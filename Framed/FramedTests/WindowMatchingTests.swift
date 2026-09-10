import XCTest
@testable import Framed

final class WindowMatchingTests: XCTestCase {
    private func window(
        title: String = "",
        frame: CGRect
    ) -> VisibleWindow {
        VisibleWindow(id: 1, ownerName: "Finder", title: title, pid: 42, frame: frame)
    }

    func testExactFrameMatchOutscoresSizeOnlyMatch() {
        let target = window(frame: CGRect(x: 100, y: 100, width: 800, height: 600))
        let candidates: [(frame: CGRect, title: String)] = [
            (CGRect(x: 5000, y: 5000, width: 800, height: 600), ""),
            (CGRect(x: 100, y: 100, width: 800, height: 600), ""),
        ]

        let index = WindowMatching.bestCandidateIndex(for: target, candidates: candidates)

        XCTAssertEqual(index, 1)
    }

    func testExcludedIndexIsSkippedSoTheNextWindowIsChosen() {
        let target = window(frame: CGRect(x: 100, y: 100, width: 800, height: 600))
        let candidates: [(frame: CGRect, title: String)] = [
            (CGRect(x: 100, y: 100, width: 800, height: 600), ""),
            (CGRect(x: 100, y: 100, width: 800, height: 600), ""),
        ]

        XCTAssertEqual(WindowMatching.bestCandidateIndex(for: target, candidates: candidates), 0)
        XCTAssertEqual(
            WindowMatching.bestCandidateIndex(for: target, candidates: candidates, excluding: [0]),
            1
        )
        XCTAssertNil(
            WindowMatching.bestCandidateIndex(for: target, candidates: candidates, excluding: [0, 1])
        )
    }

    func testDisjointFrameWithNoTitleDoesNotMatch() {
        let target = window(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let candidates: [(frame: CGRect, title: String)] = [
            (CGRect(x: 2000, y: 2000, width: 300, height: 200), ""),
        ]

        XCTAssertNil(WindowMatching.bestCandidateIndex(for: target, candidates: candidates))
    }

    func testMatchingTitleRescuesADisjointFrame() {
        let target = window(title: "Downloads", frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let candidates: [(frame: CGRect, title: String)] = [
            (CGRect(x: 2000, y: 2000, width: 300, height: 200), "  downloads  "),
        ]

        XCTAssertEqual(WindowMatching.bestCandidateIndex(for: target, candidates: candidates), 0)
    }
}
