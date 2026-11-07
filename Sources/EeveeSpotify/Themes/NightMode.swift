import UIKit

enum NightModeTrigger: Int, CaseIterable, Codable {
    case manual
    case schedule
    case system

    var title: String {
        switch self {
        case .manual: return "night_trigger_manual".localized
        case .schedule: return "night_trigger_schedule".localized
        case .system: return "night_trigger_system".localized
        }
    }
}

struct NightModeConfig: Codable, Hashable {
    var enabled: Bool
    var trigger: NightModeTrigger
    var startMinutes: Int
    var endMinutes: Int
    var preset: ThemePreset
    var accentDimming: Double
    var fasterAnimations: Bool

    static let `default` = NightModeConfig(
        enabled: false,
        trigger: .schedule,
        startMinutes: 22 * 60,
        endMinutes: 7 * 60,
        preset: .amoled,
        accentDimming: 0.3,
        fasterAnimations: false
    )
}

extension UserDefaults {
    @UserDefault(key: "nightModeConfig", defaultValue: NightModeConfig.default)
    static var nightModeConfig: NightModeConfig
}

enum NightMode {
    static func isActive(_ config: NightModeConfig = UserDefaults.nightModeConfig, at date: Date = Date()) -> Bool {
        guard config.enabled else {
            return false
        }
        switch config.trigger {
        case .manual:
            return true
        case .system:
            return UIScreen.main.traitCollection.userInterfaceStyle == .dark
        case .schedule:
            let components = Calendar.current.dateComponents([.hour, .minute], from: date)
            let minutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
            let start = config.startMinutes
            let end = config.endMinutes
            if start == end {
                return true
            }
            return start < end
                ? (minutes >= start && minutes < end)
                : (minutes >= start || minutes < end)
        }
    }

    static let isActiveAtLaunch: Bool = isActive()

    static var effectiveThemeConfig: ThemeConfig {
        var config = UserDefaults.themeConfig
        if isActiveAtLaunch {
            let night = UserDefaults.nightModeConfig
            if night.preset != .spotify {
                config.preset = night.preset
            }
        }
        return config
    }

    static var accentDimming: CGFloat {
        isActiveAtLaunch ? CGFloat(min(max(UserDefaults.nightModeConfig.accentDimming, 0), 0.8)) : 0
    }

    private static var observer: NSObjectProtocol?
    private static var notified = false

    static func start() {
        guard UserDefaults.nightModeConfig.enabled, observer == nil else {
            return
        }
        DispatchQueue.main.async {
            observer = NotificationCenter.default.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { _ in
                applyAnimationSpeed()
                checkTransition()
            }
            applyAnimationSpeed()
        }
    }

    private static func applyAnimationSpeed() {
        guard isActiveAtLaunch, UserDefaults.nightModeConfig.fasterAnimations else {
            return
        }
        WindowHelper.shared.window?.layer.speed = 1.6
    }

    private static func checkTransition() {
        guard !notified, isActive() != isActiveAtLaunch else {
            return
        }
        notified = true
        ToastHelper.show(isActive() ? "night_starting_toast".localized : "night_ending_toast".localized)
    }
}

extension UIColor {
    func spmodDimmed(by amount: CGFloat) -> UIColor {
        guard amount > 0 else {
            return self
        }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard getRed(&r, green: &g, blue: &b, alpha: &a) else {
            return self
        }
        let gray = (r + g + b) / 3 * 0.8
        let mix: (CGFloat) -> CGFloat = { min(max($0 * (1 - amount) + gray * amount, 0), 1) }
        return UIColor(red: mix(r), green: mix(g), blue: mix(b), alpha: a)
    }
}
