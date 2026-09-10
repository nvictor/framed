import CoreGraphics
import Foundation

/// The result of trying to resize one window in a group pass, plus the on-screen
/// frame where feedback (the pass/fail border) should be drawn.
struct WindowResizeOutcome {
    let window: VisibleWindow
    let result: ResizeResult
    let frame: CGRect

    var didResize: Bool {
        result.countsAsCompletedGroupResize
    }
}
