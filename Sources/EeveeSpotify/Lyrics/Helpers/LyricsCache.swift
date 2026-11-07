import Foundation
import CommonCrypto

struct CachedLyrics: Codable {
    var dto: LyricsDto
    var source: Int
    var date: Date
}

enum LyricsCache {
    private static let maxEntries = 600
    private static let maxAge: TimeInterval = 60 * 60 * 24 * 30
    private static let queue = DispatchQueue(label: "spmod.lyrics.cache")

    private static var directory: URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        let url = caches.appendingPathComponent("SPMod/Lyrics", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func fileURL(for key: String) -> URL? {
        let data = Data(key.utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(buffer.count), &digest)
        }
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory?.appendingPathComponent("\(name).json")
    }

    static func key(trackId: String, sources: [LyricsSource], options: LyricsOptions) -> String? {
        guard !trackId.isEmpty, !trackId.isLocalTrackIdentifier else {
            return nil
        }
        return [
            trackId,
            sources.map { String($0.rawValue) }.joined(separator: ","),
            options.romanization ? "r1" : "r0",
            options.musixmatchLanguage
        ].joined(separator: "|")
    }

    static func load(_ key: String) -> CachedLyrics? {
        queue.sync {
            guard
                let url = fileURL(for: key),
                let data = try? Data(contentsOf: url),
                let cached = try? JSONDecoder().decode(CachedLyrics.self, from: data)
            else {
                return nil
            }
            if Date().timeIntervalSince(cached.date) > maxAge {
                try? FileManager.default.removeItem(at: url)
                return nil
            }
            return cached
        }
    }

    static func store(_ dto: LyricsDto, source: LyricsSource, for key: String) {
        let cached = CachedLyrics(dto: dto, source: source.rawValue, date: Date())
        queue.async {
            guard
                let url = fileURL(for: key),
                let data = try? JSONEncoder().encode(cached)
            else {
                return
            }
            try? data.write(to: url, options: .atomic)
            prune()
        }
    }

    private static func prune() {
        guard
            let directory = directory,
            let files = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey]
            ),
            files.count > maxEntries
        else {
            return
        }
        let sorted = files.sorted {
            let lhs = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhs = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lhs < rhs
        }
        for file in sorted.prefix(files.count - maxEntries) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    static func size() -> Int64 {
        queue.sync {
            guard
                let directory = directory,
                let files = try? FileManager.default.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: [.fileSizeKey]
                )
            else {
                return 0
            }
            return files.reduce(Int64(0)) { total, file in
                total + Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
        }
    }

    static func clear() {
        queue.sync {
            guard let directory = directory else {
                return
            }
            try? FileManager.default.removeItem(at: directory)
        }
    }
}
