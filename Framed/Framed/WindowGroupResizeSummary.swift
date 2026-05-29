import Foundation

struct WindowGroupResizeSummary {
    let appName: String
    let windowCount: Int
    let completedCount: Int
    let preset: AspectRatioPreset
    let firstFailure: ResizeResult?

    var message: String {
        if completedCount == windowCount {
            return "Resized \(windowCount) \(appName) \(windowLabel(for: windowCount)) to \(preset.title)."
        }

        if completedCount > 0 {
            return "Resized \(completedCount) of \(windowCount) \(appName) \(windowLabel(for: windowCount)) to \(preset.title)."
        }

        if let firstFailure {
            return "\(appName): \(firstFailure.message)"
        }

        return "\(appName): No windows were resized."
    }

    init(appName: String, windowCount: Int, preset: AspectRatioPreset, results: [ResizeResult]) {
        self.appName = appName
        self.windowCount = windowCount
        self.preset = preset
        self.completedCount = results.filter(\.countsAsCompletedGroupResize).count
        self.firstFailure = results.first { !$0.countsAsCompletedGroupResize }
    }

    private func windowLabel(for count: Int) -> String {
        count == 1 ? "window" : "windows"
    }
}

extension ResizeResult {
    var countsAsCompletedGroupResize: Bool {
        switch self {
        case .success, .alreadyAtRatio:
            return true
        case .needsAccessibilityPermission,
             .noWindowSelected,
             .noMatchingWindow,
             .cannotReadWindowFrame,
             .windowNotResizable,
             .cannotWriteSize,
             .cannotWritePosition,
             .resizeNotApplied:
            return false
        }
    }

    var requiresAccessibilityPermission: Bool {
        if case .needsAccessibilityPermission = self {
            return true
        }

        return false
    }
}
