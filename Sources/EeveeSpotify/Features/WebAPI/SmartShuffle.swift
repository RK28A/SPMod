import Foundation

enum SmartShuffleMode: String, CaseIterable, Codable, Identifiable {
    case pure
    case noRepeat
    case variety
    case discovery
    case favorites

    var id: String { rawValue }

    var title: String { "shuffle_mode_\(rawValue)".localized }
    var detail: String { "shuffle_mode_\(rawValue)_description".localized }
}

struct SmartShuffleOptions: Codable, Hashable {
    var mode: SmartShuffleMode
    var artistGap: Int
    var excludeRecentHours: Int
    var randomness: Double

    static let `default` = SmartShuffleOptions(mode: .variety, artistGap: 3, excludeRecentHours: 0, randomness: 0.5)
}

extension UserDefaults {
    @UserDefault(key: "smartShuffleOptions", defaultValue: SmartShuffleOptions.default)
    static var smartShuffleOptions: SmartShuffleOptions

    @UserDefault(key: "smartShufflePlayed", defaultValue: [String: [String]]())
    static var smartShufflePlayed: [String: [String]]
}

enum SmartShuffle {
    static func order(_ tracks: [WebTrack], playlistId: String, options: SmartShuffleOptions) -> [WebTrack] {
        var pool = tracks.filter { $0.is_local != true }
        var seen = Set<String>()
        pool = pool.filter { seen.insert($0.uri).inserted }
        guard !pool.isEmpty else {
            return []
        }

        let records = ListeningStore.shared.allRecords()
        var playCounts: [String: Int] = [:]
        for record in records where !record.trackId.isEmpty {
            playCounts["spotify:track:\(record.trackId)", default: 0] += 1
        }

        if options.excludeRecentHours > 0 {
            let limit = Date().addingTimeInterval(-Double(options.excludeRecentHours) * 3600)
            let recent = Set(records.filter { $0.start >= limit && !$0.trackId.isEmpty }.map { "spotify:track:\($0.trackId)" })
            let filtered = pool.filter { !recent.contains($0.uri) }
            if filtered.count >= max(5, pool.count / 4) {
                pool = filtered
            }
        }

        switch options.mode {
        case .pure:
            return pool.shuffled()

        case .noRepeat:
            var played = Set(UserDefaults.smartShufflePlayed[playlistId] ?? [])
            var remaining = pool.filter { !played.contains($0.uri) }
            if remaining.isEmpty {
                played.removeAll()
                remaining = pool
            }
            let ordered = remaining.shuffled()
            var store = UserDefaults.smartShufflePlayed
            store[playlistId] = Array(played.union(ordered.prefix(50).map(\.uri)))
            UserDefaults.smartShufflePlayed = store
            return ordered + pool.filter { !remaining.contains($0) }.shuffled()

        case .variety:
            return spreadArtists(pool.shuffled(), gap: max(1, options.artistGap))

        case .discovery, .favorites:
            let maxCount = Double(max(1, playCounts.values.max() ?? 1))
            let weighted = pool.map { track -> (WebTrack, Double) in
                let normalized = Double(playCounts[track.uri] ?? 0) / maxCount
                let preference = options.mode == .discovery ? 1 - normalized : normalized
                let noise = Double.random(in: 0...1) * options.randomness
                return (track, preference * (1 - options.randomness) + noise)
            }
            let sorted = weighted.sorted { $0.1 > $1.1 }.map(\.0)
            return spreadArtists(sorted, gap: max(1, options.artistGap / 2))
        }
    }

    static func spreadArtists(_ tracks: [WebTrack], gap: Int) -> [WebTrack] {
        var remaining = tracks
        var result: [WebTrack] = []
        result.reserveCapacity(tracks.count)

        while !remaining.isEmpty {
            let recent = Set(result.suffix(gap).map { $0.primaryArtist.lowercased() })
            if let index = remaining.firstIndex(where: { !recent.contains($0.primaryArtist.lowercased()) }) {
                result.append(remaining.remove(at: index))
            }
            else {
                result.append(remaining.removeFirst())
            }
        }
        return result
    }

    static func play(_ tracks: [WebTrack], playlistId: String) async throws -> Int {
        let ordered = order(tracks, playlistId: playlistId, options: UserDefaults.smartShuffleOptions)
        try await SpotifyWebAPI.play(ordered.map(\.uri))
        return ordered.count
    }
}

enum QuickAddStore {
    private static let lastKey = "quickAddLastPlaylist"
    private static let pinnedKey = "quickAddPinnedPlaylist"
    private static let allowDuplicatesKey = "quickAddAllowDuplicates"

    struct Target: Codable, Hashable {
        var id: String
        var name: String
    }

    private static func load(_ key: String) -> Target? {
        guard let data = UserDefaults.container.data(forKey: key) else {
            return nil
        }
        return try? JSONDecoder().decode(Target.self, from: data)
    }

    private static func save(_ target: Target?, _ key: String) {
        if let target = target, let data = try? JSONEncoder().encode(target) {
            UserDefaults.container.set(data, forKey: key)
        }
        else {
            UserDefaults.container.removeObject(forKey: key)
        }
    }

    static var last: Target? {
        get { load(lastKey) }
        set { save(newValue, lastKey) }
    }

    static var pinned: Target? {
        get { load(pinnedKey) }
        set { save(newValue, pinnedKey) }
    }

    static var allowDuplicates: Bool {
        get { UserDefaults.container.bool(forKey: allowDuplicatesKey) }
        set { UserDefaults.container.set(newValue, forKey: allowDuplicatesKey) }
    }

    static var destination: Target? {
        pinned ?? last
    }

    static func remember(id: String, name: String) {
        last = Target(id: id, name: name)
    }

    static func currentTrackURI() -> String? {
        guard let track = statefulPlayer?.currentTrack() else {
            return nil
        }
        let id = track.trackIdentifier.replacingOccurrences(of: "spotify:track:", with: "")
        guard !id.isEmpty, !id.contains(":") else {
            return nil
        }
        return "spotify:track:\(id)"
    }

    static func addCurrentTrack() {
        guard let uri = currentTrackURI() else {
            ToastHelper.show("copy_no_track".localized)
            return
        }
        guard let destination = destination else {
            ToastHelper.show("quick_add_no_destination".localized)
            return
        }

        Task {
            do {
                if !allowDuplicates {
                    let existing = try await SpotifyWebAPI.entries(of: destination.id)
                    if existing.contains(where: { $0.track.uri == uri }) {
                        ToastHelper.show("quick_add_already".localizeWithFormat(destination.name))
                        return
                    }
                }
                try await SpotifyWebAPI.add([uri], to: destination.id)
                ToastHelper.show("quick_add_done".localizeWithFormat(destination.name))
            }
            catch WebAPIError.http(let code, _) where code == 403 || code == 404 {
                if pinned?.id == destination.id {
                    pinned = nil
                }
                else {
                    last = nil
                }
                ToastHelper.show("quick_add_unavailable".localized)
            }
            catch {
                ToastHelper.show(error.localizedDescription)
            }
        }
    }
}
