import Foundation

enum SPModDiagnostics {
    private static let lock = NSLock()
    private static var entries: [String] = []
    private static var adLog: [String] = []
    private static var adBlockedCount = 0
    private static var requests: [String] = []
    private static var requestSet = Set<String>()

    static func record(_ message: String) {
        lock.lock()
        if entries.count < 300 {
            entries.append(message)
        }
        lock.unlock()
        NSLog("[SPMod] %@", message)
    }

    static func recordAdBlock(_ message: String) {
        lock.lock()
        adBlockedCount += 1
        if adLog.count < 120 {
            adLog.append(message)
        }
        lock.unlock()
        NSLog("[SPMod][AdBlock] %@", message)
    }

    static var failedHooks: [String] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }

    static var adBlockLog: [String] {
        lock.lock()
        defer { lock.unlock() }
        return ["blocked total: \(adBlockedCount)"] + adLog
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
