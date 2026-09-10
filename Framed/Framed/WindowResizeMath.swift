import CoreGraphics

enum WindowResizeMath {
    static func resizedFrameKeepingWidthCentered(_ frame: CGRect, preset: AspectRatioPreset) -> CGRect {
        let newHeight = round(frame.width * preset.heightComponent / preset.widthComponent)
        let centerX = frame.midX
        let centerY = frame.midY

        return CGRect(
            x: round(centerX - frame.width / 2),
            y: round(centerY - newHeight / 2),
            width: round(frame.width),
            height: newHeight
        )
    }

    static func resizedFrameFittingVisibleArea(
        _ frame: CGRect,
        preset: AspectRatioPreset,
        visibleArea: CGRect
    ) -> CGRect {
        let desiredWidth = round(frame.width)
        let desiredHeight = round(desiredWidth * preset.heightComponent / preset.widthComponent)

        let maxWidthForHeight = floor(visibleArea.height * preset.widthComponent / preset.heightComponent)
        let fittedWidth = min(desiredWidth, floor(visibleArea.width), maxWidthForHeight)
        let fittedHeight = round(fittedWidth * preset.heightComponent / preset.widthComponent)

        let width = max(1, fittedWidth)
        let height = max(1, min(fittedHeight, floor(visibleArea.height)))
        let centerX = frame.midX
        let centerY = frame.midY

        let proposedX = round(centerX - width / 2)
        let proposedY = round(centerY - height / 2)
        let clampedX = min(max(proposedX, visibleArea.minX), visibleArea.maxX - width)
        let clampedY = min(max(proposedY, visibleArea.minY), visibleArea.maxY - height)

        if desiredWidth <= visibleArea.width && desiredHeight <= visibleArea.height {
            return CGRect(
                x: clampedX,
                y: clampedY,
                width: desiredWidth,
                height: desiredHeight
            )
        }

        return CGRect(
            x: round(clampedX),
            y: round(clampedY),
            width: round(width),
            height: round(height)
        )
    }

    static func resizedFrameForWidthRatio(
        _ frame: CGRect,
        preset: AspectRatioPreset,
        widthRatio: CGFloat,
        visibleArea: CGRect
    ) -> CGRect {
        let desiredWidth = round(visibleArea.width * widthRatio)

        let maxWidthForHeight = floor(visibleArea.height * preset.widthComponent / preset.heightComponent)
        let fittedWidth = min(desiredWidth, floor(visibleArea.width), maxWidthForHeight)
        let fittedHeight = round(fittedWidth * preset.heightComponent / preset.widthComponent)

        let width = max(1, fittedWidth)
        let height = max(1, min(fittedHeight, floor(visibleArea.height)))
        let centerX = frame.midX
        let centerY = frame.midY

        let proposedX = round(centerX - width / 2)
        let proposedY = round(centerY - height / 2)
        let clampedX = min(max(proposedX, visibleArea.minX), visibleArea.maxX - width)
        let clampedY = min(max(proposedY, visibleArea.minY), visibleArea.maxY - height)

        return CGRect(x: round(clampedX), y: round(clampedY), width: round(width), height: round(height))
    }

    static func aspectFitSize(in bounds: CGSize, preset: AspectRatioPreset) -> CGSize {
        let maxWidth = max(1, floor(bounds.width))
        let maxHeight = max(1, floor(bounds.height))
        let fittedWidth = min(maxWidth, floor(maxHeight * preset.widthComponent / preset.heightComponent))
        let fittedHeight = round(fittedWidth * preset.heightComponent / preset.widthComponent)

        if fittedHeight <= maxHeight {
            return CGSize(width: round(fittedWidth), height: round(fittedHeight))
        }

        let fallbackHeight = maxHeight
        let fallbackWidth = round(fallbackHeight * preset.widthComponent / preset.heightComponent)
        return CGSize(width: round(min(fallbackWidth, maxWidth)), height: round(fallbackHeight))
    }

