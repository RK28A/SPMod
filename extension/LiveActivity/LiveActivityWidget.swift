// The Live Activity's face, one of three views: the line being sung with the next one under it, the
// tracks up next, or the control menu, a tab bar over Controls, Queue and Timer. A tap reaches the
// tweak as an intent and the new state takes over a second to render, so every on/off control is a
// Toggle, whose look the system flips the moment it is tapped, and what only changes after the render
// is marked invalidatable. iOS clips a lock screen Live Activity at 160 points, so every view is kept
// under it. Built with the tweak's LiveActivityShared.swift by scripts/build-extension.sh.
import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

private let green = Color(red: 0.12, green: 0.84, blue: 0.38)
private let idle = Color.white.opacity(0.08)

// What an unlit chip is filled with, handed down from the card: on a card that lets the lock screen through
// the chips are a shade darker than it, not lighter, so they still read as chips.
private struct ChipIdleKey: EnvironmentKey {
    static let defaultValue = idle
}

private extension EnvironmentValues {
    var chipIdle: Color {
        get { self[ChipIdleKey.self] }
        set { self[ChipIdleKey.self] = newValue }
    }
}

private struct Plate<S: Shape>: View {
    let shape: S
    let lit: Color?
    @Environment(\.chipIdle) private var unlit

    var body: some View {
        shape.fill(lit ?? unlit)
    }
}

private typealias State = SGLyricsAttributes.ContentState
private typealias Tab = SGLyricsAttributes.Tab

private func color(_ rgb: Int) -> Color {
    Color(red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255, blue: Double(rgb & 0xFF) / 255)
}

// The card's look as the tweak worked it out from the Card color setting. The lock screen's card is the
// system's: an extension tints it and draws on it, and cannot draw glass of its own that sees the
// wallpaper. No tint leaves the system's material, and a tint that is not opaque lets it show through.
extension SGLyricsAttributes.ContentState {
    var lit: Color {
        guard let accent else { return green }
        return color(accent)
    }

    var cardTint: Color? {
        guard let fill else { return nil }
        return color(fill).opacity(fillAlpha ?? 1)
    }

    var chipIdle: Color {
        (fillAlpha ?? 1) < 0.2 ? Color.black.opacity(0.24) : idle
    }
}

@main
struct SGLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        SGLyricsLiveActivity()
    }
}

extension SGLyricsAttributes.Tab {
    var symbol: String {
        switch self {
        case .controls: "slider.horizontal.3"
        case .queue: "list.bullet"
        case .timer: "moon.zzz"
        }
    }

    var title: String {
        switch self {
        case .controls: "Controls"
        case .queue: "Queue"
        case .timer: "Timer"
        }
    }
}

struct SGLyricsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SGLyricsAttributes.self) { context in
            ContentView(state: context.state, upNext: 4)
                .environment(\.chipIdle, context.state.chipIdle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, context.state.view == .panel ? 12 : 16)
                .padding(.vertical, 12)
                .foregroundStyle(.white)
                .activityBackgroundTint(context.state.cardTint)
                .activitySystemActionForegroundColor(.white)
                .widgetURL(URL(string: "spotify:"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    Group {
                        if context.state.view == .panel {
                            Summary(state: context.state)
                        } else {
                            ContentView(state: context.state, upNext: 3)
                                .environment(\.chipIdle, context.state.chipIdle)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: "music.note")
                    .foregroundStyle(context.state.lit)
            } compactTrailing: {
                if let end = context.state.timerEnd, end > Date() {
                    Text(timerInterval: Date()...end, countsDown: true)
                        .monospacedDigit()
                        .foregroundStyle(context.state.lit)
                        .frame(maxWidth: 44)
                } else {
                    Image(systemName: context.state.paused ? "pause.fill" : "waveform")
                        .foregroundStyle(context.state.lit)
                }
            } minimal: {
                Image(systemName: "music.note")
                    .foregroundStyle(context.state.lit)
            }
            .widgetURL(URL(string: "spotify:"))
        }
    }
}

private struct ContentView: View {
    let state: State
    let upNext: Int

    var body: some View {
        switch state.view {
        case .lyrics: LyricsView(state: state)
        case .queue: QueueView(state: state, upNext: upNext)
        case .panel: PanelView(state: state)
        }
    }
}

// MARK: - Lyrics and queue

