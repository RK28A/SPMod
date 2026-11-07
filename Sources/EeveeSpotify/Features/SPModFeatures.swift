import UIKit
import MediaPlayer

enum ToastHelper {
    private static weak var currentToast: UIView?

    static func show(_ message: String) {
        DispatchQueue.main.async {
            guard let window = WindowHelper.shared.window else {
                return
            }

            currentToast?.removeFromSuperview()

            let label = PaddedLabel()
            label.text = message
            label.textColor = .white
            label.font = .systemFont(ofSize: 14, weight: .semibold)
            label.textAlignment = .center
            label.numberOfLines = 3
            label.backgroundColor = UIColor(white: 0.12, alpha: 0.95)
            label.layer.cornerRadius = 12
            label.layer.masksToBounds = true
            label.alpha = 0
            label.isUserInteractionEnabled = false
            label.translatesAutoresizingMaskIntoConstraints = false

            window.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: window.centerXAnchor),
                label.bottomAnchor.constraint(equalTo: window.safeAreaLayoutGuide.bottomAnchor, constant: -110),
                label.leadingAnchor.constraint(greaterThanOrEqualTo: window.leadingAnchor, constant: 24),
                label.trailingAnchor.constraint(lessThanOrEqualTo: window.trailingAnchor, constant: -24)
            ])
            currentToast = label

            UIView.animate(withDuration: 0.2) {
                label.alpha = 1
            } completion: { _ in
                UIView.animate(withDuration: 0.3, delay: 1.8, options: []) {
                    label.alpha = 0
                } completion: { _ in
                    label.removeFromSuperview()
                }
            }
        }
    }

    private class PaddedLabel: UILabel {
        override func drawText(in rect: CGRect) {
            super.drawText(in: rect.inset(by: UIEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)))
        }

        override var intrinsicContentSize: CGSize {
            let size = super.intrinsicContentSize
            return CGSize(width: size.width + 32, height: size.height + 20)
        }
    }
}

enum CopyTrackManager {
    private static var observer: NSObjectProtocol?
    private static var lastCopy = Date.distantPast

    static func start() {
        guard UserDefaults.copyTrackOnShake, observer == nil else {
            return
        }
        observer = NotificationCenter.default.addObserver(
            forName: Notification.Name("SPModDeviceShaken"),
            object: nil,
            queue: .main
        ) { _ in
            if UserDefaults.container.integer(forKey: "shakeAction") == 1 {
                QuickAddStore.addCurrentTrack()
            }
            else {
                copyCurrentTrack()
            }
        }
    }

    private static func currentTrackInfo() -> (title: String, artist: String, id: String)? {
        if let track = statefulPlayer?.currentTrack() {
            let artist = EeveeSpotify.hookTarget == .lastAvailableiOS14 ? track.artistTitle() : track.artistName()
            return (track.trackTitle(), artist, track.trackIdentifier)
        }

        guard let info = MPNowPlayingInfoCenter.default().nowPlayingInfo else {
            return nil
        }
        let title = info[MPMediaItemPropertyTitle] as? String ?? ""
        let artist = info[MPMediaItemPropertyArtist] as? String ?? ""
        if title.isEmpty && artist.isEmpty {
            return nil
        }
        return (title, artist, "")
    }

    static func copyCurrentTrack() {
        guard Date().timeIntervalSince(lastCopy) > 1 else {
            return
        }
        lastCopy = Date()

        guard let track = currentTrackInfo() else {
            ToastHelper.show("copy_no_track".localized)
            return
        }

        let id = track.id
            .replacingOccurrences(of: "spotify:track:", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let link = id.isEmpty || id.contains(":") ? "" : "https://open.spotify.com/track/\(id)"
        let titleArtist = track.artist.isEmpty ? track.title : "\(track.title) – \(track.artist)"

        let text: String
        switch UserDefaults.copyTrackFormat {
        case .link:
            text = link.isEmpty ? titleArtist : link
        case .titleArtist:
            text = titleArtist
        case .both:
            text = link.isEmpty ? titleArtist : "\(titleArtist)\n\(link)"
        case .trackId:
            text = id.isEmpty ? titleArtist : id
        }

        UIPasteboard.general.string = text
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        ToastHelper.show("copied_to_clipboard".localized)
    }
}

enum ScreenAwakeManager {
    private static var timer: Timer?
    private static var isHolding = false
    private static var observers: [NSObjectProtocol] = []

    static func start() {
        guard UserDefaults.keepScreenOn, observers.isEmpty else {
            return
        }
        DispatchQueue.main.async {
            let center = NotificationCenter.default
            observers.append(center.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { _ in
                startTimer()
            })
            observers.append(center.addObserver(
                forName: UIApplication.willResignActiveNotification,
                object: nil,
                queue: .main
            ) { _ in
                stopTimer()
            })
            if UIApplication.shared.applicationState == .active {
                startTimer()
            }
        }
    }

    private static func startTimer() {
        guard timer == nil else {
            return
        }
        let newTimer = Timer(timeInterval: 1.5, repeats: true) { _ in
            update()
        }
        newTimer.tolerance = 0.5
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    private static func stopTimer() {
        timer?.invalidate()
        timer = nil
        release()
    }

    private static func release() {
        if isHolding {
            UIApplication.shared.isIdleTimerDisabled = false
            isHolding = false
        }
    }

    private static func update() {
        let shouldHold = isPlaying() && isLyricsVisible()
        guard shouldHold != isHolding else {
            return
        }
        UIApplication.shared.isIdleTimerDisabled = shouldHold
        isHolding = shouldHold
    }

    private static func isPlaying() -> Bool {
        guard let info = MPNowPlayingInfoCenter.default().nowPlayingInfo else {
            return false
        }
        guard let rate = info[MPNowPlayingInfoPropertyPlaybackRate] as? NSNumber else {
            return true
        }
        return rate.doubleValue > 0
    }

    private static func isLyricsVisible() -> Bool {
        guard let window = WindowHelper.shared.window else {
            return false
        }
        let bounds = window.bounds
        var stack: [UIView] = [window]
        var visited = 0

        while let view = stack.popLast() {
            visited += 1
            if visited > 6000 {
                return false
            }
            if view.isHidden || view.alpha < 0.01 {
                continue
            }
            if NSStringFromClass(type(of: view)).hasPrefix("Lyrics_") {
                let frame = view.convert(view.bounds, to: window).intersection(bounds)
                if !frame.isNull && frame.height > 80 && frame.width > 80 {
                    return true
                }
            }
            stack.append(contentsOf: view.subviews)
        }
        return false
    }
}
