import CoreGraphics
import Foundation

enum ScreenWidthRatioPreset: String, CaseIterable, Identifiable {
    case half = "50%"
    case goldenRatio = "61.8%"
    case ninety = "90%"

    var id: String { rawValue }

    var title: String { rawValue }

    var ratio: CGFloat {
        switch self {
        case .half:
            return 0.5
        case .goldenRatio:
            return 0.618
        case .ninety:
            return 0.9
        }
    }
}
