import Foundation

enum PrivacyCategory: String, CaseIterable, Codable, Identifiable {
    case ads
    case analytics
    case attribution
    case diagnostics
    case marketing
    case spotifyEvents

    var id: String { rawValue }

    var title: String { "privacy_category_\(rawValue)".localized }
    var effect: String { "privacy_effect_\(rawValue)".localized }

    var hosts: [String] {
        switch self {
        case .ads:
            return [
                "doubleclick.net", "googlesyndication.com", "googleadservices.com",
                "adservice.google.com", "pubads.g.doubleclick.net", "imasdk.googleapis.com"
            ]
        case .analytics:
            return [
                "app-measurement.com", "firebaselogging.googleapis.com", "firebaselogging-pa.googleapis.com",
                "google-analytics.com", "analytics.google.com", "api.mixpanel.com", "api2.amplitude.com",
                "api.amplitude.com", "api.segment.io", "cdn.segment.com"
            ]
        case .attribution:
            return [
                "adjust.com", "adjust.net", "api2.branch.io", "api.branch.io", "appsflyer.com",
                "appsflyersdk.com", "kochava.com", "singular.net", "app-adforce.jp"
            ]
        case .diagnostics:
            return [
                "crashlytics.com", "firebase-settings.crashlytics.com", "sentry.io",
                "bugsnag.com", "sessions.bugsnag.com", "instabug.com"
            ]
        case .marketing:
            return [
                "braze.com", "appboy.com", "iterable.com", "onesignal.com", "leanplum.com"
            ]
        case .spotifyEvents:
            return []
        }
    }

    var paths: [String] {
        switch self {
        case .ads:
            return ["/ads/", "/ad-logic/", "/adeventreceiver"]
        case .spotifyEvents:
            return ["gabo-receiver-service"]
        default:
            return []
        }
    }
}

enum PrivacyMode: String, CaseIterable, Codable {
    case off
    case standard
    case strong
    case custom

    var title: String { "privacy_mode_\(rawValue)".localized }

    var categories: Set<PrivacyCategory> {
        switch self {
        case .off: return []
        case .standard: return [.ads, .analytics]
        case .strong: return Set(PrivacyCategory.allCases)
        case .custom: return UserDefaults.privacyCustomCategories
        }
    }
}

extension UserDefaults {
    static let privacyModeKey = "privacyMode"
    static let privacyCustomCategoriesKey = "privacyCustomCategories"
    static let privacyStatsKey = "privacyStats"
    static let spmodLogsEnabledKey = "spmodLogsEnabled"

    static var privacyMode: PrivacyMode {
        get { container.string(forKey: privacyModeKey).flatMap(PrivacyMode.init(rawValue:)) ?? .standard }
        set { container.set(newValue.rawValue, forKey: privacyModeKey) }
    }

    static var privacyCustomCategories: Set<PrivacyCategory> {
        get {
            guard let values = container.array(forKey: privacyCustomCategoriesKey) as? [String] else {
                return [.ads, .analytics]
            }
            return Set(values.compactMap(PrivacyCategory.init(rawValue:)))
        }
        set { container.set(newValue.map(\.rawValue).sorted(), forKey: privacyCustomCategoriesKey) }
    }

    static var spmodLogsEnabled: Bool {
        get { container.object(forKey: spmodLogsEnabledKey) as? Bool ?? true }
        set { container.set(newValue, forKey: spmodLogsEnabledKey) }
    }
}

func spmodLog(_ message: @autoclosure () -> String) {
    guard UserDefaults.spmodLogsEnabled else {
        return
    }
    NSLog("[SPMod] %@", message())
}

struct PrivacyCategoryStats: Codable {
    var count: Int = 0
    var last: Date? = nil
}

enum PrivacyStatsStore {
    private static let lock = NSLock()
    private static var stats: [String: PrivacyCategoryStats] = load()
    private static var lastSave = Date.distantPast

    private static func load() -> [String: PrivacyCategoryStats] {
        guard
            let data = UserDefaults.container.data(forKey: UserDefaults.privacyStatsKey),
            let decoded = try? JSONDecoder().decode([String: PrivacyCategoryStats].self, from: data)
        else {
            return [:]
        }
        return decoded
    }

    private static func save() {
        if let data = try? JSONEncoder().encode(stats) {
            UserDefaults.container.set(data, forKey: UserDefaults.privacyStatsKey)
        }
    }

    static func record(_ category: PrivacyCategory) {
        lock.lock()
        defer { lock.unlock() }
        var entry = stats[category.rawValue] ?? PrivacyCategoryStats()
        entry.count += 1
        entry.last = Date()
        stats[category.rawValue] = entry
        if Date().timeIntervalSince(lastSave) > 10 {
            lastSave = Date()
            save()
        }
    }

    static func snapshot() -> [String: PrivacyCategoryStats] {
        lock.lock()
        defer { lock.unlock() }
        return stats
    }

    static func flush() {
        lock.lock()
        defer { lock.unlock() }
        save()
    }

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        stats = [:]
        save()
    }
}

@objc(SPModPrivacyProtocol)
final class SPModPrivacyProtocol: URLProtocol {
    private static let activeCategories: Set<PrivacyCategory> = UserDefaults.privacyMode.categories

    static func category(for url: URL?) -> PrivacyCategory? {
        guard let url = url, let host = url.host?.lowercased(), !activeCategories.isEmpty else {
            return nil
        }
        let path = url.path.lowercased()
        let isSpotify = host.hasSuffix("spotify.com") || host.hasSuffix("spotify.net")

        for category in PrivacyCategory.allCases where activeCategories.contains(category) {
            if category.hosts.contains(where: { host == $0 || host.hasSuffix(".\($0)") }) {
                return category
            }
            if isSpotify && category.paths.contains(where: { path.contains($0) }) {
                return category
            }
        }
        return nil
    }

    override class func canInit(with request: URLRequest) -> Bool {
        category(for: request.url) != nil
    }

    override class func canInit(with task: URLSessionTask) -> Bool {
        guard let request = task.currentRequest ?? task.originalRequest else {
            return false
        }
        return category(for: request.url) != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        if let category = SPModPrivacyProtocol.category(for: request.url) {
            PrivacyStatsStore.record(category)
        }
        guard
            let url = request.url,
            let response = HTTPURLResponse(url: url, statusCode: 204, httpVersion: "HTTP/1.1", headerFields: [:])
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() { }
}
