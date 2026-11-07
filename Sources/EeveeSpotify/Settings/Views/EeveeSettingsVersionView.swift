import SwiftUI

struct EeveeSettingsVersionView: View {
    @State private var latestVersion: String?
    @State private var isPresentingContributorsSheet = false
    
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
    
    private var isUpdateAvailable: Bool {
        latestVersion != nil && latestVersion != EeveeSpotify.version
    }
    
    var body: some View {
        Section {
            if isUpdateAvailable {
                Link(
                    "update_available".localized,
                    destination: URL(string: "https://github.com/RK28A/SPMod/releases")!
                )
            }
        } footer: {
            VStack(alignment: .leading) {
                Text("v\(EeveeSpotify.version)")
                
                if latestVersion == nil {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("checking_for_update".localized)
                    }
                }
                else {
                    Button("\("contributors".localized)...") {
                        isPresentingContributorsSheet = true
                    }
                    .foregroundColor(.gray)
                    .font(.subheadline.weight(.semibold))
                }
            }
        }
        .sheet(isPresented: $isPresentingContributorsSheet) {
            EeveeContributorsSheetView()
        }
        
        .animation(.default, value: latestVersion)
        
        .onAppear {
            Task {
                await loadVersion()
            }
        }
    }
}
