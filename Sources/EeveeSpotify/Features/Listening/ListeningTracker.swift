import Foundation
import UIKit
import MediaPlayer

final class ListeningTracker {
    static let shared = ListeningTracker()

    private struct Current {
        var key: String
        var trackId: String?
        var title: String
        var artist: String
        var album: String
        var duration: Double
        var startedAt: Date
        var listened: Double
        var lastTick: Date
        var lastPlaying: Date
        var lastElapsed: Double
        var artworkKey: String?
    }

    private var timer: Timer?
    private var current: Current?
    private let minimumSeconds: Double = 10
    private let pauseTimeout: TimeInterval = 30 * 60

    static func start() {
        shared.startTimer()
    }

    private func startTimer() {
        guard UserDefaults.listeningCollectionEnabled, timer == nil else {
            return
        }
        DispatchQueue.main.async {
            let newTimer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                self?.tick()
            }
            newTimer.tolerance = 0.2
            RunLoop.main.add(newTimer, forMode: .common)
            self.timer = newTimer

            NotificationCenter.default.addObserver(
                forName: UIApplication.willTerminateNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.finalize()
            }
        }
    }

    private func currentSpotifyTrackId(matching title: String) -> String? {
        guard let track = statefulPlayer?.currentTrack() else {
            return nil
        }
        guard track.trackTitle() == title else {
            return nil
        }
        let id = track.trackIdentifier
            .replacingOccurrences(of: "spotify:track:", with: "")
        return id.isEmpty || id.contains(":") ? nil : id
    }

    private func tick() {
        let now = Date()

        guard
            let info = MPNowPlayingInfoCenter.default().nowPlayingInfo,
            let title = info[MPMediaItemPropertyTitle] as? String,
            !title.isEmpty
        else {
            if let current = current, now.timeIntervalSince(current.lastPlaying) > 5 {
                finalize()
            }
            return
        }

        let artist = info[MPMediaItemPropertyArtist] as? String ?? ""
        let album = info[MPMediaItemPropertyAlbumTitle] as? String ?? ""
        let duration = (info[MPMediaItemPropertyPlaybackDuration] as? NSNumber)?.doubleValue ?? 0
        let elapsed = (info[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? NSNumber)?.doubleValue ?? 0
        let rate = (info[MPNowPlayingInfoPropertyPlaybackRate] as? NSNumber)?.doubleValue ?? 1
        let isPlaying = rate > 0

        let trackId = currentSpotifyTrackId(matching: title)
        let key = trackId ?? "meta:\(title.lowercased())|\(artist.lowercased())|\(album.lowercased())"

        if var playing = current, playing.key == key {
            let restarted = elapsed < 3 && playing.lastElapsed > 30 && elapsed != playing.lastElapsed

            if restarted {
                finalize()
                begin(key: key, trackId: trackId, title: title, artist: artist, album: album, duration: duration, elapsed: elapsed, info: info, now: now)
                return
            }

            if isPlaying {
                let delta = now.timeIntervalSince(playing.lastTick)
                if delta > 0 {
                    playing.listened += min(delta, 2)
                }
                playing.lastPlaying = now
            }
            else if now.timeIntervalSince(playing.lastPlaying) > pauseTimeout {
                finalize()
                return
            }

            if playing.trackId == nil, let trackId = trackId {
                playing.trackId = trackId
            }
            if duration > 0 {
                playing.duration = duration
            }
            playing.lastElapsed = elapsed
            playing.lastTick = now
            current = playing
            return
        }

        finalize()

        if isPlaying {
            begin(key: key, trackId: trackId, title: title, artist: artist, album: album, duration: duration, elapsed: elapsed, info: info, now: now)
        }
    }

    private func begin(
        key: String,
        trackId: String?,
        title: String,
        artist: String,
        album: String,
        duration: Double,
        elapsed: Double,
        info: [String: Any],
        now: Date
    ) {
        let artworkKey = ListeningStore.artworkKey(album: album, artist: artist)
        if !ListeningStore.shared.hasArtwork(for: artworkKey),
           let artwork = info[MPMediaItemPropertyArtwork] as? MPMediaItemArtwork,
           let image = artwork.image(at: CGSize(width: 160, height: 160)) {
            DispatchQueue.global(qos: .utility).async {
                ListeningStore.shared.storeArtwork(image, for: artworkKey)
            }
        }

        current = Current(
            key: key,
            trackId: trackId,
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            startedAt: now,
            listened: 0,
            lastTick: now,
            lastPlaying: now,
            lastElapsed: elapsed,
            artworkKey: artworkKey
        )
    }

    private func finalize() {
        guard let playing = current else {
            return
        }
        current = nil

        guard playing.listened >= minimumSeconds else {
            return
        }

        let completed = playing.duration > 0
            && (playing.listened >= playing.duration * 0.85 || playing.lastElapsed >= playing.duration - 8)

        ListeningStore.shared.add(PlayRecord(
            id: UUID(),
            trackId: playing.trackId ?? "",
            title: playing.title,
            artist: playing.artist,
            album: playing.album,
            start: playing.startedAt,
            listened: playing.listened,
            duration: playing.duration,
            completed: completed
        ))
    }
}
