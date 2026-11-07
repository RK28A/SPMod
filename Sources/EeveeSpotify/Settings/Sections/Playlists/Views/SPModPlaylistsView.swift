import SwiftUI
import UIKit

final class PlaylistsModel: ObservableObject {
    @Published var playlists: [WebPlaylist] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func load() {
        guard !isLoading else {
            return
        }
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let result = try await SpotifyWebAPI.editablePlaylists()
                await MainActor.run {
                    self.playlists = result
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
}

struct PlaylistRow: View {
    let playlist: WebPlaylist
    var isSelected: Bool? = nil

    var body: some View {
        HStack(spacing: 12) {
            if let isSelected = isSelected {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? EeveeSettingsView.spotifyAccentColor : .gray)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.name)
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text("playlist_tracks_count".localizeWithFormat(playlist.tracks?.total ?? 0))
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            Spacer()
        }
    }
}

struct SPModPlaylistPickerView: View {
    let excluding: String?
    let onPick: (WebPlaylist) -> Void
    @StateObject private var model = PlaylistsModel()

    var body: some View {
        List {
            if model.isLoading {
                ProgressView()
            }
            if let message = model.errorMessage {
                Text(message).foregroundColor(.red)
            }
            ForEach(model.playlists.filter { $0.id != excluding }) { playlist in
                Button {
                    SPModSettingsNavigator.navigationController?.popViewController(animated: true)
                    onPick(playlist)
                } label: {
                    PlaylistRow(playlist: playlist)
                }
            }
            NonIPadSpacerView()
        }
        .listStyle(GroupedListStyle())
        .onAppear {
            model.load()
        }
    }
}

struct SPModPlaylistsView: View {
    @StateObject private var model = PlaylistsModel()
    @State private var quickAdd = QuickAddStore.destination
    @State private var pinned = QuickAddStore.pinned
    @State private var allowDuplicates = QuickAddStore.allowDuplicates

