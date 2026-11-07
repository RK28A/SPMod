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
        view: @escaping () -> any View
    ) -> some View {
        Button {
            pushSettingsController(with: view(), title: titleKey.localized)
        } label: {
            NavigationSectionView(
                color: color,
                title: titleKey.localized,
                imageSystemName: icon
            )
        }
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

            if !hasShownCommonIssuesTip {
                CommonIssuesTipView(
                    onDismiss: {
                        hasShownCommonIssuesTip = true
                        UserDefaults.hasShownCommonIssuesTip = true
                    }
                )
            }

            Section(header: Text("section_general".localized)) {
                navigationRow("general", icon: "gearshape.fill", color: .gray) {
                    SPModGeneralSettingsView()
                }
                navigationRow("patching", icon: "hammer.fill", color: .orange) {
                    EeveePatchingSettingsView()
                }
            }

            Section(header: Text("section_music".localized)) {
                navigationRow("lyrics", icon: "quote.bubble.fill", color: .blue) {
                    EeveeLyricsSettingsView()
                }
                navigationRow("playback", icon: "play.circle.fill", color: .green) {
                    SPModPlaybackSettingsView()
                }
                navigationRow("listening", icon: "chart.bar.fill", color: Color(hex: "#FF9F0A")) {
                    SPModListeningSettingsView()
                }
            }

            Section(header: Text("section_appearance".localized)) {
                navigationRow("themes", icon: "paintpalette.fill", color: Color(hex: "#FF5FA2")) {
                    SPModThemeSettingsView()
                }
            }

            Section(header: Text("section_advanced".localized)) {
                navigationRow("privacy", icon: "hand.raised.fill", color: Color(hex: "#5E5CE6")) {
                    SPModPrivacySettingsView()
                }
                navigationRow("backup", icon: "externaldrive.fill", color: Color(hex: "#64D2FF")) {
                    SPModBackupSettingsView()
                }
                navigationRow("experiments", icon: "sparkle", color: .purple) {
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
            }
        }
        .listStyle(GroupedListStyle())

        .animation(.default, value: isClearingData)
        .animation(.default, value: hasShownCommonIssuesTip)

        .onAppear {
            WindowHelper.shared.overrideUserInterfaceStyle(.dark)
        }
    }
}
