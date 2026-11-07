import UIKit

enum ThemePreset: String, CaseIterable, Codable {
    case spotify
    case amoled
    case midnight
    case violet
    case forest
    case sunset
    case rose
    case custom

    var title: String {
        switch self {
        case .spotify: return "theme_spotify".localized
        case .amoled: return "AMOLED"
        case .midnight: return "theme_midnight".localized
        case .violet: return "theme_violet".localized
        case .forest: return "theme_forest".localized
        case .sunset: return "theme_sunset".localized
        case .rose: return "theme_rose".localized
        case .custom: return "theme_custom".localized
        }
    }

    var colors: (background: String, surface: String, accent: String) {
        switch self {
        case .spotify: return ("#121212", "#1F1F1F", "#1ED760")
        case .amoled: return ("#000000", "#0B0B0B", "#1ED760")
        case .midnight: return ("#0A0F1E", "#131B33", "#4C8DFF")
        case .violet: return ("#120A1C", "#1E1430", "#B57BFF")
        case .forest: return ("#08130D", "#112219", "#3DDC84")
        case .sunset: return ("#160D08", "#261710", "#FF8A4C")
        case .rose: return ("#170A10", "#28111C", "#FF5FA2")
        case .custom: return ("#121212", "#1F1F1F", "#1ED760")
        }
    }
}

struct ThemeConfig: Codable, Hashable {
    var preset: ThemePreset
    var customBackground: String
    var customSurface: String
    var customAccent: String
    var overrideAccent: Bool
    var accent: String

    static let `default` = ThemeConfig(
        preset: .spotify,
        customBackground: "#121212",
        customSurface: "#1F1F1F",
        customAccent: "#1ED760",
        overrideAccent: false,
        accent: "#1ED760"
    )

    var isEnabled: Bool {
        preset != .spotify || overrideAccent
    }

    var backgroundHex: String {
        preset == .custom ? customBackground : preset.colors.background
    }

    var surfaceHex: String {
        preset == .custom ? customSurface : preset.colors.surface
    }

    var accentHex: String {
        if overrideAccent {
            return accent
        }
        return preset == .custom ? customAccent : preset.colors.accent
    }
}

extension UIColor {
    convenience init(spmodHex hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        if cleaned.count != 6 {
            value = 0x121212
        }
        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    func spmodAdjusted(by amount: CGFloat) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard getRed(&r, green: &g, blue: &b, alpha: &a) else {
            return self
        }
        let clamp: (CGFloat) -> CGFloat = { min(max($0, 0), 1) }
        return UIColor(red: clamp(r + amount), green: clamp(g + amount), blue: clamp(b + amount), alpha: a)
    }
}
