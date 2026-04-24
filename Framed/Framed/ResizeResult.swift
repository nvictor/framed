import Foundation
import ApplicationServices
import CoreGraphics

enum ResizeResult {
    case success(AspectRatioPreset)
    case alreadyAtRatio(AspectRatioPreset)
    case needsAccessibilityPermission
    case noWindowSelected
    case noMatchingWindow
    case cannotReadWindowFrame
    case windowNotResizable
    case cannotWriteSize(AXError)
    case cannotWritePosition(AXError)
    case resizeNotApplied(observedFrame: CGRect?)

    var message: String {
        switch self {
        case .success(let preset):
            return "Resized selected window to \(preset.title)."
        case .alreadyAtRatio(let preset):
            return "Selected window is already \(preset.title)."
        case .needsAccessibilityPermission:
            return "Grant Accessibility access to the current Framed app, then relaunch it once."
        case .noWindowSelected:
            return "Select a visible window before resizing."
        case .noMatchingWindow:
            return "Framed could not match that visible window in Accessibility."
        case .cannotReadWindowFrame:
            return "Framed could not read the selected window geometry."
        case .windowNotResizable:
            return "That window does not expose a resizable size attribute to Framed."
        case .cannotWriteSize(let error):
            return "Framed could not update the window size (\(error.rawValue))."
        case .cannotWritePosition(let error):
            return "Framed resized the window but could not recenter it (\(error.rawValue))."
        case .resizeNotApplied(let observedFrame):
            if let observedFrame {
                return "Framed wrote the resize request, but the window stayed at \(observedFrame.debugSummary)."
            }

            return "Framed wrote the resize request, but could not confirm that the window changed."
        }
    }
}
