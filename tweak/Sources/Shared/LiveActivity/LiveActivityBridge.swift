// ActivityKit is Swift only, so LiveActivity.x reaches it through this class.
import ActivityKit
import Foundation
import os

@available(iOS 17.0, *)
@objc(SGLiveActivityBridge)
public final class SGLiveActivityBridge: NSObject {
    private static let log = Logger(subsystem: "spotifyglass", category: "live activity")

    private static var current: Activity<SGLyricsAttributes>? {
        Activity<SGLyricsAttributes>.activities.first { $0.activityState == .active || $0.activityState == .stale }
    }

    @objc public static var isShowing: Bool { current != nil }

    private enum Change: Sendable {
        case update(String, ActivityContent<SGLyricsAttributes.ContentState>)
        case end([String])
    }

    private struct Pending: Sendable {
        var changes: [Change] = []
        var sending = false
    }

    private static let pending = OSAllocatedUnfairLock(initialState: Pending())

    private static func queue(_ change: Change) {
        let start = pending.withLock { pending in
            if case .update(let id, _) = change, case .update(let waiting, _)? = pending.changes.last, waiting == id {
                pending.changes.removeLast()
            }
            pending.changes.append(change)
            if pending.sending { return false }
            pending.sending = true
            return true
        }
        if start { Task { await send() } }
    }

    private static func send() async {
        while let change = pending.withLock({ pending -> Change? in
            if pending.changes.isEmpty {
                pending.sending = false
                return nil
            }
            return pending.changes.removeFirst()
        }) {
            let activities = Activity<SGLyricsAttributes>.activities
            switch change {
            case .update(let id, let content):
                guard let activity = activities.first(where: { $0.id == id }) else { break }
                // With the screen dimmed or locked the system can hold an update back for a long while. The queue
                // waits two seconds at most for it, then sends what came after, so the line shown does not stay
                // behind until the screen is woken.
                let started = Date()
                let late = await waitAtMost(2) { await activity.update(content) }
                if late {
                    log.notice("[spotifyglass] live activity: an update was still waiting after \(Date().timeIntervalSince(started), privacy: .public) s, sending on")
                }
            case .end(let ids):
                for activity in activities where ids.contains(activity.id) {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
            }
        }
    }

    // YES when `work` had not finished after `seconds`; it goes on finishing on its own.
    private static func waitAtMost(_ seconds: Double, _ work: @escaping @Sendable () async -> Void) async -> Bool {
        let settled = OSAllocatedUnfairLock<Bool?>(initialState: nil)
        return await withCheckedContinuation { (waiting: CheckedContinuation<Bool, Never>) in
            let finish: @Sendable (Bool) -> Void = { late in
                let first = settled.withLock { state -> Bool in
                    if state != nil { return false }
                    state = late
                    return true
                }
                if first { waiting.resume(returning: late) }
            }
            Task {
                await work()
                finish(false)
            }
            Task {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                finish(true)
            }
        }
    }

    @objc public static func show(view: Int, paused: Bool, line: String, nextLine: String,
                                  titles: [String], artists: [String], uris: [String],
                                  tab: Int, title: String, artist: String, shuffle: Bool, repeatMode: Int,
                                  timerEnd: Date?, timerEndOfTrack: Bool,
                                  fill: Int, fillAlpha: Double, accent: Int) {
        let tracks = titles.indices.map {
            SGLyricsAttributes.Track(title: titles[$0], artist: artists[$0], uri: uris[$0])
        }
        let state = SGLyricsAttributes.ContentState(
            view: SGLyricsAttributes.View(rawValue: view) ?? .lyrics, paused: paused,
            line: line, nextLine: nextLine, tracks: tracks,
            tab: SGLyricsAttributes.Tab(rawValue: tab) ?? .controls, title: title, artist: artist,
            shuffle: shuffle, repeatMode: repeatMode, timerEnd: timerEnd, timerEndOfTrack: timerEndOfTrack,
            // Objective-C has no optional integer: below zero stands for none.
            fill: fill >= 0 ? fill : nil, fillAlpha: fill >= 0 ? fillAlpha : nil, accent: accent >= 0 ? accent : nil)
        let content = ActivityContent(state: state, staleDate: nil)
        if let activity = current {
            queue(.update(activity.id, content))
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            log.notice("[spotifyglass] live activity: activities are off for this app")
            return
        }
        do {
            let activity = try Activity.request(attributes: SGLyricsAttributes(), content: content, pushType: nil)
            log.notice("[spotifyglass] live activity: started \(activity.id, privacy: .public)")
        } catch {
            log.error("[spotifyglass] live activity: request failed: \(String(describing: error), privacy: .public)")
        }
    }

    // Named now, so an activity requested after this call is not ended with them.
    @objc public static func end() {
        queue(.end(Activity<SGLyricsAttributes>.activities.map(\.id)))
    }
}
