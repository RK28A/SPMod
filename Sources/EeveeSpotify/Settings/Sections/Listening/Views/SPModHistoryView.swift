import SwiftUI
import UIKit

enum HistoryGrouping: String, CaseIterable, Identifiable {
    case day
    case week
    case month

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: return "history_group_day".localized
        case .week: return "history_group_week".localized
        case .month: return "history_group_month".localized
        }
    }

    var component: Calendar.Component {
        switch self {
        case .day: return .day
        case .week: return .weekOfYear
        case .month: return .month
        }
    }
}

enum HistoryDurationFilter: Int, CaseIterable, Identifiable {
    case all
    case completed
    case skipped
    case overOneMinute

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .all: return "history_filter_all".localized
        case .completed: return "history_filter_completed".localized
        case .skipped: return "history_filter_skipped".localized
        case .overOneMinute: return "history_filter_over_minute".localized
        }
    }

    func matches(_ record: PlayRecord) -> Bool {
        switch self {
        case .all: return true
        case .completed: return record.completed
        case .skipped: return !record.completed
        case .overOneMinute: return record.listened >= 60
        }
    }
}

struct HistoryGroup: Identifiable {
    let start: Date
    let records: [PlayRecord]
    var id: Date { start }
}

struct SPModHistoryView: View {
    @StateObject private var model = ListeningDataModel()
    @State private var search = ""
    @State private var grouping: HistoryGrouping = .day
    @State private var period: StatsPeriod = .allTime
    @State private var customStart = Calendar.current.date(byAdding: .day, value: -6, to: Date()) ?? Date()
    @State private var customEnd = Date()
    @State private var durationFilter: HistoryDurationFilter = .all
    @State private var visibleLimit = 300

    private var filtered: [PlayRecord] {
        let interval = period.interval(customStart: customStart, customEnd: customEnd, firstRecord: model.records.first?.start)
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return model.records.reversed().filter { record in
            guard interval.contains(record.start), durationFilter.matches(record) else {
                return false
            }
            guard !query.isEmpty else {
                return true
            }
            return record.title.lowercased().contains(query)
                || record.artist.lowercased().contains(query)
                || record.album.lowercased().contains(query)
        }
    }

    private func groupTitle(_ date: Date) -> String {
        let formatter = DateFormatter()
        switch grouping {
        case .day:
            formatter.dateStyle = .full
            formatter.timeStyle = .none
            return formatter.string(from: date)
        case .week:
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return "history_week_of".localizeWithFormat(formatter.string(from: date))
        case .month:
            formatter.setLocalizedDateFormatFromTemplate("MMMMyyyy")
            return formatter.string(from: date).capitalized
        }
    }

    private func groups(_ records: [PlayRecord]) -> [HistoryGroup] {
        let calendar = Calendar.current
        var order: [Date] = []
        var map: [Date: [PlayRecord]] = [:]
        for record in records {
            let start = calendar.dateInterval(of: grouping.component, for: record.start)?.start
                ?? calendar.startOfDay(for: record.start)
            if map[start] == nil {
                order.append(start)
            }
            map[start, default: []].append(record)
        }
        return order.map { HistoryGroup(start: $0, records: map[$0] ?? []) }
    }

