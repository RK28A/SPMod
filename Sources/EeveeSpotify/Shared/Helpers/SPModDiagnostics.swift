import Foundation

enum SPModDiagnostics {
    private static let lock = NSLock()
    private static var entries: [String] = []

    static func record(_ message: String) {
        lock.lock()
        if entries.count < 200 {
            entries.append(message)
        }
        lock.unlock()
        NSLog("[SPMod] Hook skipped: %@", message)
    }

    static var failedHooks: [String] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }
}
