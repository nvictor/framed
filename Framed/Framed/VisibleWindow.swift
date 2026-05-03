import CoreGraphics
import Foundation

struct VisibleWindow: Identifiable, Equatable {
    let id: CGWindowID
    let ownerName: String
    let title: String
    let pid: pid_t
    let frame: CGRect

    var displayName: String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            return ownerName
        }

        return "\(ownerName): \(trimmedTitle)"
    }

    var dimensionSummary: String {
        "\(Int(frame.width)) x \(Int(frame.height))"
    }

    var menuDisplayName: String {
        "\(displayName) - \(dimensionSummary)"
    }
}

extension CGRect {
    var area: CGFloat {
        guard !isNull, !isEmpty else {
            return 0
        }

        return width * height
    }

    var debugSummary: String {
        "x:\(Int(origin.x)) y:\(Int(origin.y)) w:\(Int(width)) h:\(Int(height))"
    }
}
