import CoreGraphics
import Foundation

enum ScreenWidthRatioPreset: String, CaseIterable, Identifiable {
    case half = "50%"
    case goldenRatio = "61.8%"
    case ninetyFive = "95%"

    var id: String { rawValue }

    var title: String { rawValue }

    var ratio: CGFloat {
        switch self {
        case .half:
            return 0.5
        case .goldenRatio:
            return 0.618
        case .ninetyFive:
            return 0.95
        }
    }
}
