import SwiftUI
import UIKit

struct SPModPalette {
    static var accent: Color {
        Color(UIColor(spmodHex: UserDefaults.themeConfig.accentHex))
    }

    static let cardBackground = Color(white: 1.0, opacity: 0.06)
    static let cardStroke = Color(white: 1.0, opacity: 0.08)
    static let separator = Color(white: 1.0, opacity: 0.07)
    static let primaryText = Color.white
    static let secondaryText = Color(white: 0.64)
}

struct SPModIconTile: View {
    let systemName: String
    let color: Color
    var size: CGFloat = 30

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [color, color.opacity(0.78)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: systemName)
                    .font(.system(size: size * 0.52, weight: .semibold))
                    .foregroundColor(.white)
            )
    }
}

struct SPModNavRow: View {
    let title: String
    let subtitle: String?
    let icon: String
    let color: Color
    var showsDivider: Bool = true
    let action: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: 14) {
                    SPModIconTile(systemName: icon, color: color)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(SPModPalette.primaryText)

                        if let subtitle = subtitle {
                            Text(subtitle)
                                .font(.system(size: 13, weight: .regular))
                                .foregroundColor(SPModPalette.secondaryText)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color(white: 0.5))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .contentShape(Rectangle())
            }
            .buttonStyle(SPModRowButtonStyle())

            if showsDivider {
                Rectangle()
                    .fill(SPModPalette.separator)
                    .frame(height: 1)
                    .padding(.leading, 60)
            }
        }
    }
}

struct SPModRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color(white: 1.0, opacity: 0.06) : Color.clear)
    }
}

struct SPModCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(SPModPalette.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(SPModPalette.cardStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct SPModStatusChip: View {
    let title: String
    let active: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: active ? "checkmark.seal.fill" : "xmark.seal.fill")
                .font(.system(size: 12, weight: .bold))
            Text(title)
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(
            Capsule().fill(Color(white: 1.0, opacity: active ? 0.22 : 0.10))
        )
    }
}

struct SPModHeroHeader: View {
    let version: String
    let latestVersion: String?
    let premiumActive: Bool
    let adBlockActive: Bool
    let onContributors: () -> Void

    private var accent: Color { SPModPalette.accent }

    private var isUpdateAvailable: Bool {
        latestVersion != nil && latestVersion != version
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(Color(white: 1.0, opacity: 0.18))
                    .frame(width: 54, height: 54)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(.white)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text("SPMod")
                        .font(.system(size: 26, weight: .heavy))
                        .foregroundColor(.white)

                    Button(action: onContributors) {
                        Text("v\(version)")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color(white: 1.0, opacity: 0.85))
                    }
                }

                Spacer()
            }

            HStack(spacing: 10) {
                SPModStatusChip(title: "Premium", active: premiumActive)
                SPModStatusChip(title: "Ad-Block", active: adBlockActive)
            }

            if isUpdateAvailable {
                Link(destination: URL(string: "https://github.com/RK28A/SPMod/releases")!) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.circle.fill")
                        Text("update_available".localized)
                            .font(.system(size: 14, weight: .semibold))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(white: 1.0, opacity: 0.18))
                    )
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [accent, accent.opacity(0.55)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
    }
}
