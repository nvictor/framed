import CoreGraphics
import Foundation

enum WindowMatching {
    static func normalizedTitle(_ title: String) -> String {
        title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    static func frameMatchScore(lhs: CGRect, rhs: CGRect) -> Int {
        let originTolerance: CGFloat = 6
        let sizeTolerance: CGFloat = 6

        let originMatches = abs(lhs.origin.x - rhs.origin.x) <= originTolerance &&
            abs(lhs.origin.y - rhs.origin.y) <= originTolerance
        let sizeMatches = abs(lhs.size.width - rhs.size.width) <= sizeTolerance &&
            abs(lhs.size.height - rhs.size.height) <= sizeTolerance

        if originMatches && sizeMatches {
            return 200
        }

        let centerMatches = abs(lhs.midX - rhs.midX) <= originTolerance &&
            abs(lhs.midY - rhs.midY) <= originTolerance

        if centerMatches && sizeMatches {
            return 150
        }

        if centerMatches || sizeMatches {
            return 75
        }

        return 0
    }

    static func score(candidateFrame: CGRect, candidateTitle: String, against target: VisibleWindow) -> Int {
        let normalizedTarget = normalizedTitle(target.title)
        let frameScore = frameMatchScore(lhs: candidateFrame, rhs: target.frame)
        let titleScore = normalizedTarget.isEmpty
            ? 0
            : (normalizedTarget == normalizedTitle(candidateTitle) ? 100 : 0)
        return titleScore + frameScore
    }

    /// Picks the highest-scoring candidate for `target`, ignoring any index in
    /// `excluding` (AX windows already claimed earlier in the same group pass).
    /// Ties keep the earliest candidate, matching the previous `max(by:)` behavior.
    static func bestCandidateIndex(
        for target: VisibleWindow,
        candidates: [(frame: CGRect, title: String)],
        excluding: Set<Int> = []
    ) -> Int? {
        var best: (index: Int, score: Int)?

        for (index, candidate) in candidates.enumerated() {
            if excluding.contains(index) {
                continue
            }

            let candidateScore = score(
                candidateFrame: candidate.frame,
                candidateTitle: candidate.title,
                against: target
            )

            guard candidateScore > 0 else {
                continue
            }

            if let best, best.score >= candidateScore {
                continue
            }

            best = (index, candidateScore)
        }

        return best?.index
    }
}
