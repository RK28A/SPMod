import Foundation
import UIKit

enum WebAPIError: LocalizedError {
    case noToken
    case http(Int, String)
    case decoding
    case noDevice

    var errorDescription: String? {
        switch self {
        case .noToken: return "webapi_error_no_token".localized
        case .http(let code, let message): return "HTTP \(code) \(message)"
        case .decoding: return "webapi_error_decoding".localized
        case .noDevice: return "webapi_error_no_device".localized
        }
    }
}

struct WebImage: Codable, Hashable {
    var url: String
}

struct WebUser: Codable, Hashable {
    var id: String
    var display_name: String?
}

struct WebArtist: Codable, Hashable {
    var id: String?
    var name: String
}

struct WebAlbum: Codable, Hashable {
    var id: String?
    var name: String
    var release_date: String?
    var images: [WebImage]?
}

struct WebTrack: Codable, Hashable {
    var id: String?
    var uri: String
    var name: String
    var duration_ms: Int?
    var album: WebAlbum?
    var artists: [WebArtist]?
    var is_local: Bool?

    var artistNames: String {
        (artists ?? []).map(\.name).joined(separator: ", ")
    }

    var primaryArtist: String {
        artists?.first?.name ?? ""
    }

    var releaseYear: Int {
        Int((album?.release_date ?? "").prefix(4)) ?? 0
    }
}

struct WebPlaylistItem: Codable, Hashable {
    var added_at: String?
    var track: WebTrack?
}

struct WebPlaylistTracksRef: Codable, Hashable {
    var total: Int?
}

struct WebPlaylist: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var owner: WebUser?
    var collaborative: Bool?
    var images: [WebImage]?
    var tracks: WebPlaylistTracksRef?
    var snapshot_id: String?

    var uri: String { "spotify:playlist:\(id)" }
}

struct WebPaging<Item: Codable>: Codable {
    var items: [Item]
    var next: String?
}

struct WebDevice: Codable, Hashable {
    var id: String?
    var name: String
    var type: String
    var is_active: Bool
}

struct WebDevices: Codable {
    var devices: [WebDevice]
}

struct PlaylistEntry: Identifiable, Hashable {
    var id: String { "\(position)-\(track.uri)" }
    var position: Int
    var track: WebTrack
    var addedAt: Date?
}

enum SpotifyWebAPI {
    private static let lock = NSLock()
    private static var token: String?
    private static var tokenDate = Date.distantPast
    private static var cachedUserId: String?
    private static let base = "https://api.spotify.com/v1"

    static var hasToken: Bool {
        lock.lock()
        defer { lock.unlock() }
        return token != nil && Date().timeIntervalSince(tokenDate) < 3300
    }

    static func capture(from request: URLRequest?) {
        guard
            let request = request,
            let host = request.url?.host,
            host.hasSuffix("spotify.com"),
            let header = request.value(forHTTPHeaderField: "Authorization"),
            header.hasPrefix("Bearer ")
        else {
            return
        }
        let value = String(header.dropFirst(7))
        lock.lock()
        if value != token {
            token = value
        }
        tokenDate = Date()
        lock.unlock()
    }

    private static func currentToken() throws -> String {
        lock.lock()
        defer { lock.unlock() }
        guard let token = token else {
            throw WebAPIError.noToken
        }
        return token
    }

