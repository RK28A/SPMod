import Orion
import Foundation

struct CanvasFlagsGroup: HookGroup { }
struct LyricsFlagsGroup: HookGroup { }

class CanvasAvailabilityPropertiesHook: ClassHook<NSObject> {
    typealias Group = CanvasFlagsGroup
    static let targetName = "Canvas_AvailabilityCheckerImpl.SPTCanvas_AvailabilityCheckerImplProperties"

    func initWithConfigurationProvider(_ provider: NSObject?) -> Target {
        let result = orig.initWithConfigurationProvider(provider)
        Ivars<Bool>(result)[safelyAccessing: "canvasEnabled"] = false
        Ivars<Bool>(result)[safelyAccessing: "canvasEnabledIpad"] = false
        return result
    }
}

class LyricsConfigurationPropertiesHook: ClassHook<NSObject> {
    typealias Group = LyricsFlagsGroup
    static let targetName = "Lyrics_ConfigurationImpl.SPTLyrics_ConfigurationImplProperties"

    func initWithConfigurationProvider(_ provider: NSObject?) -> Target {
        let result = orig.initWithConfigurationProvider(provider)
        Ivars<Bool>(result)[safelyAccessing: "enableLyrics"] = true
        Ivars<Bool>(result)[safelyAccessing: "enableHasLyricsCheckBypass"] = true
        return result
    }
}

class LyricsNPVElementsPropertiesHook: ClassHook<NSObject> {
    typealias Group = LyricsFlagsGroup
    static let targetName = "Lyrics_NPVElementsKitImpl.SPTLyrics_NPVElementsKitImplProperties"

    func initWithConfigurationProvider(_ provider: NSObject?) -> Target {
        let result = orig.initWithConfigurationProvider(provider)
        Ivars<Bool>(result)[safelyAccessing: "lyricsEntryPointEnabled"] = true
        return result
    }
}
