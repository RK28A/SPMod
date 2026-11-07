import SwiftUI
import UIKit

struct EeveeSettingsView: View {
    let navigationController: UINavigationController
    static var spotifyAccentColor: Color {
        Color(UIColor(spmodHex: UserDefaults.themeConfig.accentHex))
    }

    @State private var hasShownCommonIssuesTip = UserDefaults.hasShownCommonIssuesTip
    @State private var isClearingData = false

    private func pushSettingsController(with view: any View, title: String) {
        let viewController = EeveeSettingsViewController(
            navigationController.view.frame,
            settingsView: AnyView(view),
            navigationTitle: title
        )
        navigationController.pushViewController(viewController, animated: true)
    }

    init(navigationController: UINavigationController) {
        self.navigationController = navigationController
        UIView.appearance().tintColor = UIColor(EeveeSettingsView.spotifyAccentColor)
    }

    @ViewBuilder private func navigationRow(
        _ titleKey: String,
        icon: String,
        color: Color,
        subtitle: String? = nil,
        view: @escaping () -> any View
    ) -> some View {
        Button {
            pushSettingsController(with: view(), title: titleKey.localized)
        } label: {
            NavigationSectionView(
                color: color,
                title: titleKey.localized,
                imageSystemName: icon,
                subtitle: subtitle?.localized
            )
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func resetData() {
        SPModAlertHelper.confirm([
            SPModAlertStep(
                title: "reset_confirm_title_1".localized,
                message: "reset_confirm_message_1".localized,
                confirmTitle: "reset_confirm_button_1".localized
            ),
            SPModAlertStep(
                title: "reset_confirm_title_2".localized,
                message: "reset_confirm_message_2".localized,
                confirmTitle: "reset_confirm_button_2".localized
            ),
            SPModAlertStep(
                title: "reset_confirm_title_3".localized,
                message: "reset_confirm_message_3".localized,
                confirmTitle: "reset_data".localized,
                isDestructive: true
            )
        ]) {
            isClearingData = true

            DispatchQueue.global(qos: .userInitiated).async {
                LyricsCache.clear()
                OfflineHelper.resetData(clearCaches: true)

                DispatchQueue.main.async {
                    exitApplication()
                }
            }
        }
    }

    var body: some View {
        List {
            EeveeSettingsVersionView()
                .listRowBackground(Color.clear)

            if !hasShownCommonIssuesTip {
                CommonIssuesTipView(
                    onDismiss: {
                        hasShownCommonIssuesTip = true
                        UserDefaults.hasShownCommonIssuesTip = true
                    }
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            Section {
                navigationRow("general", icon: "gearshape.fill", color: .gray, subtitle: "general_subtitle") {
                    SPModGeneralSettingsView()
                }
            }

            Section {
                navigationRow("lyrics", icon: "quote.bubble", color: .blue, subtitle: "lyrics_subtitle") {
                    EeveeLyricsSettingsView()
                }
                navigationRow("playback", icon: "play.circle", color: .green, subtitle: "playback_subtitle") {
                    SPModPlaybackSettingsView()
                }
                navigationRow("listening", icon: "chart.bar", color: Color(hex: "#FF9F0A"), subtitle: "listening_subtitle") {
                    SPModListeningSettingsView()
                }
                navigationRow("playlists", icon: "music.note.list", color: Color(hex: "#30D158"), subtitle: "playlists_subtitle") {
                    SPModPlaylistsView()
                }
            }

            Section {
                navigationRow("themes", icon: "paintbrush", color: Color(hex: "#FF5FA2"), subtitle: "themes_subtitle") {
                    SPModThemeSettingsView()
                }
            }

            Section {
                navigationRow("privacy", icon: "hand.raised", color: Color(hex: "#5E5CE6"), subtitle: "privacy_subtitle") {
                    SPModPrivacySettingsView()
                }
                navigationRow("backup", icon: "externaldrive", color: Color(hex: "#64D2FF"), subtitle: "backup_subtitle") {
                    SPModBackupSettingsView()
                }
                navigationRow("experiments", icon: "sparkles", color: .purple, subtitle: "experiments_subtitle") {
                    EeveeExperimentsSettingsView()
                }
            }

            Section(footer: Text("reset_data_description".localized)) {
                Button {
                    resetData()
                } label: {
                    if isClearingData {
                        ProgressView()
                    }
                    else {
                        Text("reset_data".localized)
                            .foregroundColor(.red)
                    }
                }
                .disabled(isClearingData)
                .listRowInsets(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(PlainListStyle())
        .environment(\.defaultMinListRowHeight, 0)

        .animation(.default, value: isClearingData)
        .animation(.default, value: hasShownCommonIssuesTip)

        .onAppear {
            WindowHelper.shared.overrideUserInterfaceStyle(.dark)
        }
    }
}
