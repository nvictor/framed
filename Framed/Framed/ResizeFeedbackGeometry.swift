import CoreGraphics

enum ResizeFeedbackGeometry {
    /// Converts a Core Graphics rect (top-left origin, y grows downward) into an
    /// AppKit screen rect (bottom-left origin, y grows upward).
    ///
    /// `primaryScreenMaxY` is the top edge of the primary screen in AppKit
    /// coordinates, i.e. `NSScreen.screens.first?.frame.maxY`.
    static func cocoaRect(fromCG cgRect: CGRect, primaryScreenMaxY: CGFloat) -> CGRect {
        CGRect(
            x: cgRect.origin.x,
            y: primaryScreenMaxY - cgRect.origin.y - cgRect.height,
            width: cgRect.width,
            height: cgRect.height
        )
    }
}
