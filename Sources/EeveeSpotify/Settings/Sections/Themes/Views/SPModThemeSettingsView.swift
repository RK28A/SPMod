import SwiftUI
import UIKit

struct SPModThemeSettingsView: View {
    @State private var config = UserDefaults.themeConfig
    @State private var lyricsColors = UserDefaults.lyricsColors
    @State private var darkPopUps = UserDefaults.darkPopUps
    @State private var hasPendingChanges = false
    @State private var nightMode = UserDefaults.nightModeConfig
    @State private var hidePremiumUpsells = UserDefaults.hidePremiumUpsells
    @State private var presets = SPModPresetStore.presets
    
    private func timeBinding(_ keyPath: WritableKeyPath<NightModeConfig, Int>) -> Binding<Date> {
        Binding<Date>(
            get: {
                let minutes = nightMode[keyPath: keyPath]
                return Calendar.current.date(
                    bySettingHour: minutes / 60,
                    minute: minutes % 60,
                    second: 0,
                    of: Date()
                ) ?? Date()
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                nightMode[keyPath: keyPath] = (components.hour ?? 0) * 60 + (components.minute ?? 0)
            }
        )
    }
    
    @ViewBuilder private func nightModeSection() -> some View {
        Section(
            header: Text("night_mode".localized),
            footer: Text("night_mode_description".localized)
        ) {
            Toggle("night_mode_enabled".localized, isOn: $nightMode.enabled)
            
            if nightMode.enabled {
                Picker("night_mode_trigger".localized, selection: $nightMode.trigger) {
                    ForEach(NightModeTrigger.allCases, id: \.self) { trigger in
                        Text(trigger.title).tag(trigger)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                
                if nightMode.trigger == .schedule {
                    DatePicker("night_mode_start".localized, selection: timeBinding(\.startMinutes), displayedComponents: .hourAndMinute)
                    DatePicker("night_mode_end".localized, selection: timeBinding(\.endMinutes), displayedComponents: .hourAndMinute)
                }
                
                Picker("night_mode_theme".localized, selection: $nightMode.preset) {
                    ForEach(ThemePreset.allCases.filter { $0 != .spotify }, id: \.self) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                
                VStack(alignment: .leading, spacing: 5) {
                    Text("night_mode_accent_dimming".localized)
                    Slider(value: $nightMode.accentDimming, in: 0...0.7, step: 0.1)
                }
                
                Toggle("night_mode_faster_animations".localized, isOn: $nightMode.fasterAnimations)
            }
        }
    }

    private func color(_ hex: String) -> Color {
        Color(UIColor(spmodHex: hex))
    }

    private func promptSavePreset() {
        let alert = UIAlertController(
            title: "preset_save_title".localized,
            message: "preset_save_message".localized,
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.placeholder = "preset_name_placeholder".localized
        }
        alert.addAction(UIAlertAction(title: "cancel".localized, style: .cancel))
        alert.addAction(UIAlertAction(title: "save".localized, style: .default) { _ in
            let name = alert.textFields?.first?.text ?? ""
            SPModPresetStore.save(name: name, theme: config)
            presets = SPModPresetStore.presets
            ToastHelper.show("preset_saved".localized)
        })
        SPModAlertHelper.present(alert)
    }

    @ViewBuilder private func myPresetsSection() -> some View {
        Section(
            header: Text("my_presets".localized),
            footer: Text("my_presets_description".localized)
        ) {
            Button {
                promptSavePreset()
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("preset_save_current".localized)
                }
            }

            ForEach(presets) { preset in
                Button {
                    config = preset.theme
                    ToastHelper.show("preset_applied".localizeWithFormat(preset.name))
                } label: {
                    HStack(spacing: 12) {
                        HStack(spacing: -6) {
                            Circle().fill(color(preset.theme.backgroundHex))
                            Circle().fill(color(preset.theme.surfaceHex))
                            Circle().fill(color(preset.theme.accentHex))
                        }
                        .frame(width: 58, height: 22)

                        Text(preset.name).foregroundColor(.white)
                        Spacer()
                        Image(systemName: "arrow.down.circle")
                            .foregroundColor(color(config.accentHex))
                    }
                }
            }
            .onDelete { indexSet in
                for index in indexSet {
                    SPModPresetStore.delete(presets[index].id)
                }
                presets = SPModPresetStore.presets
            }
        }
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

            myPresetsSection()

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

            nightModeSection()
            
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
            
            Section(footer: Text("hide_premium_upsells_description".localized)) {
                Toggle("hide_premium_upsells".localized, isOn: $hidePremiumUpsells)
            }

            NonIPadSpacerView()
        }
        .listStyle(GroupedListStyle())
        .animation(.default, value: config)
        .animation(.default, value: lyricsColors)
        .animation(.default, value: hasPendingChanges)
        .animation(.default, value: presets)

        .onChange(of: config) { newConfig in
            UserDefaults.themeConfig = newConfig
            hasPendingChanges = true
        }
        .onChange(of: lyricsColors) { newColors in
            UserDefaults.lyricsColors = newColors
        }
        .onChange(of: nightMode) { value in
            UserDefaults.nightModeConfig = value
            hasPendingChanges = true
        }
        .animation(.default, value: nightMode)
        .onChange(of: hidePremiumUpsells) { value in
            UserDefaults.hidePremiumUpsells = value
            hasPendingChanges = true
        }
        .onChange(of: darkPopUps) { value in
            UserDefaults.darkPopUps = value
            hasPendingChanges = true
        }
    }
}
