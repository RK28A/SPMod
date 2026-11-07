import SwiftUI
import UIKit

struct SPModThemeSettingsView: View {
    @State private var config = UserDefaults.themeConfig
    @State private var lyricsColors = UserDefaults.lyricsColors
    @State private var darkPopUps = UserDefaults.darkPopUps
    @State private var hasPendingChanges = false

    private func color(_ hex: String) -> Color {
        Color(UIColor(spmodHex: hex))
    }

    private func hexBinding(_ keyPath: WritableKeyPath<ThemeConfig, String>) -> Binding<Color> {
        Binding<Color>(
            get: { color(config[keyPath: keyPath]) },
            set: { config[keyPath: keyPath] = "#\($0.hexString)" }
        )
    }

    @ViewBuilder private func preview() -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(color(config.backgroundHex))

            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(color(config.surfaceHex))
                    .frame(width: 54, height: 54)

                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white)
                        .frame(width: 110, height: 9)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.5))
                        .frame(width: 70, height: 8)
                }

                Spacer()

                ZStack {
                    Circle()
                        .fill(color(config.accentHex))
                        .frame(width: 42, height: 42)
                    Image(systemName: "play.fill")
                        .foregroundColor(.black)
                }
            }
            .padding(14)
        }
        .frame(height: 82)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
    }

    @ViewBuilder private func presetRow(_ preset: ThemePreset) -> some View {
        Button {
            config.preset = preset
        } label: {
            HStack(spacing: 12) {
                HStack(spacing: -6) {
                    Circle().fill(color(preset.colors.background))
                    Circle().fill(color(preset.colors.surface))
                    Circle().fill(color(preset.colors.accent))
                }
                .frame(width: 58, height: 22)
                .overlay(
                    Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1)
                        .frame(width: 66, height: 26)
                )

                Text(preset.title)
                    .foregroundColor(.white)

                Spacer()

                if config.preset == preset {
                    Image(systemName: "checkmark")
                        .foregroundColor(color(config.accentHex))
                }
            }
        }
    }

    var body: some View {
        List {
            Section(header: Text("theme_preview".localized)) {
                preview()
            }

            Section(
                header: Text("theme_presets".localized),
                footer: Text("theme_presets_description".localized)
            ) {
                ForEach(ThemePreset.allCases, id: \.self) { preset in
                    presetRow(preset)
                }
            }

            if config.preset == .custom {
                Section(header: Text("theme_custom_colors".localized)) {
                    ColorPicker("theme_background".localized, selection: hexBinding(\.customBackground), supportsOpacity: false)
                    ColorPicker("theme_surface".localized, selection: hexBinding(\.customSurface), supportsOpacity: false)
                    ColorPicker("theme_accent".localized, selection: hexBinding(\.customAccent), supportsOpacity: false)
                }
            }

            Section(footer: Text("accent_color_description".localized)) {
                Toggle("custom_accent_color".localized, isOn: $config.overrideAccent)

                if config.overrideAccent {
                    ColorPicker("accent_color".localized, selection: hexBinding(\.accent), supportsOpacity: false)
                }
            }

            if hasPendingChanges {
                Section(footer: Text("restart_is_required_description".localized)) {
                    Button("restart_now".localized) {
                        exitApplication()
                    }
                }
            }

            if UserDefaults.lyricsSource.isReplacingLyrics {
                Section(
                    header: Text("lyrics_background_color_section".localized),
                    footer: Text("lyrics_background_color_section_description".localized)
                ) {
                    Toggle(
                        "display_original_colors".localized,
                        isOn: $lyricsColors.displayOriginalColors
                    )

                    Toggle(
                        "use_static_color".localized,
                        isOn: $lyricsColors.useStaticColor
                    )

                    if lyricsColors.useStaticColor {
                        ColorPicker(
                            "static_color".localized,
                            selection: Binding<Color>(
                                get: { Color(hex: lyricsColors.staticColor) },
                                set: { lyricsColors.staticColor = $0.hexString }
                            ),
                            supportsOpacity: false
                        )
                    }
                    else {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("color_normalization_factor".localized)

                            Slider(
                                value: $lyricsColors.normalizationFactor,
                                in: 0.2...0.8,
                                step: 0.1
                            )
                        }
                    }
                }
            }

            Section(footer: Text("restart_is_required_description".localized)) {
                Toggle("dark_popups".localized, isOn: $darkPopUps)
            }

            NonIPadSpacerView()
        }
        .listStyle(GroupedListStyle())
        .animation(.default, value: config)
        .animation(.default, value: lyricsColors)
        .animation(.default, value: hasPendingChanges)

        .onChange(of: config) { newConfig in
            UserDefaults.themeConfig = newConfig
            hasPendingChanges = true
        }
        .onChange(of: lyricsColors) { newColors in
            UserDefaults.lyricsColors = newColors
        }
        .onChange(of: darkPopUps) { value in
            UserDefaults.darkPopUps = value
            hasPendingChanges = true
        }
    }
}
