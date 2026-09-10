import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

struct WindowResizer {
    func visibleWindows() -> [VisibleWindow] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowInfoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            log("CGWindowListCopyWindowInfo returned no window info.")
            return []
        }

        let windows = windowInfoList.compactMap { info -> VisibleWindow? in
            guard let ownerName = info[kCGWindowOwnerName as String] as? String,
                  let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID != getpid(),
                  let windowNumber = info[kCGWindowNumber as String] as? CGWindowID,
                  let boundsValue = info[kCGWindowBounds as String],
                  let alpha = info[kCGWindowAlpha as String] as? Double
            else {
                return nil
            }

            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            guard layer == 0, alpha > 0 else {
                return nil
            }

            let boundsObject = boundsValue as CFTypeRef
            guard CFGetTypeID(boundsObject) == CFDictionaryGetTypeID() else {
                return nil
            }
            let boundsDictionary = boundsObject as! CFDictionary

            var frame = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(boundsDictionary, &frame),
                  frame.width >= 80,
                  frame.height >= 80
            else {
                return nil
            }

            let title = (info[kCGWindowName as String] as? String) ?? ""

            return VisibleWindow(
                id: windowNumber,
                ownerName: ownerName,
                title: title,
                pid: ownerPID,
                frame: frame
            )
        }

        log("Window enumeration found \(windows.count) visible windows.")
        return windows
    }

    func accessibilityPermissionGranted() -> Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    func requestAccessibilityPermission() -> Bool {
        ensureAccessibilityPermission(prompt: true)
    }

    func resize(_ visibleWindow: VisibleWindow?, to preset: AspectRatioPreset, widthRatio: CGFloat? = nil) -> ResizeResult {
        guard let visibleWindow else {
            log("Resize aborted: no window selected.")
            return .noWindowSelected
        }

        return performResize(
            visibleWindow,
            to: preset,
            widthRatio: widthRatio,
            excluding: [],
            placedFrames: []
        ).result
    }

    /// Resizes every window in a group in one pass, making sure each AX window is
    /// claimed at most once and that windows which would land on top of each
    /// other are fanned out instead. Each outcome carries the on-screen frame
    /// where pass/fail feedback should be drawn.
    func resize(group windows: [VisibleWindow], to preset: AspectRatioPreset, widthRatio: CGFloat?) -> [WindowResizeOutcome] {
        var consumed: [AXUIElement] = []
        var placed: [CGRect] = []
        var outcomes: [WindowResizeOutcome] = []

        for window in windows {
            let step = performResize(
                window,
                to: preset,
                widthRatio: widthRatio,
                excluding: consumed,
                placedFrames: placed
            )

            if let matchedWindow = step.matchedWindow {
                consumed.append(matchedWindow)
            }

            let outcome = WindowResizeOutcome(window: window, result: step.result, frame: step.drawFrame)
            if outcome.didResize {
                placed.append(step.drawFrame)
            }

            outcomes.append(outcome)

            if step.result.requiresAccessibilityPermission {
                break
            }
        }

        return outcomes
    }

    private func performResize(
        _ visibleWindow: VisibleWindow,
        to preset: AspectRatioPreset,
        widthRatio: CGFloat?,
        excluding consumedWindows: [AXUIElement],
        placedFrames: [CGRect]
    ) -> (result: ResizeResult, matchedWindow: AXUIElement?, drawFrame: CGRect) {
        guard accessibilityPermissionGranted() else {
            log("Resize aborted: Accessibility permission missing.")
            return (.needsAccessibilityPermission, nil, visibleWindow.frame)
        }

        // Electron / Catalyst apps often expose no AX windows until they are
        // frontmost, so activate before matching and retry once.
        activateApp(pid: visibleWindow.pid)

        var match = matchingWindow(for: visibleWindow, excluding: consumedWindows)
        if match == nil {
            usleep(120_000)
            match = matchingWindow(for: visibleWindow, excluding: consumedWindows)
        }

        guard let match else {
            log("Resize aborted: no AX window matched \(visibleWindow.displayName).")
            return (.noMatchingWindow, nil, bestKnownFrame(for: nil, windowID: visibleWindow.id, fallback: visibleWindow.frame))
        }

        let window = match.window
        raiseWindow(window)

        guard sizeAttributeAppearsResizable(for: window, windowName: visibleWindow.displayName) else {
            return (.windowNotResizable, window, bestKnownFrame(for: window, windowID: visibleWindow.id, fallback: visibleWindow.frame))
        }

        guard let frame = copyFrame(of: window) else {
            log("Resize aborted: unable to read AX frame for \(visibleWindow.displayName).")
            return (.cannotReadWindowFrame, window, bestKnownFrame(for: window, windowID: visibleWindow.id, fallback: visibleWindow.frame))
        }

        let targetVisibleArea = visibleArea(for: visibleWindow.frame)
        let resizedFrame: CGRect
        if let widthRatio, let targetVisibleArea {
            resizedFrame = WindowResizeMath.resizedFrameForWidthRatio(frame, preset: preset, widthRatio: widthRatio, visibleArea: targetVisibleArea)
            log("Using visible area \(targetVisibleArea.debugSummary) with width ratio \(widthRatio) for \(visibleWindow.displayName).")
        } else if let targetVisibleArea {
            resizedFrame = WindowResizeMath.resizedFrameFittingVisibleArea(frame, preset: preset, visibleArea: targetVisibleArea)
            log("Using visible area \(targetVisibleArea.debugSummary) for \(visibleWindow.displayName).")
        } else {
            resizedFrame = WindowResizeMath.resizedFrameKeepingWidthCentered(frame, preset: preset)
            log("No containing screen found for \(visibleWindow.displayName); falling back to unconstrained resize.")
        }
        guard !resizedFrame.equalTo(frame) else {
            log("No-op resize: \(visibleWindow.displayName) already matches \(preset.title) with frame \(frame.debugSummary).")
            return (.alreadyAtRatio(preset), window, frame)
        }

        // Position first: pull the window fully onto the target area before
        // asking for the new size, so the app/WindowServer does not clamp the
        // width to keep an off-screen window visible.
        let positioningFrame = WindowResizeMath.offsetToAvoidOverlap(
            WindowResizeMath.centeredFrame(around: frame, size: resizedFrame.size, visibleArea: targetVisibleArea),
            avoiding: placedFrames,
            visibleArea: targetVisibleArea
        )
        _ = setPosition(positioningFrame.origin, for: window)
        usleep(40_000)

        log("AX match frame \(frame.debugSummary) -> target \(resizedFrame.debugSummary).")
        guard let finalSize = resolvedSize(
            for: window,
            originalSize: frame.size,
            targetSize: positioningFrame.size,
            preset: preset,
            visibleArea: targetVisibleArea,
            windowName: visibleWindow.displayName
        ) else {
            return (.resizeNotApplied(observedFrame: copyFrame(of: window)), window, bestKnownFrame(for: window, windowID: visibleWindow.id, fallback: visibleWindow.frame))
        }

        let finalFrame = WindowResizeMath.offsetToAvoidOverlap(
            WindowResizeMath.centeredFrame(around: positioningFrame, size: finalSize, visibleArea: targetVisibleArea),
            avoiding: placedFrames,
            visibleArea: targetVisibleArea
        )

        let positionError = setPosition(finalFrame.origin, for: window)
        guard positionError == .success else {
            log("AX position write failed with error \(positionError.rawValue).")
            return (.cannotWritePosition(positionError), window, bestKnownFrame(for: window, windowID: visibleWindow.id, fallback: visibleWindow.frame))
        }

        let axFrame = verifiedAXFrame(for: window, targetFrame: finalFrame)
        let axConfirmed = axFrame.map { framesMatch($0, finalFrame) } ?? false
        if let axFrame {
            log("AX read-back after resize for \(visibleWindow.displayName): \(axFrame.debugSummary) (matched: \(axConfirmed)).")
        } else {
            log("AX read-back after resize for \(visibleWindow.displayName) was unavailable.")
        }

        let observedScreenFrame = verifiedVisibleFrame(
            for: visibleWindow.id,
            targetFrame: finalFrame,
            originalFrame: visibleWindow.frame
        )

        guard let observedScreenFrame else {
            if axConfirmed {
                log("WindowServer confirmation lagged for \(visibleWindow.displayName); trusting matched AX read-back.")
                return (.success(preset), window, finalFrame)
            }
            log("Resize writes completed for \(visibleWindow.displayName), but the window could not be confirmed on screen.")
            return (.resizeNotApplied(observedFrame: nil), window, bestKnownFrame(for: window, windowID: visibleWindow.id, fallback: visibleWindow.frame))
        }

        guard framesMatch(observedScreenFrame, finalFrame) else {
            if axConfirmed {
                log("WindowServer reported \(observedScreenFrame.debugSummary) for \(visibleWindow.displayName) but AX read-back matched; trusting AX.")
                return (.success(preset), window, finalFrame)
            }
            log("Resize writes completed for \(visibleWindow.displayName), but WindowServer reported \(observedScreenFrame.debugSummary) instead of \(finalFrame.debugSummary).")
            return (.resizeNotApplied(observedFrame: observedScreenFrame), window, observedScreenFrame)
        }

        log("Resize verified on screen for \(visibleWindow.displayName) at \(observedScreenFrame.debugSummary).")
        return (.success(preset), window, observedScreenFrame)
    }

    private func bestKnownFrame(for window: AXUIElement?, windowID: CGWindowID, fallback: CGRect) -> CGRect {
        if let serverFrame = currentVisibleFrame(for: windowID) {
            return serverFrame
        }
        if let window, let axFrame = copyFrame(of: window) {
            return axFrame
        }
        return fallback
    }

    private func ensureAccessibilityPermission(prompt: Bool) -> Bool {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt
        ] as CFDictionary

        return AXIsProcessTrustedWithOptions(options)
    }

    private func matchingWindow(
        for visibleWindow: VisibleWindow,
        excluding consumedWindows: [AXUIElement] = []
    ) -> (window: AXUIElement, app: AXUIElement)? {
        let app = AXUIElementCreateApplication(visibleWindow.pid)

        var windowsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsValue) == .success,
              let windows = windowsValue as? [AXUIElement]
        else {
            log("AX window lookup failed for pid \(visibleWindow.pid).")
            return nil
        }

        log("AX window lookup for \(visibleWindow.displayName) returned \(windows.count) app windows.")

        let candidates: [(element: AXUIElement, frame: CGRect, title: String)] = windows.compactMap { window in
            guard let frame = copyFrame(of: window) else {
                log("Skipped AX candidate because frame could not be read.")
                return nil
            }

            return (window, frame, copyTitle(of: window))
        }

        let excludedIndexes = Set(candidates.indices.filter { index in
            consumedWindows.contains { CFEqual($0, candidates[index].element) }
        })

        for (index, candidate) in candidates.enumerated() {
            let score = WindowMatching.score(
                candidateFrame: candidate.frame,
                candidateTitle: candidate.title,
                against: visibleWindow
            )
            let note = excludedIndexes.contains(index) ? " (already resized in this pass)" : ""
            log("AX candidate title='\(candidate.title)' frame=\(candidate.frame.debugSummary) score=\(score)\(note).")
        }

        guard let bestIndex = WindowMatching.bestCandidateIndex(
            for: visibleWindow,
            candidates: candidates.map { ($0.frame, $0.title) },
            excluding: excludedIndexes
        ) else {
            log("No AX candidate scored above zero for \(visibleWindow.displayName).")
            return nil
        }

        let best = candidates[bestIndex]
        let bestScore = WindowMatching.score(
            candidateFrame: best.frame,
            candidateTitle: best.title,
            against: visibleWindow
        )
        log("Selected AX candidate with score \(bestScore).")
        return (best.element, app)
    }

    private func activateApp(pid: pid_t) {
        if let app = NSRunningApplication(processIdentifier: pid) {
            app.activate()
            usleep(60_000)
        }
    }

    private func raiseWindow(_ window: AXUIElement) {
        let raiseError = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        if raiseError == .success {
            log("Raised target window before resize.")
        } else {
            log("Raise action returned \(raiseError.rawValue) before resize.")
        }

        usleep(50_000)
    }

    private func copyFrame(of window: AXUIElement) -> CGRect? {
        guard let size = copySize(of: window), let origin = copyPosition(of: window) else {
            return nil
        }

        return CGRect(origin: origin, size: size)
    }

    private func copySize(of window: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID()
        else {
            return nil
        }

        let axValue = value as! AXValue
        var size = CGSize.zero
        return AXValueGetValue(axValue, .cgSize, &size) ? size : nil
    }

    private func copyPosition(of window: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID()
        else {
            return nil
        }

        let axValue = value as! AXValue
        var point = CGPoint.zero
        return AXValueGetValue(axValue, .cgPoint, &point) ? point : nil
    }

    private func copyTitle(of window: AXUIElement) -> String {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &value) == .success,
              let title = value as? String
        else {
            return ""
        }

        return title
    }

    private func sizeAttributeAppearsResizable(for window: AXUIElement, windowName: String) -> Bool {
        let resizable = copyBoolAttribute("AXResizable" as CFString, of: window)
        var settable = DarwinBoolean(false)
        let settableError = AXUIElementIsAttributeSettable(window, kAXSizeAttribute as CFString, &settable)

        if let resizable {
            log("AX resizable attribute for \(windowName): \(resizable).")
        } else {
            log("AX resizable attribute for \(windowName) was unavailable.")
        }

        if settableError == .success {
            log("AX size attribute settable for \(windowName): \(settable.boolValue).")
        } else {
            log("AX size attribute settable check for \(windowName) failed with error \(settableError.rawValue).")
        }

        if let resizable, !resizable {
            return false
        }

        if settableError == .success, !settable.boolValue {
            return false
        }

        return true
    }

    private func copyBoolAttribute(_ attribute: CFString, of window: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, attribute, &value) == .success else {
            return nil
        }

        if let boolValue = value as? Bool {
            return boolValue
        }

        if let number = value as? NSNumber {
            return number.boolValue
        }

        return nil
    }

    private func setSize(_ size: CGSize, for window: AXUIElement) -> AXError {
        var size = size
        guard let axValue = AXValueCreate(.cgSize, &size) else {
            return .failure
        }

        return AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, axValue)
    }

    private func writeSize(_ size: CGSize, for window: AXUIElement) -> (error: AXError, observedSize: CGSize?) {
        let error = setSize(size, for: window)
        guard error == .success else {
            return (error, nil)
        }

        let observedSize = verifiedSize(for: window, targetSize: size)
        return (error, observedSize)
    }

    private func resolvedSize(
        for window: AXUIElement,
        originalSize: CGSize,
        targetSize: CGSize,
        preset: AspectRatioPreset,
        visibleArea: CGRect?,
        windowName: String
    ) -> CGSize? {
        let maxAttempts = 4
        var requestedSize = targetSize
        var seenRequests = Set<String>()

        for attempt in 0..<maxAttempts {
            let requestKey = "\(Int(requestedSize.width))x\(Int(requestedSize.height))"
            if !seenRequests.insert(requestKey).inserted {
                log("Stopping size correction for \(windowName) because request \(requestKey) repeated.")
                return nil
            }

            let sizeWrite = writeSize(requestedSize, for: window)
            guard sizeWrite.error == .success else {
                if attempt == 0 {
                    log("AX size write failed with error \(sizeWrite.error.rawValue).")
                } else {
                    log("Corrective AX size write failed with error \(sizeWrite.error.rawValue).")
                }
                return nil
            }

            guard var observedSize = sizeWrite.observedSize else {
                if attempt == 0 {
                    log("Observed AX size after write was unavailable.")
                } else {
                    log("Observed AX size after corrective write was unavailable.")
                }
                return nil
            }

            if attempt == 0 {
                log("Observed AX size after write: w:\(Int(observedSize.width)) h:\(Int(observedSize.height)).")
            } else {
                log("Observed AX size after corrective write: w:\(Int(observedSize.width)) h:\(Int(observedSize.height)).")
            }

            if sizesMatch(observedSize, originalSize) {
                guard attempt == 0 else {
                    log("AX size write was acknowledged but the size remained unchanged for \(windowName).")
                    return nil
                }

                log("AX size write for \(windowName) was acknowledged but unchanged; retrying after a longer delay.")
                usleep(150_000)
                let retry = writeSize(requestedSize, for: window)
                guard retry.error == .success,
                      let retrySize = retry.observedSize,
                      !sizesMatch(retrySize, originalSize)
                else {
                    log("AX size write was acknowledged but the size remained unchanged for \(windowName).")
                    return nil
                }
                observedSize = retrySize
                log("Retry AX size write for \(windowName) took: w:\(Int(observedSize.width)) h:\(Int(observedSize.height)).")
            }

            if ratioMatches(observedSize, preset: preset) {
                return observedSize
            }

            let correctedSize = WindowResizeMath.nextCorrectionSize(
                from: observedSize,
                toward: requestedSize,
                preset: preset,
                visibleArea: visibleArea
            )
            log("Correcting toward exact \(preset.title) using accepted size box w:\(Int(observedSize.width)) h:\(Int(observedSize.height)) -> w:\(Int(correctedSize.width)) h:\(Int(correctedSize.height)).")

            if sizesMatch(correctedSize, requestedSize) {
                log("Corrective size write did not reach the exact ratio for \(windowName).")
                return nil
            }

            requestedSize = correctedSize
        }

        log("Size correction exhausted attempts for \(windowName).")
        return nil
    }

    private func setPosition(_ position: CGPoint, for window: AXUIElement) -> AXError {
        var position = position
        guard let axValue = AXValueCreate(.cgPoint, &position) else {
            return .failure
        }

        return AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, axValue)
    }

    private func visibleArea(for frame: CGRect) -> CGRect? {
        let bestScreen = NSScreen.screens.max { lhs, rhs in
            let lhsArea = lhs.visibleFrame.intersection(frame).area
            let rhsArea = rhs.visibleFrame.intersection(frame).area
            return lhsArea < rhsArea
        }

        guard let bestScreen, bestScreen.visibleFrame.intersection(frame).area > 0 else {
            return nil
        }

        return bestScreen.visibleFrame
    }

    private func verifiedAXFrame(for window: AXUIElement, targetFrame: CGRect) -> CGRect? {
        let attempts = 5
        let delay: useconds_t = 50_000

        for attempt in 0..<attempts {
            if let frame = copyFrame(of: window) {
                if framesMatch(frame, targetFrame) {
                    return frame
                }

                if attempt == attempts - 1 {
                    return frame
                }
            }

            usleep(delay)
        }

        return nil
    }

    private func verifiedVisibleFrame(for windowID: CGWindowID, targetFrame: CGRect, originalFrame: CGRect) -> CGRect? {
        let attempts = 8
        let delay: useconds_t = 75_000

        for attempt in 0..<attempts {
            if let frame = currentVisibleFrame(for: windowID) {
                if framesMatch(frame, targetFrame) {
                    return frame
                }

                if attempt == attempts - 1 {
                    return frame
                }
            } else if attempt == attempts - 1 {
                return nil
            }

            if attempt == 0 {
                log("WindowServer confirmation pending. Original frame was \(originalFrame.debugSummary), target is \(targetFrame.debugSummary).")
            }

            usleep(delay)
        }

        return nil
    }

    private func currentVisibleFrame(for windowID: CGWindowID) -> CGRect? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowInfoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        guard let info = windowInfoList.first(where: {
            ($0[kCGWindowNumber as String] as? CGWindowID) == windowID
        }) else {
            return nil
        }

        guard let boundsValue = info[kCGWindowBounds as String] else {
            return nil
        }

        let boundsObject = boundsValue as CFTypeRef
        guard CFGetTypeID(boundsObject) == CFDictionaryGetTypeID() else {
            return nil
        }

        let boundsDictionary = boundsObject as! CFDictionary
        var frame = CGRect.zero
        return CGRectMakeWithDictionaryRepresentation(boundsDictionary, &frame) ? frame : nil
    }

    private func verifiedSize(for window: AXUIElement, targetSize: CGSize) -> CGSize? {
        let attempts = 8
        let delay: useconds_t = 60_000

        for attempt in 0..<attempts {
            if let size = copySize(of: window) {
                if sizesMatch(size, targetSize) {
                    return size
                }

                if attempt == attempts - 1 {
                    return size
                }
            }

            usleep(delay)
        }

        return nil
    }

    private func framesMatch(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        let tolerance: CGFloat = 6

        return abs(lhs.origin.x - rhs.origin.x) <= tolerance &&
            abs(lhs.origin.y - rhs.origin.y) <= tolerance &&
            abs(lhs.size.width - rhs.size.width) <= tolerance &&
            abs(lhs.size.height - rhs.size.height) <= tolerance
    }

    private func sizesMatch(_ lhs: CGSize, _ rhs: CGSize) -> Bool {
        let tolerance: CGFloat = 6
        return abs(lhs.width - rhs.width) <= tolerance &&
            abs(lhs.height - rhs.height) <= tolerance
    }

    private func ratioMatches(_ size: CGSize, preset: AspectRatioPreset) -> Bool {
        let expectedWidth = size.height * preset.widthComponent / preset.heightComponent
        return abs(size.width - expectedWidth) <= 6
    }

    private func log(_ message: String) {
        Task { @MainActor in
            FramedDiagnostics.shared.log(message)
        }
    }
}
