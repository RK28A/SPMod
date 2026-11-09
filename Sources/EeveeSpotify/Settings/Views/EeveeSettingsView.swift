import SwiftUI
import UIKit

struct EeveeSettingsView: View {
    let navigationController: UINavigationController
    static var spotifyAccentColor: Color {
        Color(UIColor(spmodHex: UserDefaults.themeConfig.accentHex))
    }

    @State private var hasShownCommonIssuesTip = UserDefaults.hasShownCommonIssuesTip
    @State private var isClearingData = false
    @State private var latestVersion: String?
    @State private var isPresentingContributorsSheet = false

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

    private func navRow(
        _ titleKey: String,
        icon: String,
        color: Color,
        subtitle: String? = nil,
        showsDivider: Bool = true,
        view: @escaping () -> any View
    ) -> SPModNavRow {
        SPModNavRow(
            title: titleKey.localized,
            subtitle: subtitle?.localized,
            icon: icon,
            color: color,
            showsDivider: showsDivider
        ) {
            pushSettingsController(with: view(), title: titleKey.localized)
        }
    }

    private func loadVersion() async {
        guard
            let release = try? await GitHubHelper.shared.getLatestRelease(),
            release.tagName.hasPrefix("spmod-v"),
            let version = release.tagName.dropFirst(7).split(separator: "-").first
        else {
            latestVersion = EeveeSpotify.version
            return
        }
        latestVersion = String(version)
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

    @ViewBuilder private func sectionLabel(_ key: String) -> some View {
        Text(key.localized)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(SPModPalette.secondaryText)
            .textCase(.uppercase)
            .padding(.leading, 6)
            .padding(.bottom, 2)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                SPModHeroHeader(
                    version: EeveeSpotify.version,
                    latestVersion: latestVersion,
                    premiumActive: UserDefaults.patchType.isPatching,
                    adBlockActive: true,
                    onContributors: { isPresentingContributorsSheet = true }
                )

                if !hasShownCommonIssuesTip {
                    CommonIssuesTipView(
                        onDismiss: {
                            hasShownCommonIssuesTip = true
                            UserDefaults.hasShownCommonIssuesTip = true
                        }
                    )
                }

                VStack(alignment: .leading, spacing: 8) {
                    sectionLabel("general")
                    SPModCard {
                        navRow("general", icon: "gearshape.fill", color: .gray, subtitle: "general_subtitle", showsDivider: false) {
                            SPModGeneralSettingsView()
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    sectionLabel("lyrics")
                    SPModCard {
                        navRow("lyrics", icon: "quote.bubble.fill", color: .blue, subtitle: "lyrics_subtitle") {
                            EeveeLyricsSettingsView()
                        }
                        navRow("playback", icon: "play.circle.fill", color: .green, subtitle: "playback_subtitle") {
                            SPModPlaybackSettingsView()
                        }
                        navRow("listening", icon: "chart.bar.fill", color: Color(hex: "#FF9F0A"), subtitle: "listening_subtitle") {
                            SPModListeningSettingsView()
                        }
                        navRow("playlists", icon: "music.note.list", color: Color(hex: "#30D158"), subtitle: "playlists_subtitle", showsDivider: false) {
                            SPModPlaylistsView()
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    sectionLabel("themes")
                    SPModCard {
                        navRow("themes", icon: "paintbrush.fill", color: Color(hex: "#FF5FA2"), subtitle: "themes_subtitle", showsDivider: false) {
                            SPModThemeSettingsView()
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    sectionLabel("privacy")
                    SPModCard {
                        navRow("privacy", icon: "hand.raised.fill", color: Color(hex: "#5E5CE6"), subtitle: "privacy_subtitle") {
                            SPModPrivacySettingsView()
                        }
                        navRow("artist_block", icon: "nosign", color: Color(hex: "#FF453A"), subtitle: "artist_block_subtitle") {
                            SPModBlockedArtistsView()
                        }
                        navRow("backup", icon: "externaldrive.fill", color: Color(hex: "#64D2FF"), subtitle: "backup_subtitle") {
                            SPModBackupSettingsView()
                        }
                        navRow("labs", icon: "flask.fill", color: Color(hex: "#FFD60A"), subtitle: "labs_subtitle") {
                            SPModLabsSettingsView()
                        }
                        navRow("experiments", icon: "sparkles", color: .purple, subtitle: "experiments_subtitle", showsDivider: false) {
                            EeveeExperimentsSettingsView()
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Button(action: resetData) {
                        HStack {
                            Spacer()
                            if isClearingData {
                                ProgressView()
                            } else {
                                Text("reset_data".localized)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.red)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(SPModPalette.cardBackground)
                        )
                    }
                    .disabled(isClearingData)

                    Text("reset_data_description".localized)
                        .font(.system(size: 12))
                        .foregroundColor(SPModPalette.secondaryText)
                        .padding(.horizontal, 6)
                }

                NonIPadSpacerView()

                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Color.black.ignoresSafeArea())
        .sheet(isPresented: $isPresentingContributorsSheet) {
            EeveeContributorsSheetView()
        }
        .animation(.default, value: isClearingData)
        .animation(.default, value: hasShownCommonIssuesTip)
        .animation(.default, value: latestVersion)
        .onAppear {
            WindowHelper.shared.overrideUserInterfaceStyle(.dark)
            Task { await loadVersion() }
        }
    }
}
