import Foundation

enum LyricsTranslationMode: Int, CaseIterable, Codable {
    case bilingual
    case translationOnly

    var title: String {
        switch self {
        case .bilingual: return "translation_mode_bilingual".localized
        case .translationOnly: return "translation_mode_only".localized
        }
    }
}

struct TranslationLanguage: Hashable {
    let code: String
    let name: String

    static let all: [TranslationLanguage] = [
        TranslationLanguage(code: "fr", name: "Français"),
        TranslationLanguage(code: "en", name: "English"),
        TranslationLanguage(code: "es", name: "Español"),
        TranslationLanguage(code: "de", name: "Deutsch"),
        TranslationLanguage(code: "it", name: "Italiano"),
        TranslationLanguage(code: "pt", name: "Português"),
        TranslationLanguage(code: "nl", name: "Nederlands"),
        TranslationLanguage(code: "pl", name: "Polski"),
        TranslationLanguage(code: "tr", name: "Türkçe"),
        TranslationLanguage(code: "ru", name: "Русский"),
        TranslationLanguage(code: "uk", name: "Українська"),
        TranslationLanguage(code: "ar", name: "العربية"),
        TranslationLanguage(code: "ja", name: "日本語"),
        TranslationLanguage(code: "ko", name: "한국어"),
        TranslationLanguage(code: "zh-CN", name: "中文")
    ]
}

extension UserDefaults {
    static let lyricsTranslationEnabledKey = "lyricsTranslationEnabled"
    static let lyricsTranslationConsentKey = "lyricsTranslationConsent"
    static let lyricsTranslationTargetKey = "lyricsTranslationTarget"
    static let lyricsTranslationModeKey = "lyricsTranslationMode"

    static var lyricsTranslationEnabled: Bool {
        get { container.bool(forKey: lyricsTranslationEnabledKey) }
        set { container.set(newValue, forKey: lyricsTranslationEnabledKey) }
    }

    static var lyricsTranslationConsent: Bool {
        get { container.bool(forKey: lyricsTranslationConsentKey) }
        set { container.set(newValue, forKey: lyricsTranslationConsentKey) }
    }

    static var lyricsTranslationTarget: String {
        get {
            if let value = container.string(forKey: lyricsTranslationTargetKey), !value.isEmpty {
                return value
            }
            let language = Locale.current.languageCode ?? "fr"
            return TranslationLanguage.all.contains { $0.code == language } ? language : "fr"
        }
        set { container.set(newValue, forKey: lyricsTranslationTargetKey) }
    }

    static var lyricsTranslationMode: LyricsTranslationMode {
        get {
            (container.object(forKey: lyricsTranslationModeKey) as? Int).flatMap(LyricsTranslationMode.init(rawValue:)) ?? .bilingual
        }
        set { container.set(newValue.rawValue, forKey: lyricsTranslationModeKey) }
    }
}

enum LyricsTranslator {
    private static let endpoint = "https://translate.googleapis.com/translate_a/single"
    private static let maxCharacters = 4500

    static var isActive: Bool {
        UserDefaults.lyricsTranslationEnabled
            && (OnDeviceTranslation.isAvailable || UserDefaults.lyricsTranslationConsent)
    }

    static func apply(to dto: LyricsDto) -> LyricsDto {
        guard isActive, dto.translation == nil, !dto.lines.isEmpty else {
            return dto
        }

        var result = dto
        result.lines = dto.lines.sorted { ($0.offsetMs ?? 0) < ($1.offsetMs ?? 0) }

        let target = UserDefaults.lyricsTranslationTarget
        let originals = result.lines.map { $0.content.trimmingCharacters(in: .whitespaces) }
        var unique: [String] = []
        var seen = Set<String>()
        for line in originals where !line.isEmpty && line != "♪" && seen.insert(line).inserted {
            unique.append(line)
        }

        guard !unique.isEmpty, let translated = translate(unique, target: target) else {
            return dto
        }

        let translatedLines = originals.map { line -> String in
            line.isEmpty || line == "♪" ? line : (translated[line] ?? line)
        }

        switch UserDefaults.lyricsTranslationMode {
        case .bilingual:
            result.translation = LyricsTranslationDto(languageCode: target, lines: translatedLines)
        case .translationOnly:
            for index in result.lines.indices where translatedLines.indices.contains(index) {
                result.lines[index].content = translatedLines[index]
            }
        }
        return result
    }

    private static func chunks(_ lines: [String]) -> [[String]] {
        var result: [[String]] = []
        var current: [String] = []
        var length = 0
        for line in lines {
            if length + line.count + 1 > maxCharacters && !current.isEmpty {
                result.append(current)
                current = []
                length = 0
            }
            current.append(line)
            length += line.count + 1
        }
        if !current.isEmpty {
            result.append(current)
        }
        return result
    }

    private static func translate(_ lines: [String], target: String) -> [String: String]? {
        if OnDeviceTranslation.isAvailable,
           let local = OnDeviceTranslation.translate(lines, target: target),
           local.count == lines.count {
            return Dictionary(zip(lines, local), uniquingKeysWith: { first, _ in first })
        }
        
        guard UserDefaults.lyricsTranslationConsent else {
            return nil
        }
        
        var mapping: [String: String] = [:]
        for chunk in chunks(lines) {
            guard let translatedChunk = request(chunk, target: target), translatedChunk.count == chunk.count else {
                return nil
            }
            for (original, translation) in zip(chunk, translatedChunk) {
                mapping[original] = translation
            }
        }
        return mapping
    }

    private static func request(_ lines: [String], target: String) -> [String]? {
        guard var components = URLComponents(string: endpoint) else {
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: "client", value: "gtx"),
            URLQueryItem(name: "sl", value: "auto"),
            URLQueryItem(name: "tl", value: target),
            URLQueryItem(name: "dt", value: "t")
        ]
        guard let url = components.url else {
            return nil
        }

        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let text = lines.joined(separator: "\n")
        guard let encoded = text.addingPercentEncoding(withAllowedCharacters: allowed) else {
            return nil
        }

        var request = URLRequest(url: url, timeoutInterval: 8)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("q=\(encoded)".utf8)

        let semaphore = DispatchSemaphore(value: 0)
        var responseData: Data?
        URLSession.shared.dataTask(with: request) { data, response, _ in
            if (response as? HTTPURLResponse)?.statusCode == 200 {
                responseData = data
            }
            semaphore.signal()
        }.resume()

        guard semaphore.wait(timeout: .now() + 10) == .success, let data = responseData else {
            return nil
        }

        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [Any],
            let segments = root.first as? [Any]
        else {
            return nil
        }

        if root.count > 2, let detected = root[2] as? String, detected.lowercased().hasPrefix(String(target.lowercased().prefix(2))) {
            return nil
        }

        let joined = segments.compactMap { ($0 as? [Any])?.first as? String }.joined()
        let result = joined.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        return result.count == lines.count ? result : nil
    }
}