    private static func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let http = response as? HTTPURLResponse else {
                    continuation.resume(throwing: WebAPIError.decoding)
                    return
                }
                continuation.resume(returning: (data ?? Data(), http))
            }.resume()
        }
    }

    @discardableResult
    static func call(
        _ method: String,
        _ pathOrURL: String,
        body: [String: Any]? = nil,
        query: [String: String] = [:]
    ) async throws -> Data {
        var components = URLComponents(string: pathOrURL.hasPrefix("http") ? pathOrURL : base + pathOrURL)
        if !query.isEmpty {
            let existing = components?.queryItems ?? []
            components?.queryItems = existing + query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components?.url else {
            throw WebAPIError.decoding
        }

        for attempt in 0..<3 {
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.timeoutInterval = 20
            request.setValue("Bearer \(try currentToken())", forHTTPHeaderField: "Authorization")
            if let body = body {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
            }

            let (data, response) = try await send(request)

            if response.statusCode == 429, attempt < 2 {
                let wait = Double(response.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 2
                try await Task.sleep(nanoseconds: UInt64(min(wait, 10) * 1_000_000_000))
                continue
            }

            guard (200..<300).contains(response.statusCode) else {
                var message = ""
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = json["error"] as? [String: Any] {
                    message = error["message"] as? String ?? ""
                }
                throw WebAPIError.http(response.statusCode, message)
            }
            return data
        }
        throw WebAPIError.http(429, "")
    }

    static func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        }
        catch {
            throw WebAPIError.decoding
        }
    }

    static func userId() async throws -> String {
        if let cached = cachedUserId {
            return cached
        }
        let me = try decode(WebUser.self, try await call("GET", "/me"))
        cachedUserId = me.id
        return me.id
    }

    static func myPlaylists() async throws -> [WebPlaylist] {
        var result: [WebPlaylist] = []
        var next: String? = base + "/me/playlists?limit=50"
        while let url = next, result.count < 2000 {
            let page = try decode(WebPaging<WebPlaylist?>.self, try await call("GET", url))
            result.append(contentsOf: page.items.compactMap { $0 })
            next = page.next
        }
        return result
    }

    static func editablePlaylists() async throws -> [WebPlaylist] {
        let me = try await userId()
        return try await myPlaylists().filter { $0.owner?.id == me || $0.collaborative == true }
    }

    static func entries(of playlistId: String) async throws -> [PlaylistEntry] {
        let formatter = ISO8601DateFormatter()
        var result: [PlaylistEntry] = []
        var next: String? = base + "/playlists/\(playlistId)/tracks?limit=100&additional_types=track"
        while let url = next, result.count < 11000 {
            let page = try decode(WebPaging<WebPlaylistItem>.self, try await call("GET", url))
            for item in page.items {
                guard let track = item.track else {
                    continue
                }
                result.append(PlaylistEntry(
                    position: result.count,
                    track: track,
                    addedAt: item.added_at.flatMap { formatter.date(from: $0) }
                ))
            }
            next = page.next
        }
        for index in result.indices {
            result[index].position = index
        }
        return result
    }

    static func add(_ uris: [String], to playlistId: String) async throws {
        for chunk in uris.chunked(100) {
            try await call("POST", "/playlists/\(playlistId)/tracks", body: ["uris": chunk])
        }
    }

    static func remove(_ entries: [PlaylistEntry], from playlistId: String) async throws {
        var grouped: [String: [Int]] = [:]
        for entry in entries {
            grouped[entry.track.uri, default: []].append(entry.position)
        }
        let items = grouped.map { ["uri": $0.key, "positions": $0.value] as [String: Any] }
        var snapshot: String? = nil
        for chunk in items.chunked(100) {
            var body: [String: Any] = ["tracks": chunk]
            if let snapshot = snapshot {
                body["snapshot_id"] = snapshot
            }
            let data = try await call("DELETE", "/playlists/\(playlistId)/tracks", body: body)
            snapshot = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["snapshot_id"] as? String
        }
    }

    static func replaceAll(_ uris: [String], in playlistId: String) async throws {
        let chunks = uris.chunked(100)
        try await call("PUT", "/playlists/\(playlistId)/tracks", body: ["uris": chunks.first ?? []])
        for chunk in chunks.dropFirst() {
            try await call("POST", "/playlists/\(playlistId)/tracks", body: ["uris": chunk])
        }
    }

    static func createPlaylist(named name: String, uris: [String]) async throws -> WebPlaylist {
        let me = try await userId()
        let data = try await call("POST", "/users/\(me)/playlists", body: ["name": name, "public": false])
        let playlist = try decode(WebPlaylist.self, data)
        if !uris.isEmpty {
            try await add(uris, to: playlist.id)
        }
        return playlist
    }

    static func thisDeviceId() async throws -> String {
        let devices = try decode(WebDevices.self, try await call("GET", "/me/player/devices")).devices
        let localName = UIDevice.current.name.lowercased()
        let candidates = devices.filter { $0.id != nil }
        if let match = candidates.first(where: { $0.type.lowercased() == "smartphone" && $0.name.lowercased() == localName }) {
            return match.id!
        }
        if let active = candidates.first(where: { $0.is_active && $0.type.lowercased() == "smartphone" }) {
            return active.id!
        }
        if let phone = candidates.first(where: { $0.type.lowercased() == "smartphone" }) {
            return phone.id!
        }
        throw WebAPIError.noDevice
    }

    static func play(_ uris: [String]) async throws {
        let device = try await thisDeviceId()
        try await call(
            "PUT",
            "/me/player/play",
            body: ["uris": Array(uris.prefix(700))],
            query: ["device_id": device]
        )
        try? await call("PUT", "/me/player/shuffle", query: ["state": "false", "device_id": device])
    }
}

extension Array {
    func chunked(_ size: Int) -> [[Element]] {
        guard size > 0, !isEmpty else {
            return isEmpty ? [] : [self]
        }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
