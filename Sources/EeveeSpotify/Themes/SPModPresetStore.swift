import Foundation

// A named snapshot of a theme configuration the user can save and re-apply
// quickly. Persisted as JSON and included in the backup so presets survive a
// reinstall.
struct SPModThemePreset: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var theme: ThemeConfig

    init(name: String, theme: ThemeConfig) {
        self.id = UUID().uuidString
        self.name = name
        self.theme = theme
    }
}

enum SPModPresetStore {
    static let key = "spmodThemePresets"

    static var presets: [SPModThemePreset] {
        get {
            guard
                let data = UserDefaults.container.data(forKey: key),
                let list = try? JSONDecoder().decode([SPModThemePreset].self, from: data)
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

    static func save(name: String, theme: ThemeConfig) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? "Preset \(presets.count + 1)" : trimmed
        presets = presets + [SPModThemePreset(name: finalName, theme: theme)]
    }

    static func delete(_ id: String) {
        presets = presets.filter { $0.id != id }
    }
}
