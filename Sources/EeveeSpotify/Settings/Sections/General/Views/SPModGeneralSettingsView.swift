import SwiftUI

struct SPModGeneralSettingsView: View {
    @State private var language = UserDefaults.spmodLanguage
    @State private var playerLiquidGlass = UserDefaults.playerLiquidGlass
    @State private var glassOpacity = UserDefaults.glassOpacity

    var body: some View {
        List {
            Section(
                header: Text("interface".localized),
                footer: Text("player_liquid_glass_description".localized)
            ) {
                Toggle("player_liquid_glass".localized, isOn: $playerLiquidGlass)
                    .onChange(of: playerLiquidGlass) { newValue in
                        UserDefaults.playerLiquidGlass = newValue
                        SPModAlertHelper.askRestart()
                    }

                if playerLiquidGlass {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("glass_tint_opacity".localized)
                            Spacer()
                            Text("\(Int(glassOpacity * 100))%")
                                .foregroundColor(.gray)
                        }
                        Slider(value: $glassOpacity, in: 0.0...0.6, step: 0.02)
                            .onChange(of: glassOpacity) { newValue in
                                UserDefaults.glassOpacity = newValue
                            }
                    }
                }
            }

            Section(
                header: Text("language".localized),
                footer: Text("language_description".localized)
            ) {
                ForEach(SPModLanguage.allCases, id: \.self) { option in
                    Button {
                        guard option != language else {
                            return
                        }
                        language = option
                        UserDefaults.spmodLanguage = option
                        SPModAlertHelper.askRestart()
                    } label: {
                        HStack {
                            Text(option.title)
                                .foregroundColor(.white)
                            Spacer()
                            if option == language {
                                Image(systemName: "checkmark")
                                    .foregroundColor(EeveeSettingsView.spotifyAccentColor)
                            }
                        }
                    }
                }
            }

            Section {
                Button {
                    SPModSettingsNavigator.push(SPModDiagnosticsView(), title: "diagnostics".localized)
                } label: {
                    NavigationSectionView(
                        color: .gray,
                        title: "diagnostics".localized,
                        imageSystemName: "stethoscope"
                    )
                }
            }
            
            NonIPadSpacerView()
        }
        .listStyle(GroupedListStyle())
        .animation(.default, value: language)
    }
}