    var body: some View {
        List {
            Section(footer: Text("playlists_experimental_description".localized)) {
                HStack {
                    Image(systemName: SpotifyWebAPI.hasToken ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(SpotifyWebAPI.hasToken ? .green : .yellow)
                    Text(SpotifyWebAPI.hasToken ? "playlists_connected".localized : "playlists_waiting_token".localized)
                }
            }

            Section(
                header: Text("quick_add".localized),
                footer: Text("quick_add_description".localized)
            ) {
                HStack {
                    Text("quick_add_destination".localized)
                    Spacer()
                    Text(quickAdd?.name ?? "vault_no_folder".localized)
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
                Button("quick_add_pin".localized) {
                    SPModSettingsNavigator.push(
                        SPModPlaylistPickerView(excluding: nil) { playlist in
                            QuickAddStore.pinned = QuickAddStore.Target(id: playlist.id, name: playlist.name)
                            pinned = QuickAddStore.pinned
                            quickAdd = QuickAddStore.destination
                        },
                        title: "quick_add_pin".localized
                    )
                }
                if pinned != nil {
                    Button("quick_add_unpin".localized) {
                        QuickAddStore.pinned = nil
                        pinned = nil
                        quickAdd = QuickAddStore.destination
                    }
                    .foregroundColor(.red)
                }
                Toggle("quick_add_allow_duplicates".localized, isOn: $allowDuplicates)
                Button("quick_add_now".localized) {
                    QuickAddStore.addCurrentTrack()
                }
            }

            Section {
                Button {
                    SPModSettingsNavigator.push(SPModSmartShuffleSettingsView(), title: "smart_shuffle".localized)
                } label: {
                    NavigationSectionView(color: .green, title: "smart_shuffle".localized, imageSystemName: "shuffle")
                }
                Button {
                    SPModSettingsNavigator.push(SPModMergePlaylistsView(), title: "merge_playlists".localized)
                } label: {
                    NavigationSectionView(color: .orange, title: "merge_playlists".localized, imageSystemName: "arrow.triangle.merge")
                }
            }

            Section(header: Text("my_playlists".localized)) {
                if model.isLoading {
                    ProgressView()
                }
                if let message = model.errorMessage {
                    Text(message).foregroundColor(.red)
                    Button("retry".localized) {
                        model.load()
                    }
                }
                ForEach(model.playlists) { playlist in
                    Button {
                        SPModSettingsNavigator.push(SPModPlaylistDetailView(playlist: playlist), title: playlist.name)
                    } label: {
                        PlaylistRow(playlist: playlist)
                    }
                }
            }

            NonIPadSpacerView()
        }
        .listStyle(GroupedListStyle())
        .onAppear {
            quickAdd = QuickAddStore.destination
            model.load()
        }
        .onChange(of: allowDuplicates) { value in
            QuickAddStore.allowDuplicates = value
        }
    }
}

struct SPModMergePlaylistsView: View {
    @StateObject private var model = PlaylistsModel()
    @State private var selected = Set<String>()
    @State private var skipDuplicates = true
    @State private var isWorking = false

    private func merge(into destination: WebPlaylist) {
        let sources = model.playlists.filter { selected.contains($0.id) && $0.id != destination.id }
        guard !sources.isEmpty else {
            return
        }
        isWorking = true
        Task {
            do {
                var existing = Set(try await SpotifyWebAPI.entries(of: destination.id).map(\.track.uri))
                var toAdd: [String] = []
                for source in sources {
                    for entry in try await SpotifyWebAPI.entries(of: source.id) where entry.track.is_local != true {
                        if skipDuplicates && existing.contains(entry.track.uri) {
                            continue
                        }
                        existing.insert(entry.track.uri)
                        toAdd.append(entry.track.uri)
                    }
                }
                let uris = toAdd
                await MainActor.run {
                    isWorking = false
                    SPModAlertHelper.confirm([
                        SPModAlertStep(
                            title: "merge_playlists".localized,
                            message: "merge_preview".localizeWithFormat(uris.count, destination.name),
                            confirmTitle: "confirm".localized
                        )
                    ]) {
                        Task {
                            do {
                                try await SpotifyWebAPI.add(uris, to: destination.id)
                                QuickAddStore.remember(id: destination.id, name: destination.name)
                                ToastHelper.show("playlist_done".localized)
                            }
                            catch {
                                ToastHelper.show(error.localizedDescription)
                            }
                        }
                    }
                }
            }
            catch {
                await MainActor.run {
                    isWorking = false
                    ToastHelper.show(error.localizedDescription)
                }
            }
        }
    }

    var body: some View {
        List {
            Section(footer: Text("merge_description".localized)) {
                Toggle("merge_skip_duplicates".localized, isOn: $skipDuplicates)
                Button {
                    SPModSettingsNavigator.push(
                        SPModPlaylistPickerView(excluding: nil) { destination in
                            merge(into: destination)
                        },
                        title: "merge_destination".localized
                    )
                } label: {
                    if isWorking {
                        ProgressView()
                    }
                    else {
                        Text("merge_choose_destination".localizeWithFormat(selected.count))
                    }
                }
                .disabled(selected.isEmpty || isWorking)
            }

            Section(header: Text("merge_sources".localized)) {
                if model.isLoading {
                    ProgressView()
                }
                ForEach(model.playlists) { playlist in
                    Button {
                        if selected.contains(playlist.id) {
                            selected.remove(playlist.id)
                        }
                        else {
                            selected.insert(playlist.id)
                        }
                    } label: {
                        PlaylistRow(playlist: playlist, isSelected: selected.contains(playlist.id))
                    }
                }
            }

            NonIPadSpacerView()
        }
        .listStyle(GroupedListStyle())
        .onAppear {
            model.load()
        }
    }
}

struct SPModSmartShuffleSettingsView: View {
    @State private var options = UserDefaults.smartShuffleOptions

    var body: some View {
        List {
            Section(footer: Text(options.mode.detail)) {
                Picker("smart_shuffle_mode".localized, selection: $options.mode) {
                    ForEach(SmartShuffleMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(MenuPickerStyle())
            }

            Section(footer: Text("smart_shuffle_settings_description".localized)) {
                Stepper(
                    "smart_shuffle_artist_gap".localizeWithFormat(options.artistGap),
                    value: $options.artistGap,
                    in: 1...10
                )
                Picker("smart_shuffle_exclude_recent".localized, selection: $options.excludeRecentHours) {
                    Text("smart_shuffle_exclude_none".localized).tag(0)
                    Text("1 h").tag(1)
                    Text("6 h").tag(6)
                    Text("24 h").tag(24)
                    Text("72 h").tag(72)
                }
                .pickerStyle(MenuPickerStyle())
                VStack(alignment: .leading, spacing: 5) {
                    Text("smart_shuffle_randomness".localized)
                    Slider(value: $options.randomness, in: 0...1, step: 0.1)
                }
            }

            NonIPadSpacerView()
        }
        .listStyle(GroupedListStyle())
        .onChange(of: options) { value in
            UserDefaults.smartShuffleOptions = value
        }
    }
}
