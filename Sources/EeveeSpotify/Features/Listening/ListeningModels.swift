import Foundation

struct PlayRecord: Codable, Hashable, Identifiable {
    var id: UUID
    var trackId: String
    var title: String
    var artist: String
    var album: String
    var start: Date
    var listened: TimeInterval
    var duration: TimeInterval
    var completed: Bool

    var trackKey: String {
        trackId.isEmpty ? "\(title.lowercased())|\(artist.lowercased())|\(album.lowercased())" : trackId
    }

    var artistKey: String { artist.lowercased() }
    var albumKey: String { "\(album.lowercased())|\(artist.lowercased())" }
    var end: Date { start.addingTimeInterval(listened) }
}

enum StatsPeriod: String, CaseIterable, Identifiable {
    case today
    case yesterday
    case last7Days
    case last30Days
    case thisMonth
    case thisYear
    case allTime
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "period_today".localized
        case .yesterday: return "period_yesterday".localized
        case .last7Days: return "period_7_days".localized
        case .last30Days: return "period_30_days".localized
        case .thisMonth: return "period_month".localized
        case .thisYear: return "period_year".localized
        case .allTime: return "period_all".localized
        case .custom: return "period_custom".localized
        }
    }

    func interval(customStart: Date, customEnd: Date, firstRecord: Date?) -> DateInterval {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)

        switch self {
        case .today:
            return DateInterval(start: startOfToday, end: now)
        case .yesterday:
            let start = calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday
            return DateInterval(start: start, end: startOfToday)
        case .last7Days:
            let start = calendar.date(byAdding: .day, value: -6, to: startOfToday) ?? startOfToday
            return DateInterval(start: start, end: now)
        case .last30Days:
            let start = calendar.date(byAdding: .day, value: -29, to: startOfToday) ?? startOfToday
            return DateInterval(start: start, end: now)
        case .thisMonth:
            let start = calendar.dateInterval(of: .month, for: now)?.start ?? startOfToday
            return DateInterval(start: start, end: now)
        case .thisYear:
            let start = calendar.dateInterval(of: .year, for: now)?.start ?? startOfToday
            return DateInterval(start: start, end: now)
        case .allTime:
            let start = min(firstRecord.map { calendar.startOfDay(for: $0) } ?? startOfToday, startOfToday)
            return DateInterval(start: start, end: now)
        case .custom:
            let start = calendar.startOfDay(for: min(customStart, customEnd))
            let endDay = calendar.startOfDay(for: max(customStart, customEnd))
            let end = calendar.date(byAdding: .day, value: 1, to: endDay) ?? endDay
            return DateInterval(start: start, end: max(end, start))
        }
    }
}

enum RankingKind: String, CaseIterable, Identifiable {
    case tracks
    case artists
    case albums

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tracks: return "ranking_tracks".localized
        case .artists: return "ranking_artists".localized
        case .albums: return "ranking_albums".localized
        }
    }
}

struct RankingEntry: Identifiable, Hashable {
    var id: String
    var kind: RankingKind
    var title: String
    var subtitle: String
    var artworkKey: String
    var trackId: String
    var plays: Int
    var listened: TimeInterval
    var share: Double
}

struct StatsSummary {
    var listened: TimeInterval = 0
    var plays = 0
    var uniqueTracks = 0
    var uniqueArtists = 0
    var uniqueAlbums = 0
    var averagePerDay: TimeInterval = 0
    var sessions = 0
    var averageSession: TimeInterval = 0
    var completedPlays = 0
}

extension TimeInterval {
    var spmodDuration: String {
        let totalMinutes = Int((self / 60).rounded())
        if totalMinutes < 60 {
            return "\(totalMinutes) min"
        }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return minutes == 0 ? "\(hours) h" : "\(hours) h \(minutes) min"
    }

    var spmodClock: String {
        let seconds = max(Int(self.rounded()), 0)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
