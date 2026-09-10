import AppKit

/// Briefly flashes a thick colored border around each window Framed just tried to
/// resize: green when it reached the target, red when it did not.
@MainActor
final class ResizeFeedbackOverlay {
    private var activeWindows: [NSWindow] = []

    private let lineWidth: CGFloat = 6
    private let cornerRadius: CGFloat = 10
    private let holdDuration: TimeInterval = 0.9
    private let fadeDuration: TimeInterval = 0.4

    func flash(_ marks: [(frame: CGRect, didResize: Bool)]) {
        let primaryScreenMaxY = NSScreen.screens.first?.frame.maxY ?? 0

        for mark in marks {
            guard !mark.frame.isEmpty, !mark.frame.isNull, !mark.frame.isInfinite else {
                continue
            }

            let cocoaFrame = ResizeFeedbackGeometry.cocoaRect(
                fromCG: mark.frame,
                primaryScreenMaxY: primaryScreenMaxY
            )

            present(frame: cocoaFrame, didResize: mark.didResize)
        }
    }

    private func present(frame: CGRect, didResize: Bool) {
        let window = NSWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        let color: NSColor = didResize ? .systemGreen : .systemRed
        window.contentView = BorderView(color: color, lineWidth: lineWidth, cornerRadius: cornerRadius)

        window.alphaValue = 1
        window.orderFrontRegardless()
        activeWindows.append(window)

        DispatchQueue.main.asyncAfter(deadline: .now() + holdDuration) { [weak self, weak window] in
            guard let self, let window else { return }

            NSAnimationContext.runAnimationGroup { context in
                context.duration = self.fadeDuration
                window.animator().alphaValue = 0
            } completionHandler: { [weak self, weak window] in
                guard let window else { return }
                window.close()
                self?.activeWindows.removeAll { $0 === window }
            }
        }
    }

    private final class BorderView: NSView {
        private let color: NSColor
        private let borderWidth: CGFloat
        private let radius: CGFloat

        init(color: NSColor, lineWidth: CGFloat, cornerRadius: CGFloat) {
            self.color = color
            self.borderWidth = lineWidth
            self.radius = cornerRadius
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func draw(_ dirtyRect: NSRect) {
            let inset = bounds.insetBy(dx: borderWidth / 2, dy: borderWidth / 2)
            let path = NSBezierPath(roundedRect: inset, xRadius: radius, yRadius: radius)
            path.lineWidth = borderWidth
            color.setStroke()
            path.stroke()
        }
    }
}
