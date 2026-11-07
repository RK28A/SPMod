import SwiftUI
import UIKit

struct PeriodPickerSection: View {
    @Binding var period: StatsPeriod
    @Binding var customStart: Date
    @Binding var customEnd: Date

    var body: some View {
        Section(header: Text("stats_period".localized)) {
            Picker("stats_period".localized, selection: $period) {
                ForEach(StatsPeriod.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(MenuPickerStyle())

            if period == .custom {
                DatePicker("period_from".localized, selection: $customStart, in: ...Date(), displayedComponents: .date)
                DatePicker("period_to".localized, selection: $customEnd, in: ...Date(), displayedComponents: .date)
            }
        }
    }
}

struct SPModStatsView: View {
    @StateObject private var model = ListeningDataModel()
    @State private var period: StatsPeriod = .last7Days
    @State private var customStart = Calendar.current.date(byAdding: .day, value: -6, to: Date()) ?? Date()
    @State private var customEnd = Date()
    @State private var rankingKind: RankingKind = .tracks
    @State private var rankingLimit = 10
    @State private var compare = true

    private var interval: DateInterval {
        period.interval(customStart: customStart, customEnd: customEnd, firstRecord: model.records.first?.start)
    }

    private func dayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("dMMM")
        return formatter.string(from: date)
    }

    var body: some View {
        let stats = ListeningStats(all: model.records, interval: interval)
        let summary = stats.summary
        let previous = ListeningStats(all: model.records, interval: stats.previousInterval).summary
        let daily = stats.dailyTotals()
        let hourly = stats.hourlyTotals()
        let ranking = stats.ranking(rankingKind, limit: rankingLimit)
        let topArtists = stats.ranking(.artists, limit: 5)

        List {
            PeriodPickerSection(period: $period, customStart: $customStart, customEnd: $customEnd)

            if !UserDefaults.listeningCollectionEnabled {
                Section {
                    Text("listening_collection_disabled_notice".localized)
                        .foregroundColor(.orange)
                        .font(.footnote)
                }
            }

            Section(header: Text("stats_overview".localized)) {
                Toggle("stats_compare".localized, isOn: $compare)

                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        StatTile(
                            title: "stats_listening_time".localized,
                            value: summary.listened.spmodDuration,
                            change: compare ? ListeningStats.change(current: summary.listened, previous: previous.listened) : nil
                        )
                        StatTile(
                            title: "stats_plays".localized,
                            value: "\(summary.plays)",
                            change: compare ? ListeningStats.change(current: Double(summary.plays), previous: Double(previous.plays)) : nil
                        )
                    }
                    HStack(spacing: 8) {
                        StatTile(title: "stats_minutes".localized, value: "\(Int((summary.listened / 60).rounded()))")
                        StatTile(title: "stats_hours".localized, value: String(format: "%.1f", summary.listened / 3600))
                    }
                    HStack(spacing: 8) {
                        StatTile(title: "stats_tracks".localized, value: "\(summary.uniqueTracks)")
                        StatTile(title: "stats_artists".localized, value: "\(summary.uniqueArtists)")
                        StatTile(title: "stats_albums".localized, value: "\(summary.uniqueAlbums)")
                    }
                    HStack(spacing: 8) {
                        StatTile(title: "stats_per_day".localized, value: summary.averagePerDay.spmodDuration)
                        StatTile(title: "stats_sessions".localized, value: "\(summary.sessions)")
                        StatTile(title: "stats_avg_session".localized, value: summary.averageSession.spmodDuration)
                    }
                }
                .padding(.vertical, 4)
            }

            if summary.plays > 0 {
                Section(header: Text("stats_daily_chart".localized)) {
                    BarChartView(
                        values: daily.map { $0.listened },
                        labels: daily.map { dayLabel($0.date) }
                    )
                }

                Section(header: Text("stats_trend_chart".localized)) {
                    LineChartView(values: daily.reduce(into: [Double]()) { result, day in
                        result.append((result.last ?? 0) + day.listened)
                    })
                }

                Section(header: Text("stats_hours_chart".localized)) {
                    BarChartView(
                        values: hourly,
                        labels: (0..<24).map { "\($0) h" }
                    )
                }

                if !topArtists.isEmpty {
                    Section(header: Text("stats_artist_share".localized)) {
                        ShareBarView(entries: topArtists)
                    }
                }

                Section(header: Text("stats_ranking".localized)) {
                    Picker("stats_ranking".localized, selection: $rankingKind) {
                        ForEach(RankingKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())

                    Picker("stats_ranking_size".localized, selection: $rankingLimit) {
                        ForEach([10, 25, 50, 100], id: \.self) { limit in
                            Text("Top \(limit)").tag(limit)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())

                    ForEach(Array(ranking.enumerated()), id: \.element.id) { index, entry in
                        NavigationLinkButton {
                            SPModStatsDetailView(entry: entry, records: stats.records(for: entry))
                        } label: {
                            RankingRow(rank: index + 1, entry: entry)
                        }
                    }
                }
            }
            else {
                Section {
                    Text("stats_empty".localized)
                        .foregroundColor(.gray)
                }
            }

            NonIPadSpacerView()
        }
        .listStyle(GroupedListStyle())
    }
}

struct NavigationLinkButton<Destination: View, Label: View>: View {
    let destination: () -> Destination
    let label: () -> Label

