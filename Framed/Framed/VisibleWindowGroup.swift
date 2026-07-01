import Foundation

struct VisibleWindowGroup: Identifiable, Equatable {
    let ownerName: String
    let windows: [VisibleWindow]

    var id: String { ownerName }

    var windowCount: Int { windows.count }

    var menuDisplayName: String {
        "\(ownerName) - \(windowCount) \(windowCount == 1 ? "window" : "windows")"
    }

    static func groups(from windows: [VisibleWindow]) -> [VisibleWindowGroup] {
        var groups: [VisibleWindowGroup] = []
        var groupIndexesByOwnerName: [String: Int] = [:]

        for window in windows {
            if let index = groupIndexesByOwnerName[window.ownerName] {
                var groupedWindows = groups[index].windows
                groupedWindows.append(window)
                groups[index] = VisibleWindowGroup(ownerName: window.ownerName, windows: groupedWindows)
                continue
            }

            groupIndexesByOwnerName[window.ownerName] = groups.count
            groups.append(VisibleWindowGroup(ownerName: window.ownerName, windows: [window]))
        }

        return groups
    }
}
