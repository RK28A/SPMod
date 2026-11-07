import SwiftUI
import UIKit

enum PlaylistSort: String, CaseIterable, Identifiable {
    case title
    case artist
    case album
    case duration
    case addedAt
    case releaseYear
    case random

    var id: String { rawValue }
    var title: String { "playlist_sort_\(rawValue)".localized }

    func sorted(_ entries: [PlaylistEntry]) -> [PlaylistEntry] {
        let compare: (String, String) -> Bool = {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
        switch self {
        case .title: return entries.sorted { compare($0.track.name, $1.track.name) }
        case .artist: return entries.sorted { compare($0.track.artistNames, $1.track.artistNames) }
        case .album: return entries.sorted { compare($0.track.album?.name ?? "", $1.track.album?.name ?? "") }
        case .duration: return entries.sorted { ($0.track.duration_ms ?? 0) < ($1.track.duration_ms ?? 0) }
        case .addedAt: return entries.sorted { ($0.addedAt ?? .distantPast) < ($1.addedAt ?? .distantPast) }
        case .releaseYear: return entries.sorted { $0.track.releaseYear < $1.track.releaseYear }
        case .random: return entries.shuffled()
        }
    }
}

final class PlaylistDetailModel: ObservableObject {
    let playlist: WebPlaylist
    @Published var entries: [PlaylistEntry] = []
    @Published var isLoading = false
    @Published var isWorking = false
    @Published var errorMessage: String?
    @Published var undoSnapshot: [String]?

    init(playlist: WebPlaylist) {
        self.playlist = playlist
    }

    var duplicates: [PlaylistEntry] {
        var seen = Set<String>()
        return entries.filter { entry in
            guard entry.track.is_local != true else {
                return false
            }
            return !seen.insert(entry.track.uri).inserted
        }
    }

    func load() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let result = try await SpotifyWebAPI.entries(of: playlist.id)
                await MainActor.run {
                    self.entries = result
                    self.isLoading = false
                }
            }
            catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }

    func run(_ work: @escaping () async throws -> Void, keepUndo: Bool = true) {
        let snapshot = entries.filter { $0.track.is_local != true }.map(\.track.uri)
        let hasLocal = entries.contains { $0.track.is_local == true }
        isWorking = true
        Task {
            do {
                try await work()
                await MainActor.run {
                    self.isWorking = false
                    self.undoSnapshot = keepUndo && !hasLocal ? snapshot : nil
                    ToastHelper.show("playlist_done".localized)
                }
                await MainActor.run { self.load() }
            }
            catch {
                await MainActor.run {
                    self.isWorking = false
                    ToastHelper.show(error.localizedDescription)
                }
            }
        }
    }

    func undo() {
        guard let snapshot = undoSnapshot else {
            return
        }
        let id = playlist.id
        run({ try await SpotifyWebAPI.replaceAll(snapshot, in: id) }, keepUndo: false)
        undoSnapshot = nil
    }
}

struct SPModPlaylistDetailView: View {
    @StateObject private var model: PlaylistDetailModel
    @State private var search = ""
    @State private var artistFilter = ""
    @State private var sort: PlaylistSort = .title
    @State private var isSelecting = false
    @State private var selected = Set<String>()

    init(playlist: WebPlaylist) {
        _model = StateObject(wrappedValue: PlaylistDetailModel(playlist: playlist))
    }

