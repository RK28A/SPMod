import Orion
import Foundation

enum ProductStatePatch {
    static let overrides: [String: String] = [
        "ads": "0",
        "catalogue": "premium",
        "type": "premium",
        "on-demand": "1",
        "player-license": "premium",
        "player-license-v2": "premium",
        "streaming-rules": "",
        "shuffle-eligible": "1",
        "unrestricted": "1",
        "financial-product": "pr:premium,tc:0",
        "can_use_superbird": "1",
        "nft-disabled": "1",
        "name": "Spotify Premium",
        "offline": "1",
        "social-session": "1",
        "social-session-free-tier": "0",
        "is-eligible-premium-unboxing": "1",
        "payments-initial-campaign": "default"
    ]

    static func value(for key: String?) -> String? {
        guard let key = key else {
            return nil
        }
        return overrides[key]
    }
}

class SPTCoreProductStateHook: ClassHook<NSObject> {
    typealias Group = BasePremiumPatchingGroup
    static let targetName = "SPTCoreProductState"

    func stringForKey(_ key: String) -> String? {
        if let override = ProductStatePatch.value(for: key) {
            return override
        }
        return orig.stringForKey(key)
    }
}

class SPTAdsProductStateHook: ClassHook<NSObject> {
    typealias Group = BasePremiumPatchingGroup
    static let targetName = "SPTAdsProductState"

    func adsEnabled() -> Bool {
        false
    }
}
