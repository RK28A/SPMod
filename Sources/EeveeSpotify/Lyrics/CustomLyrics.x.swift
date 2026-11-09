import Orion
import SwiftUI

//

struct BaseLyricsGroup: HookGroup { }

struct LegacyLyricsGroup: HookGroup { }
struct ModernLyricsGroup: HookGroup { }

var lyricsState = LyricsLoadingState()

var hasShownRestrictedPopUp = false
var hasShownUnauthorizedPopUp = false

private let geniusLyricsRepository = GeniusLyricsRepository()
private let petitLyricsRepository = PetitLyricsRepository()

//

private func lyricsRepository(for source: LyricsSource) throws -> LyricsRepository {
    switch source {
    case .genius:
        return geniusLyricsRepository
    case .lrclib:
        return LrclibLyricsRepository.shared
    case .musixmatch:
        return MusixmatchLyricsRepository.shared
    case .petit:
        return petitLyricsRepository
    case .netease:
        return NetEaseLyricsRepository.shared
    case .notReplaced:
        throw LyricsError.invalidSource
    }
}

func lyricsSourceChain(primary: LyricsSource) -> [LyricsSource] {
    var chain = [primary]
    
    for source in UserDefaults.lyricsFallbackOrder where !chain.contains(source) {
        if source == .musixmatch && UserDefaults.musixmatchToken.isEmpty {
            continue
        }
        chain.append(source)
    }
    
    return chain
}

private func handleLyricsErrorPopUp(_ error: Error) {
    guard let error = error as? LyricsError else {
        return
    }
    
    switch error {
    case .invalidMusixmatchToken:
        if !hasShownUnauthorizedPopUp {
            PopUpHelper.showPopUp(
                delayed: false,
                message: "musixmatch_unauthorized_popup".localized,
                buttonText: "OK".uiKitLocalized
            )
            
            hasShownUnauthorizedPopUp = true
        }
        
    case .musixmatchRestricted:
        if !hasShownRestrictedPopUp {
            PopUpHelper.showPopUp(
                delayed: false,
                message: "musixmatch_restricted_popup".localized,
                buttonText: "OK".uiKitLocalized
            )
            
            hasShownRestrictedPopUp = true
        }
        
    default:
        break
    }
}

private func loadCustomLyricsForCurrentTrack() throws -> Lyrics {
    guard
        let track = statefulPlayer?.currentTrack() ??
                    nowPlayingScrollViewController?.loadedTrack
        else {
            throw LyricsError.noCurrentTrack
        }
    
    let searchQuery = LyricsSearchQuery(
        title: track.trackTitle(),
        primaryArtist: EeveeSpotify.hookTarget == .lastAvailableiOS14
            ? track.artistTitle()
            : track.artistName(),
        spotifyTrackId: track.trackIdentifier
    )
    
    let options = UserDefaults.lyricsOptions
    let primarySource = UserDefaults.lyricsSource
    
    guard primarySource.isReplacingLyrics else {
        throw LyricsError.invalidSource
    }
    
    let sources = lyricsSourceChain(primary: primarySource)
    let cacheKey = UserDefaults.lyricsCacheEnabled
        ? LyricsCache.key(trackId: searchQuery.spotifyTrackId, sources: sources, options: options)
        : nil
    
    lyricsState = LyricsLoadingState()
    
    var loadedDto: LyricsDto? = nil
    var source = primarySource
    
    if let cacheKey = cacheKey,
       let cached = LyricsCache.load(cacheKey),
       let cachedSource = LyricsSource(rawValue: cached.source) {
        loadedDto = cached.dto
        source = cachedSource
    }
    
    var lastError: Error? = nil
    
    if loadedDto == nil {
        for candidate in sources {
            do {
                loadedDto = try lyricsRepository(for: candidate).getLyrics(searchQuery, options: options)
                source = candidate
                break
            }
            catch let error {
                lastError = error
                
                if lyricsState.fallbackError == nil {
                    lyricsState.fallbackError = (error as? LyricsError) ?? .unknownError
                }
                
                handleLyricsErrorPopUp(error)
            }
        }
        
        if let loadedDto = loadedDto, let cacheKey = cacheKey {
            LyricsCache.store(loadedDto, source: source, for: cacheKey)
        }
    }
    
    guard let baseDto = loadedDto else {
        throw lastError ?? LyricsError.unknownError
    }
    
    let lyricsDto = LyricsTranslator.apply(to: baseDto)
    
    if source == primarySource {
        lyricsState.fallbackError = nil
    }
    
    lyricsState.isEmpty = lyricsDto.lines.isEmpty
    
    lyricsState.wasRomanized = lyricsDto.romanization == .romanized
        || (lyricsDto.romanization == .canBeRomanized && UserDefaults.lyricsOptions.romanization)
    
    lyricsState.loadedSuccessfully = true

    let lyrics = Lyrics.with {
        $0.data = lyricsDto.toSpotifyLyricsData(source: source.description)
    }
    
    return lyrics
}

func getLyricsDataForCurrentTrack(_ originalPath: String, originalLyrics: Lyrics? = nil) throws -> Data {
    guard
        let track = statefulPlayer?.currentTrack() ??
                    nowPlayingScrollViewController?.loadedTrack
        else {
            throw LyricsError.noCurrentTrack
        }
    
    let trackIdentifier = track.trackIdentifier
    
    if !trackIdentifier.isEmpty && !originalPath.contains(trackIdentifier) {
        throw LyricsError.trackMismatch
    }
    
    var lyrics = try loadCustomLyricsForCurrentTrack()
    
    let lyricsColorsSettings = UserDefaults.lyricsColors
    
    if lyricsColorsSettings.displayOriginalColors, let originalLyrics = originalLyrics {
        lyrics.colors = originalLyrics.colors
    }
    else {
        let extractedColor = switch EeveeSpotify.hookTarget {
        case .lastAvailableiOS14:
            track.extractedColorHex()
        default:
            track.metadata()["extracted_color"]
        }
        
        var color: Color
        
        if lyricsColorsSettings.useStaticColor {
            color = Color(hex: lyricsColorsSettings.staticColor)
        }
        else if let extractedColor = extractedColor {
            color = Color(hex: extractedColor)
                .normalized(lyricsColorsSettings.normalizationFactor)
        }
        else if let uiColor = backgroundViewModel?.color() {
            color = Color(uiColor)
                .normalized(lyricsColorsSettings.normalizationFactor)
        }
        else {
            color = Color.gray
        }
        
        lyrics.colors = LyricsColors.with {
            $0.backgroundColor = color.uInt32
            $0.lineColor = Color.black.uInt32
            $0.activeLineColor = Color.white.uInt32
        }
    }
    
    return try lyrics.serializedBytes()
}