    private var artists: [String] {
        Array(Set(model.entries.map(\.track.primaryArtist).filter { !$0.isEmpty }))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var visibleEntries: [PlaylistEntry] {
        model.entries.filter { entry in
            let matchesSearch = search.isEmpty
                || entry.track.name.localizedCaseInsensitiveContains(search)
                || entry.track.artistNames.localizedCaseInsensitiveContains(search)
                || (entry.track.album?.name ?? "").localizedCaseInsensitiveContains(search)
            let matchesArtist = artistFilter.isEmpty || entry.track.primaryArtist == artistFilter
            return matchesSearch && matchesArtist
        }
    }

    private var selectedEntries: [PlaylistEntry] {
        model.entries.filter { selected.contains($0.id) }
    }

    private var editableURIs: (uris: [String], hasLocal: Bool) {
        (model.entries.filter { $0.track.is_local != true }.map(\.track.uri), model.entries.contains { $0.track.is_local == true })
    }

    private func applySort() {
        let ordered = sort.sorted(model.entries.filter { $0.track.is_local != true }).map(\.track.uri)
        guard !editableURIs.hasLocal else {
            ToastHelper.show("playlist_local_files_blocked".localized)
            return
        }
        let id = model.playlist.id
        SPModAlertHelper.confirm([
            SPModAlertStep(
                title: "playlist_sort_apply".localized,
                message: "playlist_sort_preview".localizeWithFormat(ordered.count, sort.title),
                confirmTitle: "confirm".localized
            )
        ]) {
            model.run { try await SpotifyWebAPI.replaceAll(ordered, in: id) }
        }
    }

    private func removeDuplicates() {
        let duplicates = model.duplicates
        guard !duplicates.isEmpty else {
            ToastHelper.show("playlist_no_duplicates".localized)
            return
        }
        let id = model.playlist.id
        let keep = editableURIs
        SPModAlertHelper.confirm([
            SPModAlertStep(
                title: "playlist_remove_duplicates".localized,
                message: "playlist_duplicates_preview".localizeWithFormat(duplicates.count),
                confirmTitle: "history_delete_entry".localized,
                isDestructive: true
            )
        ]) {
            if keep.hasLocal {
                model.run { try await SpotifyWebAPI.remove(duplicates, from: id) }
            }
            else {
                var seen = Set<String>()
                let unique = keep.uris.filter { seen.insert($0).inserted }
                model.run { try await SpotifyWebAPI.replaceAll(unique, in: id) }
            }
        }
    }

    private func removeSelected() {
        let entries = selectedEntries
        guard !entries.isEmpty else {
            return
        }
        let id = model.playlist.id
        SPModAlertHelper.confirm([
            SPModAlertStep(
                title: "playlist_remove_selected".localized,
                message: "playlist_remove_preview".localizeWithFormat(entries.count),
                confirmTitle: "history_delete_entry".localized,
                isDestructive: true
            )
        ]) {
            model.run { try await SpotifyWebAPI.remove(entries, from: id) }
            selected.removeAll()
        }
    }

    private func sendSelected(move: Bool) {
        let entries = selectedEntries.filter { $0.track.is_local != true }
        guard !entries.isEmpty else {
            return
        }
        let sourceId = model.playlist.id
        SPModSettingsNavigator.push(
            SPModPlaylistPickerView(excluding: sourceId) { destination in
                SPModAlertHelper.confirm([
                    SPModAlertStep(
                        title: move ? "playlist_move".localized : "playlist_copy".localized,
                        message: "playlist_send_preview".localizeWithFormat(entries.count, destination.name),
                        confirmTitle: "confirm".localized
                    )
                ]) {
                    model.run({
                        try await SpotifyWebAPI.add(entries.map(\.track.uri), to: destination.id)
                        if move {
                            try await SpotifyWebAPI.remove(entries, from: sourceId)
                        }
                    }, keepUndo: false)
                    QuickAddStore.remember(id: destination.id, name: destination.name)
                    selected.removeAll()
                }
            },
            title: "playlist_choose_destination".localized
        )
    }

    private func createFromSelection() {
        let uris = selectedEntries.filter { $0.track.is_local != true }.map(\.track.uri)
        guard !uris.isEmpty else {
            return
        }
        let alert = UIAlertController(title: "playlist_create".localized, message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "playlist_name".localized
            field.text = "\(model.playlist.name) – SPMod"
        }
        alert.addAction(UIAlertAction(title: "cancel".localized, style: .cancel))
        alert.addAction(UIAlertAction(title: "confirm".localized, style: .default) { _ in
            let name = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespaces) ?? ""
            model.run({
                let playlist = try await SpotifyWebAPI.createPlaylist(named: name.isEmpty ? "SPMod" : name, uris: uris)
                QuickAddStore.remember(id: playlist.id, name: playlist.name)
            }, keepUndo: false)
            selected.removeAll()
        })
        SPModAlertHelper.present(alert)
    }

