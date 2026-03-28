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
}
