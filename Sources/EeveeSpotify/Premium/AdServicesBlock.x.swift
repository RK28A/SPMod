import Orion
import Foundation

struct AdBlockGroup: HookGroup { }

class URLSessionTaskResumeHook: ClassHook<URLSessionTask> {
    typealias Group = AdBlockGroup

    func resume() {
        if let url = target.currentRequest?.url, url.isAd {
            target.cancel()
            return
        }
        orig.resume()
    }
}

class AdsBaseSwiftServiceHook: ClassHook<NSObject> {
    typealias Group = AdBlockGroup
    static let targetName = "AdsPlatform_AdsBaseSwiftImpl.AdsBaseSwiftServiceImpl"
    func load() { }
}

class RealTimeAdControllerServiceHook: ClassHook<NSObject> {
    typealias Group = AdBlockGroup
    static let targetName = "AdsPlatform_RealTimeAdControllerImpl.RealTimeAdControllerServiceImpl"
    func load() { }
}

class AdsInstrumentationServiceHook: ClassHook<NSObject> {
    typealias Group = AdBlockGroup
    static let targetName = "AdsPlatform_AdsInstrumentationImpl.AdsInstrumentationServiceImpl"
    func load() { }
}

class AdsPlatformElementServiceHook: ClassHook<NSObject> {
    typealias Group = AdBlockGroup
    static let targetName = "AdsPlatform_ElementImpl.ElementServiceImpl"
    func load() { }
}

class RewardedAdFetchControllerServiceHook: ClassHook<NSObject> {
    typealias Group = AdBlockGroup
    static let targetName = "AdsStandalone_RewardedAdImpl.RewardedAdFetchControllerService"
    func load() { }
}

class OnDemandAdEventLoggerServiceHook: ClassHook<NSObject> {
    typealias Group = AdBlockGroup
    static let targetName = "AdsStandalone_RewardedAdImpl.OnDemandAdEventLoggerService"
    func load() { }
}

class AdOnAppOpenServiceHook: ClassHook<NSObject> {
    typealias Group = AdBlockGroup
    static let targetName = "AdsStandalone_AdOnAppOpenImpl.AdOnAppOpenServiceImpl"
    func load() { }
}

class EmbeddedCTACardsServiceHook: ClassHook<NSObject> {
    typealias Group = AdBlockGroup
    static let targetName = "AdsEmbedded_EmbeddedCTACardsImpl.EmbeddedCTACardsService"
    func load() { }
}

class EmbeddedPlaylistServiceHook: ClassHook<NSObject> {
    typealias Group = AdBlockGroup
    static let targetName = "AdsEmbedded_EmbeddedPlaylistImpl.EmbeddedPlaylistServiceImpl"
    func load() { }
}

class NativeAdsElementServiceHook: ClassHook<NSObject> {
    typealias Group = AdBlockGroup
    static let targetName = "NativeAds_ElementImpl.NativeAdsElementServiceImpl"
    func load() { }
}

class AudioAdPictureInPictureCoordinatorServiceHook: ClassHook<NSObject> {
    typealias Group = AdBlockGroup
    static let targetName = "Betamax_AudioAdPictureInPictureCoordinatorImpl.AudioAdPictureInPictureCoordinatorService"
    func load() { }
}

class ShuffleToggleUpsellServiceHook: ClassHook<NSObject> {
    typealias Group = AdBlockGroup
    static let targetName = "ContextualShuffle_UpsellImpl.ShuffleToggleUpsellServiceImplementation"
    func load() { }
}

class PlayFullSongUpsellServiceHook: ClassHook<NSObject> {
    typealias Group = AdBlockGroup
    static let targetName = "ReinventFree_PlayFullSongUpsellImpl.PlayFullSongUpsellServiceImpl"
    func load() { }
}