    static func correctedSize(
        from observedSize: CGSize,
        requestedSize: CGSize,
        preset: AspectRatioPreset,
        visibleArea: CGRect?
    ) -> CGSize {
        let tolerance: CGFloat = 6

        if observedSize.height > requestedSize.height + tolerance {
            let preferredWidth = round(observedSize.height * preset.widthComponent / preset.heightComponent)
            let maxWidth = visibleArea.map { floor($0.width) } ?? preferredWidth
            let correctedWidth = min(preferredWidth, maxWidth)
            let correctedHeight = round(correctedWidth * preset.heightComponent / preset.widthComponent)
            return CGSize(width: round(correctedWidth), height: round(correctedHeight))
        }

        return aspectFitSize(in: observedSize, preset: preset)
    }

    static func nextCorrectionSize(
        from observedSize: CGSize,
        toward requestedSize: CGSize,
        preset: AspectRatioPreset,
        visibleArea: CGRect?
    ) -> CGSize {
        let tolerance: CGFloat = 6
        let maxWidth = visibleArea.map { floor($0.width) } ?? max(observedSize.width, requestedSize.width)
        let maxHeight = visibleArea.map { floor($0.height) } ?? max(observedSize.height, requestedSize.height)

        if abs(observedSize.height - requestedSize.height) > tolerance {
            let widthFromHeight = round(observedSize.height * preset.widthComponent / preset.heightComponent)
            return CGSize(
                width: round(min(maxWidth, max(1, widthFromHeight))),
                height: round(min(maxHeight, max(1, observedSize.height)))
            )
        }

        let heightFromWidth = round(observedSize.width * preset.heightComponent / preset.widthComponent)
        return CGSize(
            width: round(min(maxWidth, max(1, observedSize.width))),
            height: round(min(maxHeight, max(1, heightFromWidth)))
        )
    }

    /// Nudges `frame` diagonally until its origin no longer coincides with any
    /// frame in `placed`, so a group of windows that started stacked fans out
    /// instead of landing on the exact same spot. Bounded so it always returns.
    static func offsetToAvoidOverlap(
        _ frame: CGRect,
        avoiding placed: [CGRect],
        visibleArea: CGRect?,
        step: CGFloat = 32
    ) -> CGRect {
        guard !placed.isEmpty else {
            return frame
        }

        let collisionTolerance: CGFloat = 8

        func collides(_ candidate: CGRect) -> Bool {
            placed.contains { existing in
                abs(existing.origin.x - candidate.origin.x) <= collisionTolerance &&
                    abs(existing.origin.y - candidate.origin.y) <= collisionTolerance
            }
        }

        var result = frame
        let maxIterations = placed.count + 1

        for iteration in 0..<maxIterations {
            guard collides(result) else {
                break
            }

            var moved = CGRect(
                x: result.origin.x + step,
                y: result.origin.y + step,
                width: result.width,
                height: result.height
            )

            if let visibleArea {
                if moved.maxX > visibleArea.maxX || moved.maxY > visibleArea.maxY {
                    moved.origin.x = visibleArea.minX + step * CGFloat(iteration + 1)
                    moved.origin.y = visibleArea.minY + step * CGFloat(iteration + 1)
                }

                moved.origin.x = min(max(moved.origin.x, visibleArea.minX), visibleArea.maxX - moved.width)
                moved.origin.y = min(max(moved.origin.y, visibleArea.minY), visibleArea.maxY - moved.height)
            }

            result = moved
        }

        return CGRect(
            x: round(result.origin.x),
            y: round(result.origin.y),
            width: round(result.width),
            height: round(result.height)
        )
    }

    static func centeredFrame(
        around referenceFrame: CGRect,
        size: CGSize,
        visibleArea: CGRect?
    ) -> CGRect {
        let centerX = referenceFrame.midX
        let centerY = referenceFrame.midY
        let proposed = CGRect(
            x: round(centerX - size.width / 2),
            y: round(centerY - size.height / 2),
            width: round(size.width),
            height: round(size.height)
        )

        guard let visibleArea else {
            return proposed
        }

        let clampedX = min(max(proposed.minX, visibleArea.minX), visibleArea.maxX - proposed.width)
        let clampedY = min(max(proposed.minY, visibleArea.minY), visibleArea.maxY - proposed.height)
        return CGRect(x: round(clampedX), y: round(clampedY), width: proposed.width, height: proposed.height)
    }
}
