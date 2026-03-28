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
