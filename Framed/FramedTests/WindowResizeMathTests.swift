import XCTest
@testable import Framed

final class WindowResizeMathTests: XCTestCase {
    func testSixteenByNineKeepsWidthAndComputesExpectedHeight() {
        let frame = CGRect(x: 100, y: 150, width: 1600, height: 900)

        let resizedFrame = WindowResizeMath.resizedFrameKeepingWidthCentered(frame, preset: .sixteenByNine)

        XCTAssertEqual(resizedFrame.width, 1600)
        XCTAssertEqual(resizedFrame.height, 900)
    }

    func testFourByThreeKeepsCenterFixed() {
        let frame = CGRect(x: 100, y: 100, width: 1200, height: 700)

        let resizedFrame = WindowResizeMath.resizedFrameKeepingWidthCentered(frame, preset: .fourByThree)

        XCTAssertEqual(resizedFrame.midX, frame.midX)
        XCTAssertEqual(resizedFrame.midY, frame.midY)
        XCTAssertEqual(resizedFrame.height, 900)
    }

    func testNineBySixteenKeepsWidthAndComputesExpectedHeight() {
        let frame = CGRect(x: 100, y: 150, width: 900, height: 900)

        let resizedFrame = WindowResizeMath.resizedFrameKeepingWidthCentered(frame, preset: .nineBySixteen)

        XCTAssertEqual(resizedFrame.width, 900)
        XCTAssertEqual(resizedFrame.height, 1600)
        XCTAssertEqual(resizedFrame.midX, frame.midX)
        XCTAssertEqual(resizedFrame.midY, frame.midY)
    }

    func testThreeByFourKeepsWidthAndComputesExpectedHeight() {
        let frame = CGRect(x: 100, y: 150, width: 900, height: 900)

        let resizedFrame = WindowResizeMath.resizedFrameKeepingWidthCentered(frame, preset: .threeByFour)

        XCTAssertEqual(resizedFrame.width, 900)
        XCTAssertEqual(resizedFrame.height, 1200)
        XCTAssertEqual(resizedFrame.midX, frame.midX)
        XCTAssertEqual(resizedFrame.midY, frame.midY)
    }

    func testOneByOneRoundsHeightForOddWidths() {
        let frame = CGRect(x: 41, y: 57, width: 801, height: 603)

        let resizedFrame = WindowResizeMath.resizedFrameKeepingWidthCentered(frame, preset: .oneByOne)

        XCTAssertEqual(resizedFrame.width, 801)
        XCTAssertEqual(resizedFrame.height, 801)
        XCTAssertEqual(resizedFrame.midX, frame.midX)
        XCTAssertEqual(resizedFrame.midY, frame.midY)
    }

    func testResizeFitsVisibleAreaWhenDesiredHeightWouldOverflow() {
        let frame = CGRect(x: 0, y: 38, width: 1470, height: 821)
        let visibleArea = CGRect(x: 0, y: 33, width: 1512, height: 840)

        let resizedFrame = WindowResizeMath.resizedFrameFittingVisibleArea(
            frame,
            preset: .fourByThree,
            visibleArea: visibleArea
        )

        XCTAssertEqual(resizedFrame, CGRect(x: 175, y: 33, width: 1120, height: 840))
    }

    func testResizeKeepsRequestedWidthWhenItAlreadyFitsVisibleArea() {
        let frame = CGRect(x: 100, y: 100, width: 1200, height: 700)
        let visibleArea = CGRect(x: 0, y: 0, width: 1400, height: 1000)

        let resizedFrame = WindowResizeMath.resizedFrameFittingVisibleArea(
            frame,
            preset: .fourByThree,
            visibleArea: visibleArea
        )

        XCTAssertEqual(resizedFrame.width, 1200)
        XCTAssertEqual(resizedFrame.height, 900)
        XCTAssertEqual(resizedFrame.midX, frame.midX)
        XCTAssertEqual(resizedFrame.midY, frame.midY)
    }

    func testPortraitResizeFitsVisibleAreaWhenDesiredHeightWouldOverflow() {
        let frame = CGRect(x: 100, y: 100, width: 900, height: 900)
        let visibleArea = CGRect(x: 0, y: 0, width: 1400, height: 1000)

        let resizedFrame = WindowResizeMath.resizedFrameFittingVisibleArea(
            frame,
            preset: .nineBySixteen,
            visibleArea: visibleArea
        )

        XCTAssertEqual(resizedFrame.width, 562)
        XCTAssertEqual(resizedFrame.height, 999)
        XCTAssertEqual(resizedFrame.midX, frame.midX)
        XCTAssertEqual(resizedFrame.midY, visibleArea.midY, accuracy: 0.5)
    }

    func testOffsetToAvoidOverlapLeavesFrameAloneWhenNothingIsPlaced() {
        let frame = CGRect(x: 100, y: 100, width: 800, height: 450)

        let result = WindowResizeMath.offsetToAvoidOverlap(frame, avoiding: [], visibleArea: nil)

        XCTAssertEqual(result, frame)
    }

    func testOffsetToAvoidOverlapShiftsByStepWhenOriginCollides() {
        let frame = CGRect(x: 100, y: 100, width: 800, height: 450)

        let result = WindowResizeMath.offsetToAvoidOverlap(
            frame,
            avoiding: [frame],
            visibleArea: nil,
            step: 32
        )

        XCTAssertEqual(result, CGRect(x: 132, y: 132, width: 800, height: 450))
    }

    func testOffsetToAvoidOverlapWrapsBackInsideVisibleAreaNearTheEdge() {
        let visibleArea = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = CGRect(x: 1350, y: 820, width: 80, height: 70)

        let result = WindowResizeMath.offsetToAvoidOverlap(
            frame,
            avoiding: [frame],
            visibleArea: visibleArea,
            step: 32
        )

        XCTAssertTrue(visibleArea.contains(result), "expected \(result) inside \(visibleArea)")
        XCTAssertNotEqual(result.origin, frame.origin)
    }

    func testOffsetToAvoidOverlapGivesStackedWindowsDistinctOrigins() {
        let base = CGRect(x: 100, y: 100, width: 800, height: 450)
        var placed: [CGRect] = []

        for _ in 0..<4 {
            let next = WindowResizeMath.offsetToAvoidOverlap(base, avoiding: placed, visibleArea: nil, step: 32)
            placed.append(next)
        }

        for i in placed.indices {
            for j in placed.indices where j > i {
                XCTAssertFalse(
                    placed[i].origin == placed[j].origin,
                    "windows \(i) and \(j) landed on the same origin \(placed[i].origin)"
                )
            }
        }
    }
}
