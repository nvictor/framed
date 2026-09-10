import XCTest
@testable import Framed

final class ResizeFeedbackGeometryTests: XCTestCase {
    func testTopLeftCGRectFlipsToBottomLeftAppKitRect() {
        let cg = CGRect(x: 200, y: 0, width: 800, height: 450)

        let cocoa = ResizeFeedbackGeometry.cocoaRect(fromCG: cg, primaryScreenMaxY: 900)

        XCTAssertEqual(cocoa, CGRect(x: 200, y: 450, width: 800, height: 450))
    }

    func testFullScreenRectRoundTripsToTheOrigin() {
        let cg = CGRect(x: 0, y: 0, width: 1512, height: 944)

        let cocoa = ResizeFeedbackGeometry.cocoaRect(fromCG: cg, primaryScreenMaxY: 944)

        XCTAssertEqual(cocoa, CGRect(x: 0, y: 0, width: 1512, height: 944))
    }

    func testRectOnADisplayLeftOfPrimaryKeepsNegativeXAndFlipsY() {
        // Secondary display sitting to the left of and above the primary.
        let cg = CGRect(x: -1440, y: -200, width: 600, height: 400)

        let cocoa = ResizeFeedbackGeometry.cocoaRect(fromCG: cg, primaryScreenMaxY: 900)

        XCTAssertEqual(cocoa.origin.x, -1440)
        XCTAssertEqual(cocoa.origin.y, 900 - (-200) - 400) // 700
        XCTAssertEqual(cocoa.size, CGSize(width: 600, height: 400))
    }
}
