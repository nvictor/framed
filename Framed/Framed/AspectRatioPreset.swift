import CoreGraphics
import Foundation

enum AspectRatioPreset: String, CaseIterable, Identifiable {
    case sixteenByNine = "16:9"
    case nineBySixteen = "9:16"
    case fourByThree = "4:3"
    case threeByFour = "3:4"
    case oneByOne = "1:1"

    static let `default` = AspectRatioPreset.sixteenByNine

    var id: String { rawValue }

    var title: String { rawValue }

    var widthComponent: CGFloat {
        switch self {
        case .sixteenByNine:
            return 16
        case .nineBySixteen:
            return 9
        case .fourByThree:
            return 4
        case .threeByFour:
            return 3
        case .oneByOne:
            return 1
        }
    }

    var heightComponent: CGFloat {
        switch self {
        case .sixteenByNine:
            return 9
        case .nineBySixteen:
            return 16
        case .fourByThree:
            return 3
        case .threeByFour:
            return 4
        case .oneByOne:
            return 1
        }
    }
}