    init(@ViewBuilder destination: @escaping () -> Destination, @ViewBuilder label: @escaping () -> Label) {
        self.destination = destination
        self.label = label
    }

    var body: some View {
        Button {
            SPModSettingsNavigator.push(destination(), title: "")
        } label: {
            label()
        }
    }
}

enum SPModSettingsNavigator {
    static weak var navigationController: UINavigationController?

    static func push<Content: View>(_ view: Content, title: String) {
        guard let navigationController = navigationController else {
            return
        }
        let controller = EeveeSettingsViewController(
            navigationController.view.frame,
            settingsView: AnyView(view),
            navigationTitle: title
        )
        navigationController.pushViewController(controller, animated: true)
    }
}

struct SPModStatsDetailView: View {
    let entry: RankingEntry
    let records: [PlayRecord]

    private var firstPlay: Date? { records.map(\.start).min() }
    private var lastPlay: Date? { records.map(\.start).max() }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }

    var body: some View {
        let total = records.reduce(0) { $0 + $1.listened }
        let completed = records.filter(\.completed).count
        let interval = DateInterval(
            start: Calendar.current.startOfDay(for: firstPlay ?? Date()),
            end: Date()
        )
        let stats = ListeningStats(all: records, interval: interval)
        let daily = stats.dailyTotals().suffix(60)
        let topTracks = entry.kind == .tracks ? [] : stats.ranking(.tracks, limit: 10)

        List {
            Section {
                HStack(spacing: 14) {
                    ArtworkView(key: entry.artworkKey, size: 72, isArtist: entry.kind == .artists)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.title)
                            .font(.headline)
                            .foregroundColor(.white)
                        if !entry.subtitle.isEmpty {
                            Text(entry.subtitle)
                                .foregroundColor(.gray)
                        }
                    }
                }
                .padding(.vertical, 6)
            }

            Section(header: Text("stats_overview".localized)) {
                HStack(spacing: 8) {
                    StatTile(title: "stats_plays".localized, value: "\(records.count)")
                    StatTile(title: "stats_listening_time".localized, value: total.spmodDuration)
                }
                HStack(spacing: 8) {
                    StatTile(title: "stats_completed".localized, value: "\(completed)")
                    StatTile(title: "stats_skipped".localized, value: "\(records.count - completed)")
                }
                if let firstPlay = firstPlay {
                    HStack {
                        Text("stats_first_play".localized)
                        Spacer()
                        Text(dateFormatter.string(from: firstPlay)).foregroundColor(.gray)
                    }
                }
                if let lastPlay = lastPlay {
                    HStack {
                        Text("stats_last_play".localized)
                        Spacer()
                        Text(dateFormatter.string(from: lastPlay)).foregroundColor(.gray)
                    }
                }
            }

            if !daily.isEmpty {
                Section(header: Text("stats_daily_chart".localized)) {
                    BarChartView(
                        values: daily.map { $0.listened },
                        labels: daily.map { DateFormatter.localizedString(from: $0.date, dateStyle: .short, timeStyle: .none) }
                    )
                }
            }

            if !topTracks.isEmpty {
                Section(header: Text("ranking_tracks".localized)) {
                    ForEach(Array(topTracks.enumerated()), id: \.element.id) { index, track in
                        RankingRow(rank: index + 1, entry: track)
                    }
                }
            }

            if entry.kind == .tracks {
                Section {
                    Button("listening_open_in_spotify".localized) {
                        SpotifyOpener.openTrack(entry.trackId)
                    }
                    .disabled(entry.trackId.isEmpty)
                }
            }

            NonIPadSpacerView()
        }
        .listStyle(GroupedListStyle())
    }
}
