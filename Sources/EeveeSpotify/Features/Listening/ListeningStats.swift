import Foundation

struct ListeningStats {
    let records: [PlayRecord]
    let interval: DateInterval

    init(all: [PlayRecord], interval: DateInterval) {
        self.interval = interval
        self.records = all.filter { interval.contains($0.start) || $0.start == interval.end }
    }

    var dayCount: Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: interval.start)
        let end = calendar.startOfDay(for: interval.end)
        let days = calendar.dateComponents([.day], from: start, to: end).day ?? 0
        return max(days + (interval.end > end ? 1 : 0), 1)
    }

    var summary: StatsSummary {
        var summary = StatsSummary()
        summary.listened = records.reduce(0) { $0 + $1.listened }
        summary.plays = records.count
        summary.completedPlays = records.filter(\.completed).count
        summary.uniqueTracks = Set(records.map(\.trackKey)).count
        summary.uniqueArtists = Set(records.map(\.artistKey).filter { !$0.isEmpty }).count
        summary.uniqueAlbums = Set(records.map(\.albumKey).filter { $0 != "|" }).count
        summary.averagePerDay = summary.listened / Double(dayCount)

        var sessions = 0
        var sessionTotal: TimeInterval = 0
        var lastEnd: Date? = nil
        for record in records.sorted(by: { $0.start < $1.start }) {
            if let end = lastEnd, record.start.timeIntervalSince(end) < 600 {
                sessionTotal += record.listened
            }
            else {
                sessions += 1
                sessionTotal += record.listened
            }
            lastEnd = record.end
        }
        summary.sessions = sessions
        summary.averageSession = sessions > 0 ? sessionTotal / Double(sessions) : 0
        return summary
    }

    func dailyTotals() -> [(date: Date, listened: TimeInterval)] {
        let calendar = Calendar.current
        var totals: [Date: TimeInterval] = [:]
        for record in records {
            totals[calendar.startOfDay(for: record.start), default: 0] += record.listened
        }
        var result: [(Date, TimeInterval)] = []
        var day = calendar.startOfDay(for: interval.start)
        var guardCount = 0
        while day < interval.end && guardCount < 3700 {
            result.append((day, totals[day] ?? 0))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else {
                break
            }
            day = next
            guardCount += 1
        }
        return result.map { (date: $0.0, listened: $0.1) }
    }

    func hourlyTotals() -> [TimeInterval] {
        let calendar = Calendar.current
        var totals = [TimeInterval](repeating: 0, count: 24)
        for record in records {
            let hour = calendar.component(.hour, from: record.start)
            if totals.indices.contains(hour) {
                totals[hour] += record.listened
            }
        }
        return totals
    }

    func ranking(_ kind: RankingKind, limit: Int) -> [RankingEntry] {
        let total = max(records.reduce(0) { $0 + $1.listened }, 1)
        let groups: [String: [PlayRecord]]
        switch kind {
        case .tracks: groups = Dictionary(grouping: records, by: \.trackKey)
        case .artists: groups = Dictionary(grouping: records.filter { !$0.artist.isEmpty }, by: \.artistKey)
        case .albums: groups = Dictionary(grouping: records.filter { !$0.album.isEmpty }, by: \.albumKey)
        }

        return groups.compactMap { key, plays -> RankingEntry? in
            guard let sample = plays.last else {
                return nil
            }
            let listened = plays.reduce(0) { $0 + $1.listened }
            let title: String
            let subtitle: String
            switch kind {
            case .tracks:
                title = sample.title
                subtitle = sample.artist
            case .artists:
                title = sample.artist
                subtitle = ""
            case .albums:
                title = sample.album
                subtitle = sample.artist
            }
            return RankingEntry(
                id: "\(kind.rawValue)|\(key)",
                kind: kind,
                title: title,
                subtitle: subtitle,
                artworkKey: ListeningStore.artworkKey(album: sample.album, artist: sample.artist),
                trackId: kind == .tracks ? sample.trackId : "",
                plays: plays.count,
                listened: listened,
                share: listened / total
            )
        }
        .sorted { $0.plays != $1.plays ? $0.plays > $1.plays : $0.listened > $1.listened }
        .prefix(limit)
        .map { $0 }
    }

    func records(for entry: RankingEntry) -> [PlayRecord] {
        let key = entry.id.components(separatedBy: "|").dropFirst().joined(separator: "|")
        switch entry.kind {
        case .tracks: return records.filter { $0.trackKey == key }
        case .artists: return records.filter { $0.artistKey == key }
        case .albums: return records.filter { $0.albumKey == key }
        }
    }

    var previousInterval: DateInterval {
        let length = interval.duration
        let start = interval.start.addingTimeInterval(-length)
        return DateInterval(start: start, end: interval.start)
    }

    static func change(current: Double, previous: Double) -> Double? {
        guard previous > 0 else {
            return nil
        }
        return (current - previous) / previous * 100
    }
}
