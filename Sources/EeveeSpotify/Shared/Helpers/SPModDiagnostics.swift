import Foundation

enum SPModDiagnostics {
    private static let lock = NSLock()
    private static var entries: [String] = []
    private static var requests: [String] = []
    private static var requestSet = Set<String>()

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

    static func recordRequest(_ url: URL?, source: String) {
        guard let url = url, let host = url.host else {
            return
        }
        let path = url.path
            .split(separator: "/")
            .map { component -> String in
                let value = String(component)
                if value.count > 16 && value.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil {
                    return "*"
                }
                return value
            }
            .joined(separator: "/")
        let entry = "\(source) \(host)/\(path)"

        lock.lock()
        defer { lock.unlock() }
        guard requests.count < 250, !requestSet.contains(entry) else {
            return
        }
        requestSet.insert(entry)
        requests.append(entry)
    }

    static var seenRequests: [String] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }
}