    private func createPlaylist(from records: [PlayRecord]) {
        var seen = Set<String>()
        let uris = records
            .sorted { $0.start < $1.start }
            .compactMap { $0.trackId.isEmpty ? nil : "spotify:track:\($0.trackId)" }
            .filter { seen.insert($0).inserted }
        guard !uris.isEmpty else {
            return
        }
        let alert = UIAlertController(
            title: "playlist_create".localized,
            message: "history_create_playlist_preview".localizeWithFormat(uris.count),
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.placeholder = "playlist_name".localized
            field.text = "SPMod – \(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .none))"
        }
        alert.addAction(UIAlertAction(title: "cancel".localized, style: .cancel))
        alert.addAction(UIAlertAction(title: "confirm".localized, style: .default) { _ in
            let name = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespaces) ?? ""
            Task {
                do {
                    let playlist = try await SpotifyWebAPI.createPlaylist(named: name.isEmpty ? "SPMod" : name, uris: uris)
                    QuickAddStore.remember(id: playlist.id, name: playlist.name)
                    ToastHelper.show("playlist_done".localized)
                }
                catch {
                    ToastHelper.show(error.localizedDescription)
                }
            }
        })
        SPModAlertHelper.present(alert)
    }

    private func actions(for record: PlayRecord) {
        let sheet = UIAlertController(title: record.title, message: record.artist, preferredStyle: .actionSheet)
        if !record.trackId.isEmpty {
            sheet.addAction(UIAlertAction(title: "listening_open_in_spotify".localized, style: .default) { _ in
                SpotifyOpener.openTrack(record.trackId)
            })
        }
        sheet.addAction(UIAlertAction(title: "copy_on_shake_copy".localized, style: .default) { _ in
            UIPasteboard.general.string = record.trackId.isEmpty
                ? "\(record.title) – \(record.artist)"
                : "https://open.spotify.com/track/\(record.trackId)"
            ToastHelper.show("copied_to_clipboard".localized)
        })
        if !record.trackId.isEmpty {
            sheet.addAction(UIAlertAction(title: "history_add_to_playlist".localized, style: .default) { _ in
                let uri = "spotify:track:\(record.trackId)"
                SPModSettingsNavigator.push(
                    SPModPlaylistPickerView(excluding: nil) { playlist in
                        Task {
                            do {
                                try await SpotifyWebAPI.add([uri], to: playlist.id)
                                QuickAddStore.remember(id: playlist.id, name: playlist.name)
                                ToastHelper.show("quick_add_done".localizeWithFormat(playlist.name))
                            }
                            catch {
                                ToastHelper.show(error.localizedDescription)
                            }
                        }
                    },
                    title: "playlist_choose_destination".localized
                )
            })
        }
        sheet.addAction(UIAlertAction(title: "history_delete_entry".localized, style: .destructive) { _ in
            ListeningStore.shared.delete(ids: [record.id])
        })
        sheet.addAction(UIAlertAction(title: "cancel".localized, style: .cancel))
        SPModAlertHelper.present(sheet)
    }

    var body: some View {
        let records = filtered
        let visible = Array(records.prefix(visibleLimit))
        let total = records.reduce(0) { $0 + $1.listened }

        List {
            Section {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    TextField("history_search".localized, text: $search)
                        .disableAutocorrection(true)
                }

                Picker("history_grouping".localized, selection: $grouping) {
                    ForEach(HistoryGrouping.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())

                Picker("history_filter".localized, selection: $durationFilter) {
                    ForEach(HistoryDurationFilter.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(MenuPickerStyle())
            }

            PeriodPickerSection(period: $period, customStart: $customStart, customEnd: $customEnd)

            Section {
                Button {
                    SPModSettingsNavigator.push(SPModHistoryCalendarView(), title: "history_calendar".localized)
                } label: {
                    Label("history_calendar".localized, systemImage: "calendar")
                }
                HStack {
                    Text("history_results".localizeWithFormat(records.count))
                    Spacer()
                    Text(total.spmodDuration)
                        .foregroundColor(.gray)
                }
                .font(.footnote)
                Button {
                    createPlaylist(from: records)
                } label: {
                    Label("history_create_playlist".localized, systemImage: "music.note.list")
                }
                .disabled(records.allSatisfy { $0.trackId.isEmpty })
            }

            if records.isEmpty {
                Section {
                    Text("history_empty".localized)
                        .foregroundColor(.gray)
                }
            }

            ForEach(groups(visible)) { group in
                Section(header: Text(groupTitle(group.start))) {
                    ForEach(group.records) { record in
                        Button {
                            actions(for: record)
                        } label: {
                            HistoryRow(record: record)
                        }
                    }
                    .onDelete { offsets in
                        let ids = Set(offsets.compactMap { group.records.indices.contains($0) ? group.records[$0].id : nil })
                        ListeningStore.shared.delete(ids: ids)
                    }
                }
            }

            if records.count > visible.count {
                Section {
                    Button("history_show_more".localized) {
                        visibleLimit += 300
                    }
                }
            }

            NonIPadSpacerView()
        }
        .listStyle(GroupedListStyle())
    }
}

struct SPModHistoryCalendarView: View {
    @StateObject private var model = ListeningDataModel()
    @State private var date = Date()

    var body: some View {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        let records = model.records.filter { $0.start >= start && $0.start < end }.reversed()
        let total = records.reduce(0) { $0 + $1.listened }

        List {
            Section {
                DatePicker("", selection: $date, in: ...Date(), displayedComponents: .date)
                    .datePickerStyle(GraphicalDatePickerStyle())
                    .labelsHidden()
            }

            Section(header: Text("history_day_total".localizeWithFormat(total.spmodDuration))) {
                if records.isEmpty {
                    Text("history_empty".localized)
                        .foregroundColor(.gray)
                }
                ForEach(Array(records)) { record in
                    HistoryRow(record: record)
                }
            }

            NonIPadSpacerView()
        }
        .listStyle(GroupedListStyle())
    }
}
