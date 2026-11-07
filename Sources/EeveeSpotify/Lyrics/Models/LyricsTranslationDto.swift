import Foundation

struct LyricsTranslationDto: Codable {
    var languageCode: String
    var lines: [String]
}