private struct LyricsView: View {
    let state: State

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(state.line)
                .font(.title3.weight(.bold))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .direction(of: state.line)
            if !state.nextLine.isEmpty {
                Text(state.nextLine)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
                    .direction(of: state.nextLine)
            }
        }
    }
}

// Whether a line is written right to left, told by its first letter the way the Unicode bidi algorithm
// tells a paragraph's direction. Each line is asked on its own, since a song can mix scripts, and the
// phone's language has no say in it. The tweak's lyrics page asks the same (SGRKaraokeView.m).
private func readsRightToLeft(_ text: String) -> Bool {
    guard let first = text.unicodeScalars.first(where: { $0.properties.isAlphabetic }) else { return false }
    switch first.value {
    case 0x0590...0x08FF,      // Hebrew, Arabic, Syriac, Thaana, N'Ko and on
         0xFB1D...0xFDFF,      // Hebrew and Arabic presentation forms
         0xFE70...0xFEFF,      // Arabic presentation forms B
         0x10800...0x10FFF,    // the old scripts written right to left
         0x1E800...0x1EFFF:    // Mende Kikakui and Adlam
        return true
    default:
        return false
    }
}

private extension View {
    // A line written right to left is laid out right to left, against the right edge; any other is left
    // the way it was.
    @ViewBuilder func direction(of line: String) -> some View {
        if readsRightToLeft(line) {
            frame(maxWidth: .infinity, alignment: .leading)
                .environment(\.layoutDirection, .rightToLeft)
        } else {
            self
        }
    }
}

private struct QueueView: View {
    let state: State
    let upNext: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Up next")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.45))
            if state.tracks.isEmpty {
                Text("Nothing up next")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
            }
            ForEach(Array(state.tracks.prefix(upNext).enumerated()), id: \.offset) { _, track in
                // A tap skips ahead to the track.
                Button(intent: SGPlayQueuedTrackIntent(track.uri)) {
                    (Text(track.title).fontWeight(.semibold) + Text("  " + track.artist).foregroundColor(.white.opacity(0.5)))
                        .font(.subheadline)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Control menu

// The expanded Dynamic Island has room for one line of the menu.
private struct Summary: View {
    let state: State

    var body: some View {
        Group {
            switch state.tab {
            case .controls:
                Text("\(state.title) · \(state.artist)")
            case .queue:
                Text(state.tracks.first.map { "Next: \($0.title)" } ?? "Nothing up next")
            case .timer:
                if let end = state.timerEnd, end > Date() {
                    Text("Music stops in \(Text(timerInterval: Date()...end, countsDown: true))")
                } else if state.timerEndOfTrack {
                    Text("Music stops at the end of this track")
                } else {
                    Text("No sleep timer")
                }
            }
        }
        .font(.subheadline.weight(.semibold))
        .lineLimit(1)
        .invalidatableContent()
    }
}

private struct PanelView: View {
    let state: State

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    Toggle(isOn: tab == state.tab, intent: SGLiveActivityActionIntent("tab:\(tab.rawValue)")) {
                        EmptyView()
                    }
                    .toggleStyle(TabStyle(tab: tab, accent: state.lit))
                }
            }
            Group {
                switch state.tab {
                case .controls: ControlsPage(state: state)
                case .queue: QueuePage(state: state)
                case .timer: TimerPage(state: state)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct TabStyle: ToggleStyle {
    let tab: Tab
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            Image(systemName: tab.symbol)
            if configuration.isOn {
                Text(tab.title)
            }
        }
        .font(.caption.weight(.semibold))
        .frame(maxWidth: .infinity)
        .frame(height: 24)
        .background(Plate(shape: Capsule(), lit: configuration.isOn ? accent.opacity(0.22) : nil))
        .foregroundStyle(configuration.isOn ? accent : .white.opacity(0.7))
    }
}

private struct ChipLabel: View {
    let symbol: String
    let label: String

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
            Text(label)
                .font(.caption2.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 48)
    }
}

private struct ChipStyle: ToggleStyle {
    let symbol: String
    var onSymbol: String?
    let label: String
    var onLabel: String?
    // Play and pause flips its symbol but is not a setting, so it keeps the idle fill either way.
    var lights = true
    var accent = green

