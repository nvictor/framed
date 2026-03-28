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

    func resize(_ visibleWindow: VisibleWindow?, to preset: AspectRatioPreset) -> ResizeResult {
        guard let visibleWindow else {
            log("Resize aborted: no window selected.")
            return .noWindowSelected
        }

        guard ensureAccessibilityPermission(prompt: true) else {
            log("Resize aborted: Accessibility permission missing.")
            return .needsAccessibilityPermission
        }

        guard let match = matchingWindow(for: visibleWindow) else {
            log("Resize aborted: no AX window matched \(visibleWindow.displayName).")
            return .noMatchingWindow
        }

        let window = match.window
        prepareWindowForResize(pid: visibleWindow.pid, window: window)

        guard sizeAttributeAppearsResizable(for: window, windowName: visibleWindow.displayName) else {
            return .windowNotResizable
        }

        guard let frame = copyFrame(of: window) else {
            log("Resize aborted: unable to read AX frame for \(visibleWindow.displayName).")
            return .cannotReadWindowFrame
        }

        let targetVisibleArea = visibleArea(for: visibleWindow.frame)
        let resizedFrame: CGRect
        if let targetVisibleArea {
            resizedFrame = WindowResizeMath.resizedFrameFittingVisibleArea(frame, preset: preset, visibleArea: targetVisibleArea)
            log("Using visible area \(targetVisibleArea.debugSummary) for \(visibleWindow.displayName).")
        } else {
            resizedFrame = WindowResizeMath.resizedFrameKeepingWidthCentered(frame, preset: preset)
            log("No containing screen found for \(visibleWindow.displayName); falling back to unconstrained resize.")
        }
        guard !resizedFrame.equalTo(frame) else {
            log("No-op resize: \(visibleWindow.displayName) already matches \(preset.title) with frame \(frame.debugSummary).")
            return .alreadyAtRatio(preset)
        }

        log("AX match frame \(frame.debugSummary) -> target \(resizedFrame.debugSummary).")
        guard let finalSize = resolvedSize(
            for: window,
            originalSize: frame.size,
            targetSize: resizedFrame.size,
            preset: preset,
            visibleArea: targetVisibleArea,
            windowName: visibleWindow.displayName
        ) else {
            return .resizeNotApplied(observedFrame: copyFrame(of: window))
        }

        let finalFrame = WindowResizeMath.centeredFrame(
            around: frame,
            size: finalSize,
            visibleArea: targetVisibleArea
        )

        let positionError = setPosition(finalFrame.origin, for: window)
        guard positionError == .success else {
            log("AX position write failed with error \(positionError.rawValue).")
            return .cannotWritePosition(positionError)
        }

        if let observedAXFrame = verifiedAXFrame(for: window, targetFrame: finalFrame) {
            log("AX read-back after resize for \(visibleWindow.displayName): \(observedAXFrame.debugSummary).")
        } else {
            log("AX read-back after resize for \(visibleWindow.displayName) was unavailable.")
        }

        let observedScreenFrame = verifiedVisibleFrame(
            for: visibleWindow.id,
            targetFrame: finalFrame,
            originalFrame: visibleWindow.frame
        )
        guard let observedScreenFrame else {
            log("Resize writes completed for \(visibleWindow.displayName), but the window could not be confirmed on screen.")
            return .resizeNotApplied(observedFrame: nil)
        }

        guard framesMatch(observedScreenFrame, finalFrame) else {
            log("Resize writes completed for \(visibleWindow.displayName), but WindowServer reported \(observedScreenFrame.debugSummary) instead of \(finalFrame.debugSummary).")
            return .resizeNotApplied(observedFrame: observedScreenFrame)
        }

        log("Resize verified on screen for \(visibleWindow.displayName) at \(observedScreenFrame.debugSummary).")
        return .success(preset)
    }

    private func ensureAccessibilityPermission(prompt: Bool) -> Bool {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt
        ] as CFDictionary

        return AXIsProcessTrustedWithOptions(options)
    }

    private func matchingWindow(for visibleWindow: VisibleWindow) -> (window: AXUIElement, app: AXUIElement)? {
        let app = AXUIElementCreateApplication(visibleWindow.pid)

        var windowsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsValue) == .success,
              let windows = windowsValue as? [AXUIElement]
        else {
            log("AX window lookup failed for pid \(visibleWindow.pid).")
            return nil
        }

        log("AX window lookup for \(visibleWindow.displayName) returned \(windows.count) app windows.")

        let normalizedSelectedTitle = normalizedTitle(visibleWindow.title)
        let matchingCandidates = windows.compactMap { window -> (window: AXUIElement, score: Int)? in
            guard let frame = copyFrame(of: window) else {
                log("Skipped AX candidate because frame could not be read.")
                return nil
            }

            let title = copyTitle(of: window)
            let normalizedWindowTitle = normalizedTitle(title)
            let frameScore = frameMatchScore(lhs: frame, rhs: visibleWindow.frame)
            let titleScore = normalizedSelectedTitle.isEmpty ? 0 : (normalizedSelectedTitle == normalizedWindowTitle ? 100 : 0)
            let score = titleScore + frameScore

            log("AX candidate title='\(title)' frame=\(frame.debugSummary) score=\(score).")

            guard frameScore > 0 || titleScore > 0 else {
                return nil
            }

            return (window, score)
        }

        if let bestMatch = matchingCandidates.max(by: { $0.score < $1.score }) {
            log("Selected AX candidate with score \(bestMatch.score).")
            return (bestMatch.window, app)
        }

        log("No AX candidate scored above zero for \(visibleWindow.displayName).")
        return nil
    }

    private func prepareWindowForResize(pid: pid_t, window: AXUIElement) {
        if let app = NSRunningApplication(processIdentifier: pid) {
            app.activate()
        }

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

            guard let observedSize = sizeWrite.observedSize else {
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
                log("AX size write was acknowledged but the size remained unchanged for \(windowName).")
                return nil
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

    private func frameMatchScore(lhs: CGRect, rhs: CGRect) -> Int {
        let originTolerance: CGFloat = 6
        let sizeTolerance: CGFloat = 6

        let originMatches = abs(lhs.origin.x - rhs.origin.x) <= originTolerance &&
            abs(lhs.origin.y - rhs.origin.y) <= originTolerance
        let sizeMatches = abs(lhs.size.width - rhs.size.width) <= sizeTolerance &&
            abs(lhs.size.height - rhs.size.height) <= sizeTolerance

        if originMatches && sizeMatches {
            return 200
        }

        let centerMatches = abs(lhs.midX - rhs.midX) <= originTolerance &&
            abs(lhs.midY - rhs.midY) <= originTolerance

        if centerMatches && sizeMatches {
            return 150
        }

        if centerMatches || sizeMatches {
            return 75
        }

        return 0
    }

    private func normalizedTitle(_ title: String) -> String {
        title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
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
        let attempts = 5
        let delay: useconds_t = 50_000

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
