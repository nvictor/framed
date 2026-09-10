import XCTest
@testable import Framed

final class WindowGroupResizeSummaryTests: XCTestCase {
    func testAllSuccessfulResultsReportFullGroupResize() {
        let summary = WindowGroupResizeSummary(
            appName: "Safari",
            windowCount: 2,
            preset: .sixteenByNine,
            results: [.success(.sixteenByNine), .alreadyAtRatio(.sixteenByNine)]
        )

        XCTAssertEqual(summary.completedCount, 2)
        XCTAssertEqual(summary.message, "Resized 2 Safari windows to 16:9.")
    }

    func testMixedResultsReportPartialGroupResizeWithFailureReason() {
        let summary = WindowGroupResizeSummary(
            appName: "Safari",
            windowCount: 3,
            preset: .fourByThree,
            results: [.success(.fourByThree), .noMatchingWindow, .alreadyAtRatio(.fourByThree)]
        )

        XCTAssertEqual(summary.completedCount, 2)
        XCTAssertEqual(
            summary.message,
            "Resized 2 of 3 Safari windows to 4:3. Framed could not match that visible window in Accessibility."
        )
    }

    func testPartialResizeSurfacesTheResizeNotAppliedReason() {
        let summary = WindowGroupResizeSummary(
            appName: "Teams",
            windowCount: 2,
            preset: .sixteenByNine,
            results: [.success(.sixteenByNine), .resizeNotApplied(observedFrame: nil)]
        )

        XCTAssertEqual(summary.completedCount, 1)
        XCTAssertTrue(
            summary.message.contains("could not confirm that the window changed"),
            "expected the failure reason in \(summary.message)"
        )
    }

    func testNoSuccessfulResultsReportsFirstFailure() {
        let summary = WindowGroupResizeSummary(
            appName: "Safari",
            windowCount: 2,
            preset: .oneByOne,
            results: [.noMatchingWindow, .windowNotResizable]
        )

        XCTAssertEqual(summary.completedCount, 0)
        XCTAssertEqual(summary.message, "Safari: Framed could not match that visible window in Accessibility.")
    }

    func testAccessibilityFailureCanShortCircuitGroupResize() {
        XCTAssertTrue(ResizeResult.needsAccessibilityPermission.requiresAccessibilityPermission)
        XCTAssertFalse(ResizeResult.noMatchingWindow.requiresAccessibilityPermission)
    }

    func testSingularWindowLabelForOneWindowGroup() {
        let summary = WindowGroupResizeSummary(
            appName: "Notes",
            windowCount: 1,
            preset: .nineBySixteen,
            results: [.success(.nineBySixteen)]
        )

        XCTAssertEqual(summary.message, "Resized 1 Notes window to 9:16.")
    }
}
