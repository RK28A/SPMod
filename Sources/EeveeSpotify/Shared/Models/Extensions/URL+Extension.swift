import Foundation

extension URL {
    var isLyrics: Bool {
        self.path.contains("color-lyrics/v2")
    }
    
    var isPlanOverview: Bool {
        self.path.contains("GetPlanOverview")
    }
    
    var isPremiumPlanRow: Bool {
        self.path.contains("v1/GetPremiumPlanRow")
    }
    
    var isPremiumBadge: Bool {
        self.path.contains("GetYourPremiumBadge")
    }

    var isOpenSpotifySafariExtension: Bool {
        self.host == "eevee"
    }
    
    var isCustomize: Bool {
        self.path.contains("v1/customize")
    }
    
    var isCanvas: Bool {
        self.path.contains("canvaz-cache") || (self.host?.contains("canvaz") ?? false)
    }
    
    var isBootstrap: Bool {
        self.path.contains("v1/bootstrap")
    }

    var isAd: Bool {
        if let host = self.host?.lowercased(), host == "aet.spotify.com" || host.hasPrefix("adeventreceiver") {
            return true
        }
        let path = self.path.lowercased()
        return path.contains("/ads/")
            || path.hasSuffix("/ads")
            || path.contains("/ad-logic")
            || path.contains("/adeventreceiver")
            || path.contains("/sponsored")
            || path.contains("spotify:ad:")
    }
}
