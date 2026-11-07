import SwiftUI
import UIKit

final class ListeningDataModel: ObservableObject {
    @Published var records: [PlayRecord] = []
    private var observer: NSObjectProtocol?

    init() {
        reload()
        observer = NotificationCenter.default.addObserver(
            forName: ListeningStore.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reload()
        }
    }

    deinit {
        if let observer = observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func reload() {
        DispatchQueue.global(qos: .userInitiated).async {
            let records = ListeningStore.shared.allRecords()
            DispatchQueue.main.async {
                self.records = records
            }
        }
    }
}

struct ArtworkView: View {
    let key: String
    var size: CGFloat = 44
    var isArtist = false

    var body: some View {
        Group {
            if let image = ListeningStore.shared.artwork(for: key) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
            else {
                ZStack {
                    Color.white.opacity(0.08)
                    Image(systemName: isArtist ? "person.fill" : "music.note")
                        .foregroundColor(.gray)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: isArtist ? size / 2 : 6, style: .continuous))
    }
}

struct StatTile: View {
    let title: String
    let value: String
    var change: Double? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.gray)
                .lineLimit(1)
            Text(value)
                .font(.headline)
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let change = change {
                Text(String(format: "%@%.0f %%", change >= 0 ? "+" : "", change))
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(change >= 0 ? .green : .red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.06)))
    }
}

struct BarChartView: View {
    let values: [Double]
    let labels: [String]
    var valueText: (Double) -> String = { TimeInterval($0).spmodDuration }
    var height: CGFloat = 140

    @State private var selected: Int? = nil

    var body: some View {
        let maxValue = max(values.max() ?? 0, 1)
        VStack(alignment: .leading, spacing: 6) {
            Text(selectedText)
                .font(.caption.weight(.semibold))
                .foregroundColor(.gray)
                .frame(height: 16)

            GeometryReader { geometry in
                let count = max(values.count, 1)
                let spacing: CGFloat = count > 40 ? 1 : 3
                let width = max((geometry.size.width - spacing * CGFloat(count - 1)) / CGFloat(count), 1)
                HStack(alignment: .bottom, spacing: spacing) {
                    ForEach(values.indices, id: \.self) { index in
                        RoundedRectangle(cornerRadius: min(width / 2, 3))
                            .fill(selected == index ? Color.white : EeveeSettingsView.spotifyAccentColor)
                            .frame(
                                width: width,
                                height: max(CGFloat(values[index] / maxValue) * geometry.size.height, values[index] > 0 ? 2 : 0)
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selected = selected == index ? nil : index
                            }
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .bottomLeading)
            }
            .frame(height: height)

            HStack {
                Text(labels.first ?? "")
                Spacer()
                Text(labels.last ?? "")
            }
            .font(.caption2)
            .foregroundColor(.gray)
        }
        .padding(.vertical, 4)
    }

    private var selectedText: String {
        guard let selected = selected, values.indices.contains(selected) else {
            return "chart_tap_hint".localized
        }
        let label = labels.indices.contains(selected) ? labels[selected] : ""
        return "\(label) · \(valueText(values[selected]))"
    }
}

struct LineChartView: View {
    let values: [Double]
    var height: CGFloat = 120

    var body: some View {
        GeometryReader { geometry in
            let maxValue = max(values.max() ?? 0, 1)
            let step = values.count > 1 ? geometry.size.width / CGFloat(values.count - 1) : 0
            ZStack {
                Path { path in
                    for (index, value) in values.enumerated() {
                        let point = CGPoint(
                            x: CGFloat(index) * step,
                            y: geometry.size.height - CGFloat(value / maxValue) * geometry.size.height
                        )
                        if index == 0 {
                            path.move(to: point)
                        }
                        else {
                            path.addLine(to: point)
                        }
                    }
                }
                .stroke(EeveeSettingsView.spotifyAccentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(height: height)
        .padding(.vertical, 6)
    }
}

struct ShareBarView: View {
    let entries: [RankingEntry]

    private let palette: [Color] = [.green, .blue, .purple, .orange, .pink, .gray]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        palette[index % palette.count]
                            .frame(width: geometry.size.width * CGFloat(entry.share))
                    }
                    Color.white.opacity(0.08)
                }
            }
            .frame(height: 12)
            .clipShape(Capsule())

            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                HStack(spacing: 8) {
                    Circle()
                        .fill(palette[index % palette.count])
                        .frame(width: 8, height: 8)
                    Text(entry.title)
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Spacer()
                    Text(String(format: "%.0f %%", entry.share * 100))
                        .foregroundColor(.gray)
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }
}

struct RankingRow: View {
    let rank: Int
    let entry: RankingEntry

    var body: some View {
        HStack(spacing: 10) {
            Text("\(rank)")
                .font(.footnote.weight(.bold))
                .foregroundColor(.gray)
                .frame(width: 26)

            ArtworkView(key: entry.artworkKey, size: 42, isArtist: entry.kind == .artists)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .foregroundColor(.white)
                    .lineLimit(1)
                if !entry.subtitle.isEmpty {
                    Text(entry.subtitle)
                        .font(.caption)
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("listening_plays_count".localizeWithFormat(entry.plays))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white)
                Text("\(entry.listened.spmodDuration) · \(String(format: "%.1f %%", entry.share * 100))")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
        }
    }
}

struct HistoryRow: View {
    let record: PlayRecord

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    var body: some View {
        HStack(spacing: 10) {
            ArtworkView(key: ListeningStore.artworkKey(album: record.album, artist: record.artist), size: 42)

            VStack(alignment: .leading, spacing: 2) {
                Text(record.title)
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(record.album.isEmpty ? record.artist : "\(record.artist) · \(record.album)")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(HistoryRow.timeFormatter.string(from: record.start))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white)
                HStack(spacing: 4) {
                    Image(systemName: record.completed ? "checkmark.circle.fill" : "forward.fill")
                        .foregroundColor(record.completed ? .green : .orange)
                    Text(record.listened.spmodClock)
                        .foregroundColor(.gray)
                }
                .font(.caption2)
            }
        }
    }
}

enum SpotifyOpener {
    static func openTrack(_ trackId: String) {
        let id = trackId.replacingOccurrences(of: "spotify:track:", with: "")
        guard !id.isEmpty, !id.contains(":"), let url = URL(string: "spotify:track:\(id)") else {
            ToastHelper.show("listening_no_track_link".localized)
            return
        }
        UIApplication.shared.open(url)
    }
}
