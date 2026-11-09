import Foundation

// Persisted list of blocked artists and extraction of a track's artists from
// Spotify's own track metadata. Original implementation.
struct BlockedArtist: Codable, Hashable, Identifiable {
    let uri: String
    let name: String
    var id: String { uri }
}

enum ArtistBlockStore {
    private static let key = "spmodBlockedArtists"

    static var blocked: [BlockedArtist] {
        get {
            guard
                let data = UserDefaults.container.data(forKey: key),
                let list = try? JSONDecoder().decode([BlockedArtist].self, from: data)
            else {
                return []
            }
            return list
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.container.set(data, forKey: key)
            }
        }
    }

    static func isBlocked(_ uri: String) -> Bool {
        blocked.contains { $0.uri == uri }
    }

    static func block(_ artist: BlockedArtist) {
        guard !isBlocked(artist.uri) else { return }
        blocked = blocked + [artist]
    }

    static func unblock(_ uri: String) {
        blocked = blocked.filter { $0.uri != uri }
    }

    // Reads every credited artist off the track: the primary artist plus any
    // additional artist_uri:<n> / artist_name:<n> pairs Spotify stores in the
    // track metadata dictionary.
    static func artists(of track: SPTPlayerTrack) -> [BlockedArtist] {
        let metadata = track.metadata()
        var result: [BlockedArtist] = []

        func add(_ uri: String?, _ name: String?) {
            guard let uri = uri, uri.hasPrefix("spotify:artist:") else { return }
            guard !result.contains(where: { $0.uri == uri }) else { return }
            result.append(BlockedArtist(uri: uri, name: (name?.isEmpty == false ? name! : uri)))
        }

        add(metadata["artist_uri"], metadata["artist_name"] ?? track.artistName())

        var index = 1
        while index < 32 {
            guard let uri = metadata["artist_uri:\(index)"] else { break }
            add(uri, metadata["artist_name:\(index)"])
            index += 1
        }

        return result
    }
}

extension UserDefaults {
    static let artistBlockEnabledKey = "artistBlockEnabled"

    static var artistBlockEnabled: Bool {
        get { container.object(forKey: artistBlockEnabledKey) as? Bool ?? false }
        set { container.set(newValue, forKey: artistBlockEnabledKey) }
    }
}
