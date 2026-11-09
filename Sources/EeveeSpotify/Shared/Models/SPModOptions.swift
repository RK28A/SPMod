import Foundation

enum SPModLanguage: String, CaseIterable, Codable {
    case automatic
    case english
    case french

    var title: String {
        switch self {
        case .automatic: return "language_automatic".localized
        case .english: return "English"
        case .french: return "Français"
        }
    }
}

enum SPModCopyFormat: Int, CaseIterable, Codable {
    case link
    case titleArtist
    case both
    case trackId

    var title: String {
        switch self {
        case .link: return "copy_format_link".localized
        case .titleArtist: return "copy_format_title_artist".localized
        case .both: return "copy_format_both".localized
        case .trackId: return "copy_format_track_id".localized
        }
    }
}

extension UserDefaults {
    static let spmodLanguageKey = "spmodLanguage"
    static let lyricsCacheEnabledKey = "lyricsCacheEnabled"
    static let lyricsFallbackOrderKey = "lyricsFallbackOrder"
    static let copyTrackOnShakeKey = "copyTrackOnShake"
    static let copyTrackFormatKey = "copyTrackFormat"
    static let disableCanvasKey = "disableCanvas"
    static let keepScreenOnKey = "keepScreenOn"
    static let themeConfigKey = "themeConfig"

    static var spmodLanguage: SPModLanguage {
        get {
            container.string(forKey: spmodLanguageKey).flatMap(SPModLanguage.init(rawValue:)) ?? .automatic
        }
        set {
            container.set(newValue.rawValue, forKey: spmodLanguageKey)
        }
    }

    static var lyricsCacheEnabled: Bool {
        get { container.object(forKey: lyricsCacheEnabledKey) as? Bool ?? true }
        set { container.set(newValue, forKey: lyricsCacheEnabledKey) }
    }

    static var lyricsFallbackOrder: [LyricsSource] {
        get {
            if let rawValues = container.array(forKey: lyricsFallbackOrderKey) as? [Int] {
                var seen = Set<LyricsSource>()
                return rawValues
                    .compactMap(LyricsSource.init(rawValue:))
                    .filter { $0.isReplacingLyrics && seen.insert($0).inserted }
            }
            return lyricsOptions.geniusFallback ? [.genius] : []
        }
        set {
            container.set(newValue.map(\.rawValue), forKey: lyricsFallbackOrderKey)
        }
    }

    static var copyTrackOnShake: Bool {
        get { container.object(forKey: copyTrackOnShakeKey) as? Bool ?? true }
        set { container.set(newValue, forKey: copyTrackOnShakeKey) }
    }

    static var copyTrackFormat: SPModCopyFormat {
        get {
            (container.object(forKey: copyTrackFormatKey) as? Int).flatMap(SPModCopyFormat.init(rawValue:)) ?? .link
        }
        set { container.set(newValue.rawValue, forKey: copyTrackFormatKey) }
    }

    static var disableCanvas: Bool {
        get { container.object(forKey: disableCanvasKey) as? Bool ?? false }
        set { container.set(newValue, forKey: disableCanvasKey) }
    }

    static var keepScreenOn: Bool {
        get { container.object(forKey: keepScreenOnKey) as? Bool ?? true }
        set { container.set(newValue, forKey: keepScreenOnKey) }
    }

    @UserDefault(key: "themeConfig", defaultValue: ThemeConfig.default)
    static var themeConfig: ThemeConfig

    static let listeningCollectionEnabledKey = "listeningCollectionEnabled"
    static let hidePremiumUpsellsKey = "hidePremiumUpsells"
    static let playerQuickAddButtonKey = "playerQuickAddButton"
    static let playerLiquidGlassKey = "playerLiquidGlass"

    static var playerQuickAddButton: Bool {
        get { container.object(forKey: playerQuickAddButtonKey) as? Bool ?? true }
        set { container.set(newValue, forKey: playerQuickAddButtonKey) }
    }

    static var playerLiquidGlass: Bool {
        get { container.object(forKey: playerLiquidGlassKey) as? Bool ?? true }
        set { container.set(newValue, forKey: playerLiquidGlassKey) }
    }

    static let glassOpacityKey = "glassOpacity"

    static var glassOpacity: Double {
        get {
            let value = container.object(forKey: glassOpacityKey) as? Double ?? 0.22
            return min(max(value, 0.0), 0.6)
        }
        set { container.set(min(max(newValue, 0.0), 0.6), forKey: glassOpacityKey) }
    }


    static var hidePremiumUpsells: Bool {
        get { container.object(forKey: hidePremiumUpsellsKey) as? Bool ?? true }
        set { container.set(newValue, forKey: hidePremiumUpsellsKey) }
    }


    static var listeningCollectionEnabled: Bool {
        get { container.object(forKey: listeningCollectionEnabledKey) as? Bool ?? true }
        set { container.set(newValue, forKey: listeningCollectionEnabledKey) }
    }

    static let spmodBackupKeys: [String] = [
        "musixmatchToken",
        "darkPopUps",
        "patchType",
        "overwriteConfiguration",
        "lyricsColors",
        "lyricsOptions",
        "lyricsSource",
        "experimentsOptions",
        "hasShownCommonIssuesTip",
        spmodLanguageKey,
        lyricsCacheEnabledKey,
        lyricsFallbackOrderKey,
        copyTrackOnShakeKey,
        copyTrackFormatKey,
        disableCanvasKey,
        keepScreenOnKey,
        themeConfigKey,
        listeningCollectionEnabledKey,
        hidePremiumUpsellsKey,
        playerQuickAddButtonKey,
        playerLiquidGlassKey,
        glassOpacityKey,
        enabledLabGroupsKey,
        artistBlockEnabledKey,
        "spmodBlockedArtists",
        "shakeAction",
        "smartShuffleOptions",
        "quickAddLastPlaylist",
        "quickAddPinnedPlaylist",
        "quickAddAllowDuplicates",
        lyricsTranslationEnabledKey,
        lyricsTranslationConsentKey,
        lyricsTranslationTargetKey,
        lyricsTranslationModeKey,
        privacyModeKey,
        privacyCustomCategoriesKey,
        spmodLogsEnabledKey,
        "nightModeConfig"
    ]
}
