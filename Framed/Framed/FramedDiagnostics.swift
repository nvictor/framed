import Combine
import Foundation
import OSLog

@MainActor
final class FramedDiagnostics: ObservableObject {
    static let shared = FramedDiagnostics()

    @Published private(set) var entries: [String] = []

    private let logger = Logger(subsystem: "com.mellowfleet.Framed", category: "Resize")
    private let maxEntries = 12

    func log(_ message: String) {
        logger.log("\(message, privacy: .public)")
        NSLog("[Framed] %@", message)
        entries.insert(message, at: 0)

        if entries.count > maxEntries {
            entries.removeLast(entries.count - maxEntries)
        }
    }
}
