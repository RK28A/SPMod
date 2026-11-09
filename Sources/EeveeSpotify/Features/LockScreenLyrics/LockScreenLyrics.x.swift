import Orion
import UIKit
import MediaPlayer

struct LockScreenLyricsGroup: HookGroup {}

// Spotify's now-playing info is passed through untouched; a timer then re-sends
// it with the artist row replaced by the line being sung. Spotify only ever
// reads back its own dictionary. Original implementation over SPMod's lyrics
// repositories; modelled on spoti.pw's LockScreenLyrics.
class NowPlayingInfoLyricsHook: ClassHook<MPNowPlayingInfoCenter> {
    typealias Group = LockScreenLyricsGroup

    func setNowPlayingInfo(_ info: [String: Any]?) {
        orig.setNowPlayingInfo(info)
        guard UserDefaults.lockScreenLyricsEnabled, !LockScreenLyrics.isResending else { return }
        LockScreenLyrics.capture(info)
    }
}

enum LockScreenLyrics {
    static var isResending = false

    private static var spotifyInfo: [String: Any]?
    private static var infoAt: CFAbsoluteTime = 0
    private static var timer: Timer?

    private static var currentTrackId: String?
    private static var lines: [LyricsLineDto]?
    private static var fetching = false
    private static var shownLine: String?

    private static let breakMs = 8000
    private static let heldMs = 5000

    static func capture(_ info: [String: Any]?) {
        spotifyInfo = info
        infoAt = CFAbsoluteTimeGetCurrent()
    }

    static func start() {
        DispatchQueue.main.async {
            guard timer == nil else { return }
            let newTimer = Timer(timeInterval: 0.25, repeats: true) { _ in
                LockScreenLyrics.tick()
            }
            newTimer.tolerance = 0.05
            RunLoop.main.add(newTimer, forMode: .common)
            timer = newTimer
        }
    }

    private static func tick() {
        guard UserDefaults.lockScreenLyricsEnabled, let info = spotifyInfo else { return }
        guard let track = statefulPlayer?.currentTrack() else { return }

        let id = track.trackIdentifier
        if id != currentTrackId {
            currentTrackId = id
            lines = nil
            shownLine = nil
            fetchLyrics(for: track)
            return
        }

        guard let lines = lines, !lines.isEmpty else { return }

        let rate = (info[MPNowPlayingInfoPropertyPlaybackRate] as? NSNumber)?.doubleValue ?? 0
        let reported = (info[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? NSNumber)?.doubleValue ?? 0
        let elapsed = reported + rate * (CFAbsoluteTimeGetCurrent() - infoAt)
        let positionMs = Int(elapsed * 1000)

        let line = currentLine(lines, positionMs)
        if line == shownLine { return }
        shownLine = line
        resend(info, artist: line)
    }

    private static func currentLine(_ lines: [LyricsLineDto], _ positionMs: Int) -> String? {
        var index = -1
        for (i, line) in lines.enumerated() {
            if (line.offsetMs ?? 0) <= positionMs {
                index = i
            } else {
                break
            }
        }
        guard index >= 0 else { return nil }

        let start = lines[index].offsetMs ?? 0
        let nextStart = index + 1 < lines.count ? (lines[index + 1].offsetMs ?? Int.max) : Int.max
        if nextStart - start > breakMs && positionMs - start > heldMs {
            return nil
        }

        let content = lines[index].content.trimmingCharacters(in: .whitespacesAndNewlines)
        return content.isEmpty ? nil : content
    }

    private static func resend(_ info: [String: Any], artist: String?) {
        var modified = info
        if let artist = artist {
            modified[MPMediaItemPropertyArtist] = artist
        }
        isResending = true
        MPNowPlayingInfoCenter.default().nowPlayingInfo = modified
        isResending = false
    }

    private static func fetchLyrics(for track: SPTPlayerTrack) {
        guard !fetching else { return }
        fetching = true

        let query = LyricsSearchQuery(
            title: track.trackTitle(),
            primaryArtist: EeveeSpotify.hookTarget == .lastAvailableiOS14
                ? track.artistTitle()
                : track.artistName(),
            spotifyTrackId: track.trackIdentifier
        )
        let targetId = track.trackIdentifier

        DispatchQueue.global(qos: .utility).async {
            let result = timedLyrics(for: query)
            DispatchQueue.main.async {
                fetching = false
                if currentTrackId == targetId {
                    lines = result
                }
            }
        }
    }

    private static func timedLyrics(for query: LyricsSearchQuery) -> [LyricsLineDto]? {
        var repositories: [LyricsRepository] = [
            LrclibLyricsRepository.shared,
            NetEaseLyricsRepository.shared
        ]
        if !UserDefaults.musixmatchToken.isEmpty {
            repositories.append(MusixmatchLyricsRepository.shared)
        }

        let options = UserDefaults.lyricsOptions
        for repository in repositories {
            if let dto = try? repository.getLyrics(query, options: options),
               dto.timeSynced,
               !dto.lines.isEmpty {
                return dto.lines.sorted { ($0.offsetMs ?? 0) < ($1.offsetMs ?? 0) }
            }
        }
        return nil
    }
}

func activateLockScreenLyrics() {
    guard UserDefaults.lockScreenLyricsEnabled else { return }
    LockScreenLyricsGroup().activate()
    LockScreenLyrics.start()
    SPModDiagnostics.record("[LockLyrics] activated")
}
