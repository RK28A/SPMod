import Foundation

// Original implementation against NetEase Cloud Music's public web API
// (music.163.com). Search returns song ids; the lyric endpoint returns an
// LRC document that is parsed into timed lines. No third-party code is used.
class NetEaseLyricsRepository: LyricsRepository {
    static let shared = NetEaseLyricsRepository()

    private let session: URLSession
    private let baseUrl = "https://music.163.com"

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15",
            "Referer": "https://music.163.com",
            "Cookie": "os=pc; appver=2.9.7"
        ]
        session = URLSession(configuration: configuration)
    }

    private struct SearchResponse: Decodable {
        struct Result: Decodable {
            struct Song: Decodable {
                struct Artist: Decodable { let name: String? }
                let id: Int
                let name: String?
                let artists: [Artist]?
                let duration: Int?
            }
            let songs: [Song]?
        }
        let result: Result?
    }

    private struct LyricResponse: Decodable {
        struct Lyric: Decodable { let lyric: String? }
        let lrc: Lyric?
        let klyric: Lyric?
        let tlyric: Lyric?
    }

    private func perform(_ path: String, query: [String: Any]) throws -> Data {
        var stringUrl = "\(baseUrl)\(path)"
        if !query.isEmpty {
            stringUrl += "?\(query.queryString)"
        }
        guard let url = URL(string: stringUrl) else {
            throw LyricsError.unknownError
        }

        let semaphore = DispatchSemaphore(value: 0)
        var data: Data?
        var error: Error?

        let task = session.dataTask(with: URLRequest(url: url)) { response, _, err in
            data = response
            error = err
            semaphore.signal()
        }
        task.resume()
        semaphore.wait()

        if let error = error {
            throw error
        }
        guard let data = data else {
            throw LyricsError.decodingError
        }
        return data
    }

    private func findSongId(title: String, artist: String) throws -> Int {
        let keyword = "\(title) \(artist)".trimmingCharacters(in: .whitespacesAndNewlines)
        let data = try perform("/api/search/get/web", query: [
            "s": keyword,
            "type": 1,
            "offset": 0,
            "limit": 5
        ])

        guard
            let response = try? JSONDecoder().decode(SearchResponse.self, from: data),
            let songs = response.result?.songs,
            let first = songs.first
        else {
            throw LyricsError.noSuchSong
        }
        return first.id
    }

    private func parseLrc(_ lrc: String) -> [LyricsLineDto] {
        lrc.components(separatedBy: "\n").compactMap { line in
            guard let match = line.firstMatch(
                "\\[(?<minute>\\d+):(?<seconds>\\d+\\.\\d+|\\d+)\\] ?(?<content>.*)"
            ) else {
                return nil
            }

            var captures: [String: String] = [:]
            for name in ["minute", "seconds", "content"] {
                let range = match.range(withName: name)
                if let substringRange = Range(range, in: line) {
                    captures[name] = String(line[substringRange])
                }
            }

            guard let seconds = captures["seconds"].flatMap(Float.init) else {
                return nil
            }
            let minute = captures["minute"].flatMap { Int($0) } ?? 0
            let content = (captures["content"] ?? "").trimmingCharacters(in: .whitespaces)

            return LyricsLineDto(
                content: content.lyricsNoteIfEmpty,
                offsetMs: Int(minute * 60 * 1000 + Int(seconds * 1000))
            )
        }
    }

    func getLyrics(_ query: LyricsSearchQuery, options: LyricsOptions) throws -> LyricsDto {
        let songId: Int
        do {
            songId = try findSongId(title: query.title, artist: query.primaryArtist)
        } catch {
            songId = try findSongId(
                title: query.title.strippedTrackTitle,
                artist: query.primaryArtist
            )
        }

        let data = try perform("/api/song/lyric", query: [
            "id": songId,
            "lv": 1,
            "kv": 1,
            "tv": -1
        ])

        guard let response = try? JSONDecoder().decode(LyricResponse.self, from: data) else {
            throw LyricsError.decodingError
        }

        guard let rawLrc = response.lrc?.lyric, !rawLrc.isEmpty else {
            throw LyricsError.noSuchSong
        }

        let lines = parseLrc(rawLrc)

        if lines.isEmpty {
            // Pure-text fallback (no timestamps): keep only the words.
            let plain = rawLrc
                .components(separatedBy: "\n")
                .map { $0.replacingOccurrences(of: "\\[.*?\\]", with: "", options: .regularExpression) }
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

            guard !plain.isEmpty else {
                throw LyricsError.noSuchSong
            }

            return LyricsDto(
                lines: plain.map { LyricsLineDto(content: $0) },
                timeSynced: false,
                romanization: plain.canBeRomanized ? .canBeRomanized : .original
            )
        }

        let contents = lines.map(\.content)
        return LyricsDto(
            lines: lines,
            timeSynced: true,
            romanization: contents.canBeRomanized ? .canBeRomanized : .original
        )
    }
}
