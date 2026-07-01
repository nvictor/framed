import CoreGraphics
import XCTest
@testable import Framed

final class VisibleWindowGroupTests: XCTestCase {
    func testGroupsWindowsWithTheSameOwnerName() {
        let windows = [
            makeWindow(id: 1, ownerName: "Safari", title: "One"),
            makeWindow(id: 2, ownerName: "Notes", title: "Two"),
            makeWindow(id: 3, ownerName: "Safari", title: "Three")
        ]

        let groups = VisibleWindowGroup.groups(from: windows)

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].ownerName, "Safari")
        XCTAssertEqual(groups[0].windows.map(\.id), [1, 3])
        XCTAssertEqual(groups[1].ownerName, "Notes")
        XCTAssertEqual(groups[1].windows.map(\.id), [2])
    }

    func testGroupsPreserveFirstSeenAppOrder() {
        let windows = [
            makeWindow(id: 1, ownerName: "Notes"),
            makeWindow(id: 2, ownerName: "Safari"),
            makeWindow(id: 3, ownerName: "Finder"),
            makeWindow(id: 4, ownerName: "Safari"),
            makeWindow(id: 5, ownerName: "Notes")
        ]

        let groups = VisibleWindowGroup.groups(from: windows)

        XCTAssertEqual(groups.map(\.ownerName), ["Notes", "Safari", "Finder"])
    }

    func testWindowsInsideGroupPreserveVisibleWindowOrder() {
        let windows = [
            makeWindow(id: 7, ownerName: "Safari"),
            makeWindow(id: 4, ownerName: "Safari"),
            makeWindow(id: 9, ownerName: "Safari")
        ]

        let groups = VisibleWindowGroup.groups(from: windows)

        XCTAssertEqual(groups.first?.windows.map(\.id), [7, 4, 9])
    }

    func testEmptyWindowsProduceNoGroups() {
        XCTAssertEqual(VisibleWindowGroup.groups(from: []), [])
    }

    func testSingleWindowAppsProduceGroups() {
        let windows = [
            makeWindow(id: 1, ownerName: "Notes"),
            makeWindow(id: 2, ownerName: "Safari"),
            makeWindow(id: 3, ownerName: "Finder")
        ]

        let groups = VisibleWindowGroup.groups(from: windows)

        XCTAssertEqual(groups.map(\.ownerName), ["Notes", "Safari", "Finder"])
        XCTAssertEqual(groups.map(\.windowCount), [1, 1, 1])
    }

    func testMenuDisplayNameUsesSingularAndPluralWindowLabels() {
        let oneWindowGroup = VisibleWindowGroup(ownerName: "Notes", windows: [
            makeWindow(id: 1, ownerName: "Notes")
        ])
        let twoWindowGroup = VisibleWindowGroup(ownerName: "Safari", windows: [
            makeWindow(id: 2, ownerName: "Safari"),
            makeWindow(id: 3, ownerName: "Safari")
        ])

        XCTAssertEqual(oneWindowGroup.menuDisplayName, "Notes - 1 window")
        XCTAssertEqual(twoWindowGroup.menuDisplayName, "Safari - 2 windows")
    }

    private func makeWindow(
        id: CGWindowID,
        ownerName: String,
        title: String = "",
        pid: pid_t = 100
    ) -> VisibleWindow {
        VisibleWindow(
            id: id,
            ownerName: ownerName,
            title: title,
            pid: pid,
            frame: CGRect(x: Int(id) * 10, y: Int(id) * 20, width: 800, height: 600)
        )
    }
}
