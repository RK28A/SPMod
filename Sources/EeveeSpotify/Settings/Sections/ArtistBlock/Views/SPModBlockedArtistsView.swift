import SwiftUI

struct SPModBlockedArtistsView: View {
    @State private var enabled = UserDefaults.artistBlockEnabled
    @State private var blocked = ArtistBlockStore.blocked

    private func blockCurrent() {
        guard let track = statefulPlayer?.currentTrack() else {
            ToastHelper.show("artist_block_no_track".localized)
            return
        }
        let artists = ArtistBlockStore.artists(of: track)
        guard let artist = artists.first else {
            ToastHelper.show("artist_block_no_track".localized)
            return
        }
        ArtistBlockStore.block(artist)
        blocked = ArtistBlockStore.blocked
        ToastHelper.show("artist_block_added".localizeWithFormat(artist.name))
    }

    var body: some View {
        List {
            Section(footer: Text("artist_block_description".localized)) {
                Toggle("artist_block_enabled".localized, isOn: $enabled)
                    .onChange(of: enabled) { newValue in
                        UserDefaults.artistBlockEnabled = newValue
                        SPModAlertHelper.askRestart()
                    }
            }

            Section {
                Button {
                    blockCurrent()
                } label: {
                    HStack {
                        Image(systemName: "nosign")
                        Text("artist_block_add_current".localized)
                    }
                }
            }

            if blocked.isEmpty {
                Section {
                    Text("artist_block_empty".localized)
                        .foregroundColor(.gray)
                }
            } else {
                Section(header: Text("artist_block_list".localized)) {
                    ForEach(blocked) { artist in
                        Text(artist.name)
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            ArtistBlockStore.unblock(blocked[index].uri)
                        }
                        blocked = ArtistBlockStore.blocked
                    }
                }
            }

            NonIPadSpacerView()
        }
        .listStyle(GroupedListStyle())
        .animation(.default, value: blocked)
    }
}