    private func smartShuffle() {
        let tracks = model.entries.map(\.track)
        let id = model.playlist.id
        Task {
            do {
                let count = try await SmartShuffle.play(tracks, playlistId: id)
                ToastHelper.show("smart_shuffle_started".localizeWithFormat(count))
            }
            catch {
                ToastHelper.show(error.localizedDescription)
            }
        }
    }

    var body: some View {
        List {
            Section {
                Button {
                    smartShuffle()
                } label: {
                    Label("smart_shuffle_play".localizeWithFormat(UserDefaults.smartShuffleOptions.mode.title), systemImage: "shuffle")
                }
                Button {
                    QuickAddStore.pinned = QuickAddStore.Target(id: model.playlist.id, name: model.playlist.name)
                    ToastHelper.show("quick_add_pinned".localizeWithFormat(model.playlist.name))
                } label: {
                    Label("quick_add_pin_this".localized, systemImage: "pin.fill")
                }
                Button {
                    removeDuplicates()
                } label: {
                    Label("playlist_remove_duplicates_count".localizeWithFormat(model.duplicates.count), systemImage: "doc.on.doc")
                }
                if model.undoSnapshot != nil {
                    Button {
                        model.undo()
                    } label: {
                        Label("playlist_undo".localized, systemImage: "arrow.uturn.backward")
                    }
                }
            }

            Section(header: Text("playlist_sort".localized)) {
                Picker("playlist_sort_by".localized, selection: $sort) {
                    ForEach(PlaylistSort.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                Button("playlist_sort_apply".localized) {
                    applySort()
                }
            }

            Section(header: Text("playlist_tracks".localized)) {
                TextField("history_search".localized, text: $search)
                Picker("playlist_filter_artist".localized, selection: $artistFilter) {
                    Text("history_filter_all".localized).tag("")
                    ForEach(artists, id: \.self) { artist in
                        Text(artist).tag(artist)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                Toggle("playlist_select_mode".localized, isOn: $isSelecting)

                if isSelecting {
                    HStack {
                        Button("playlist_select_all".localized) {
                            selected = Set(visibleEntries.map(\.id))
                        }
                        .buttonStyle(BorderlessButtonStyle())
                        Spacer()
                        Text("playlist_selected_count".localizeWithFormat(selected.count))
                            .foregroundColor(.gray)
                        Spacer()
                        Button("playlist_select_none".localized) {
                            selected.removeAll()
                        }
                        .buttonStyle(BorderlessButtonStyle())
                    }
                    if !selected.isEmpty {
                        Button("playlist_copy".localized) { sendSelected(move: false) }
                        Button("playlist_move".localized) { sendSelected(move: true) }
                        Button("playlist_create".localized) { createFromSelection() }
                        Button("playlist_remove_selected".localized) { removeSelected() }
                            .foregroundColor(.red)
                    }
                }

                if model.isLoading || model.isWorking {
                    ProgressView()
                }
                if let message = model.errorMessage {
                    Text(message).foregroundColor(.red)
                }

                ForEach(visibleEntries) { entry in
                    Button {
                        if isSelecting {
                            if selected.contains(entry.id) {
                                selected.remove(entry.id)
                            }
                            else {
                                selected.insert(entry.id)
                            }
                        }
                        else if let url = URL(string: entry.track.uri) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 10) {
                            if isSelecting {
                                Image(systemName: selected.contains(entry.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(selected.contains(entry.id) ? EeveeSettingsView.spotifyAccentColor : .gray)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.track.name)
                                    .foregroundColor(entry.track.is_local == true ? .gray : .white)
                                    .lineLimit(1)
                                Text(entry.track.artistNames)
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(TimeInterval(Double(entry.track.duration_ms ?? 0) / 1000).spmodClock)
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                }
            }

            NonIPadSpacerView()
        }
        .listStyle(GroupedListStyle())
        .disabled(model.isWorking)
        .onAppear {
            if model.entries.isEmpty {
                model.load()
            }
        }
    }
}