    func makeBody(configuration: Configuration) -> some View {
        let on = configuration.isOn
        ChipLabel(symbol: on ? onSymbol ?? symbol : symbol, label: on ? onLabel ?? label : label)
            .background(Plate(shape: RoundedRectangle(cornerRadius: 12, style: .continuous), lit: on && lights ? accent.opacity(0.22) : nil))
            .foregroundStyle(on && lights ? accent : .white)
    }
}

private struct ChipButton: View {
    let action: String
    let symbol: String
    let label: String
    var lit = false
    var accent = green

    var body: some View {
        Button(intent: SGLiveActivityActionIntent(action)) {
            ChipLabel(symbol: symbol, label: label)
                .background(Plate(shape: RoundedRectangle(cornerRadius: 12, style: .continuous), lit: lit ? accent.opacity(0.22) : nil))
                .foregroundStyle(lit ? accent : .white)
        }
        .buttonStyle(.plain)
    }
}

private struct ControlsPage: View {
    let state: State

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(state.title)
                    .font(.subheadline.weight(.semibold))
                Text(state.artist)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.55))
            }
            .lineLimit(1)
            .invalidatableContent()
            HStack(spacing: 6) {
                ChipButton(action: "previous", symbol: "backward.fill", label: "Previous")
                Toggle(isOn: !state.paused, intent: SGLiveActivityActionIntent("toggle")) { EmptyView() }
                    .toggleStyle(ChipStyle(symbol: "play.fill", onSymbol: "pause.fill", label: "Play", onLabel: "Pause", lights: false))
                ChipButton(action: "next", symbol: "forward.fill", label: "Next")
                Toggle(isOn: state.shuffle, intent: SGLiveActivityActionIntent("shuffle")) { EmptyView() }
                    .toggleStyle(ChipStyle(symbol: "shuffle", label: "Shuffle", accent: state.lit))
                // Three states, so a button: the new one shows once the render lands.
                ChipButton(action: "repeat", symbol: state.repeatMode == 2 ? "repeat.1" : "repeat",
                           label: "Repeat", lit: state.repeatMode != 0, accent: state.lit)
                    .invalidatableContent()
            }
        }
    }
}

private struct QueuePage: View {
    let state: State

    var body: some View {
        VStack(spacing: 4) {
            if state.tracks.isEmpty {
                Text("Nothing up next")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(maxWidth: .infinity, minHeight: 60)
            }
            ForEach(Array(state.tracks.prefix(3).enumerated()), id: \.offset) { _, track in
                Button(intent: SGPlayQueuedTrackIntent(track.uri)) {
                    HStack(spacing: 10) {
                        Image(systemName: "play.fill")
                            .font(.caption)
                            .foregroundStyle(state.lit)
                        Text(track.title)
                            .font(.footnote.weight(.semibold))
                        Text(track.artist)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.55))
                        Spacer(minLength: 0)
                    }
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(Plate(shape: RoundedRectangle(cornerRadius: 10, style: .continuous), lit: nil))
                }
                .buttonStyle(.plain)
            }
        }
        .invalidatableContent()
    }
}

private struct TimerPage: View {
    let state: State

    var body: some View {
        Group {
            if (state.timerEnd.map { $0 > Date() } ?? false) || state.timerEndOfTrack {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Music stops")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.55))
                        if let end = state.timerEnd {
                            Text(timerInterval: Date()...end, countsDown: true)
                                .font(.system(size: 34, weight: .bold).monospacedDigit())
                                .foregroundStyle(state.lit)
                        } else {
                            Text("End of track")
                                .font(.title2.weight(.bold))
                                .foregroundStyle(state.lit)
                        }
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: 8) {
                        if state.timerEnd != nil {
                            ChipButton(action: "timer:add", symbol: "plus", label: "15 min")
                        }
                        ChipButton(action: "timer:cancel", symbol: "xmark", label: "Cancel")
                    }
                    .frame(width: state.timerEnd != nil ? 140 : 66)
                }
            } else {
                HStack(spacing: 8) {
                    ChipButton(action: "timer:15", symbol: "moon", label: "15 min")
                    ChipButton(action: "timer:30", symbol: "moon", label: "30 min")
                    ChipButton(action: "timer:60", symbol: "moon", label: "1 hour")
                    ChipButton(action: "timer:track", symbol: "music.note", label: "End of track")
                }
            }
        }
        .invalidatableContent()
    }
}
