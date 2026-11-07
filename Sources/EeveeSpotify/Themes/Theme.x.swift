import Orion
import UIKit

struct ThemeGroup: HookGroup { }

enum ThemeEngine {
    private static let backgroundSources: [UInt32] = [0x000000, 0x121212, 0x101010]
    private static let surfaceSources: [UInt32] = [0x181818, 0x1A1A1A, 0x1F1F1F, 0x212121, 0x242424, 0x282828, 0x292929, 0x2A2A2A]
    private static let elevatedSources: [UInt32] = [0x2E2E2E, 0x333333]
    private static let accentSources: [UInt32] = [0x1ED760, 0x1DB954, 0x1FDF64, 0x1ED75F, 0x3BE477, 0x1CC458]

    private struct Palette {
        let background: UIColor
        let surface: UIColor
        let elevated: UIColor
        let accent: UIColor
        let isAccentOnly: Bool
    }

    private static let palette: Palette? = {
        let config = NightMode.effectiveThemeConfig
        let dimming = NightMode.accentDimming
        guard config.isEnabled || dimming > 0 else {
            return nil
        }
        let surface = UIColor(spmodHex: config.surfaceHex)
        return Palette(
            background: UIColor(spmodHex: config.backgroundHex),
            surface: surface,
            elevated: surface.spmodAdjusted(by: 0.06),
            accent: UIColor(spmodHex: config.accentHex).spmodDimmed(by: dimming),
            isAccentOnly: config.preset == .spotify
        )
    }()

    private static func variants(of sources: [UInt32]) -> [UInt32] {
        var result: [UInt32] = []
        for source in sources {
            let r = Int((source >> 16) & 0xFF), g = Int((source >> 8) & 0xFF), b = Int(source & 0xFF)
            for dr in -2...2 {
                for dg in -2...2 {
                    for db in -2...2 {
                        let nr = r + dr, ng = g + dg, nb = b + db
                        guard (0...255).contains(nr), (0...255).contains(ng), (0...255).contains(nb) else {
                            continue
                        }
                        result.append(UInt32(nr) << 16 | UInt32(ng) << 8 | UInt32(nb))
                    }
                }
            }
        }
        return result
    }

    private static let backgroundMap: [UInt32: UIColor] = {
        guard let palette = palette else {
            return [:]
        }
        var map: [UInt32: UIColor] = [:]
        if !palette.isAccentOnly {
            for key in variants(of: backgroundSources) { map[key] = palette.background }
            for key in variants(of: surfaceSources) { map[key] = palette.surface }
            for key in variants(of: elevatedSources) { map[key] = palette.elevated }
        }
        for key in variants(of: accentSources) { map[key] = palette.accent }
        return map
    }()

    private static let accentMap: [UInt32: UIColor] = {
        guard let palette = palette else {
            return [:]
        }
        var map: [UInt32: UIColor] = [:]
        for key in variants(of: accentSources) { map[key] = palette.accent }
        return map
    }()

    static var isActive: Bool {
        palette != nil
    }

    static var accentColor: UIColor? {
        palette?.accent
    }

    private static var suspendDepth = 0

    static func suspend() {
        suspendDepth += 1
    }

    static func resume() {
        if suspendDepth > 0 {
            suspendDepth -= 1
        }
    }

    static var isSuspended: Bool {
        suspendDepth > 0
    }

    private static func pack(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> UInt32? {
        guard r.isFinite, g.isFinite, b.isFinite else {
            return nil
        }
        let byte: (CGFloat) -> UInt32 = { UInt32((min(max($0, 0), 1) * 255).rounded()) }
        return byte(r) << 16 | byte(g) << 8 | byte(b)
    }

    private static func replacement(for color: UIColor?, in map: [UInt32: UIColor]) -> UIColor? {
        guard let color = color, !map.isEmpty else {
            return color
        }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard
            color.getRed(&r, green: &g, blue: &b, alpha: &a),
            a > 0.98,
            let key = pack(r, g, b),
            let target = map[key]
        else {
            return color
        }
        return target
    }

    static func background(_ color: UIColor?) -> UIColor? {
        isSuspended ? color : replacement(for: color, in: backgroundMap)
    }

    static func accent(_ color: UIColor?) -> UIColor? {
        isSuspended ? color : replacement(for: color, in: accentMap)
    }

    static func background(_ color: CGColor?) -> CGColor? {
        guard
            !isSuspended,
            let color = color,
            !backgroundMap.isEmpty,
            let components = color.components,
            color.alpha > 0.98
        else {
            return color
        }
        let key: UInt32?
        switch color.colorSpace?.model {
        case .some(.rgb) where components.count >= 3:
            key = pack(components[0], components[1], components[2])
        case .some(.monochrome) where components.count >= 1:
            key = pack(components[0], components[0], components[0])
        default:
            key = nil
        }
        guard let key = key, let target = backgroundMap[key] else {
            return color
        }
        return target.cgColor
    }
}

class UIViewThemeHook: ClassHook<UIView> {
    typealias Group = ThemeGroup

    func setBackgroundColor(_ color: UIColor?) {
        orig.setBackgroundColor(ThemeEngine.background(color))
    }

    func setTintColor(_ color: UIColor?) {
        orig.setTintColor(ThemeEngine.accent(color))
    }
}

class UILabelThemeHook: ClassHook<UILabel> {
    typealias Group = ThemeGroup

    func setTextColor(_ color: UIColor?) {
        orig.setTextColor(ThemeEngine.accent(color))
    }
}

class CALayerThemeHook: ClassHook<CALayer> {
    typealias Group = ThemeGroup

    func setBackgroundColor(_ color: CGColor?) {
        orig.setBackgroundColor(ThemeEngine.background(color))
    }
}
