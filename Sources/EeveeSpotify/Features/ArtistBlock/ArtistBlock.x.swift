import Orion
import UIKit
import ObjectiveC.runtime

struct ArtistBlockGroup: HookGroup {}

// The now-playing playback controller is captured here; it carries the skip
// command used to pass over a blocked track.
class PlaybackControllerCaptureHook: ClassHook<NSObject> {
    typealias Group = ArtistBlockGroup
    static let targetName = "SPTNowPlayingPlaybackControllerImplementation"

    func canSkipNext() -> Bool {
        ArtistBlockRuntime.controller = target
        return orig.canSkipNext()
    }
}

enum ArtistBlockRuntime {
    static weak var controller: NSObject?
    private static var timer: Timer?
    private static var lastHandledTrackId: String?

    static func start() {
        DispatchQueue.main.async {
            guard timer == nil else { return }
            let newTimer = Timer(timeInterval: 0.5, repeats: true) { _ in
                ArtistBlockRuntime.tick()
            }
            newTimer.tolerance = 0.1
            RunLoop.main.add(newTimer, forMode: .common)
            timer = newTimer
        }
    }

    private static func tick() {
        guard UserDefaults.artistBlockEnabled else { return }
        guard let track = statefulPlayer?.currentTrack() else { return }

        let id = track.trackIdentifier
        guard !id.isEmpty, id != lastHandledTrackId else { return }
        lastHandledTrackId = id

        let artists = ArtistBlockStore.artists(of: track)
        if artists.contains(where: { ArtistBlockStore.isBlocked($0.uri) }) {
            skipNext()
        }
    }

    // Calls -skipToNextWhileDragging: through a typed IMP so a BOOL argument is
    // passed correctly; guarded so a missing selector is a no-op, never a crash.
    static func skipNext() {
        guard let controller = controller else { return }
        let selector = Selector(("skipToNextWhileDragging:"))
        guard
            controller.responds(to: selector),
            let method = class_getInstanceMethod(type(of: controller), selector)
        else {
            return
        }
        typealias SkipFunction = @convention(c) (AnyObject, Selector, Bool) -> Void
        let function = unsafeBitCast(method_getImplementation(method), to: SkipFunction.self)
        function(controller, selector, false)
    }
}

func activateArtistBlock() {
    guard UserDefaults.artistBlockEnabled else { return }

    guard let cls = findTweakClass(PlaybackControllerCaptureHook.targetName),
          class_getInstanceMethod(cls, Selector(("canSkipNext"))) != nil else {
        SPModDiagnostics.record("[ArtistBlock] playback controller unavailable; skipping")
        return
    }

    ArtistBlockGroup().activate()
    ArtistBlockRuntime.start()
    SPModDiagnostics.record("[ArtistBlock] activated")
}
