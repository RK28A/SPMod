import SwiftUI
import UIKit

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    var components: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0

        guard UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a) else {
            return (0, 0, 0, 0)
        }

        return (r, g, b, a)
    }

    func lighter(by amount: CGFloat = 0.2) -> Self { Self(UIColor(self).lighter(by: amount)) }
    func darker(by amount: CGFloat = 0.2) -> Self { Self(UIColor(self).darker(by: amount)) }

    var brightness: CGFloat {
        (
            components.red * 299
            + components.green * 587
            + components.blue * 114
        ) / 1000
    }

    func normalized(_ by: CGFloat) -> Color {
        brightness < 0.5
            ? self.lighter(by: max(by - brightness, 0))
            : self.darker(by: max(brightness - by, 0))
    }
    
    private static func byte(_ value: CGFloat) -> UInt32 {
        guard value.isFinite else { return 0 }
        return UInt32((min(max(value, 0), 1) * 255).rounded())
    }
    
    var hexString: String {
        let c = components
        return String(
            format: "%02X%02X%02X",
            Self.byte(c.red),
            Self.byte(c.green),
            Self.byte(c.blue)
        )
    }
    
    var uInt32: UInt32 {
        let c = components
        return Self.byte(c.alpha) << 24
            | Self.byte(c.red) << 16
            | Self.byte(c.green) << 8
            | Self.byte(c.blue)
    }
}

