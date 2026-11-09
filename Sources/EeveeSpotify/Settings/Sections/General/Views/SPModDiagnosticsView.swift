import SwiftUI
import UIKit

struct SPModDiagnosticsView: View {
    private let entries = SPModDiagnostics.failedHooks
    private let requests = SPModDiagnostics.seenRequests
    private let adBlock = SPModDiagnostics.adBlockLog
    private let spotifyVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"

    private var report: String {
        (["SPMod \(EeveeSpotify.version) · Spotify \(spotifyVersion) · iOS \(UIDevice.current.systemVersion)", "patch: \(UserDefaults.patchType)", "-- adblock"] + adBlock + ["-- hooks"] + entries + ["-- requests"] + requests)
            .joined(separator: "\n")
    }
    
    var body: some View {
        List {
            Section(footer: Text("diagnostics_description".localized)) {
                HStack {
                    Text("Spotify")
                    Spacer()
                    Text(spotifyVersion).foregroundColor(.gray)
                }
                HStack {
                    Text("SPMod")
                    Spacer()
                    Text(EeveeSpotify.version).foregroundColor(.gray)
                }
                HStack {
                    Text("diagnostics_skipped_hooks".localized)
                    Spacer()
                    Text("\(entries.count)").foregroundColor(.gray)
                }
            }
            
            Section(header: Text("Ad Block")) {
                ForEach(adBlock, id: \.self) { entry in
                    Text(entry)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }

            if !entries.isEmpty {
                Section(header: Text("diagnostics_details".localized)) {
                    ForEach(entries, id: \.self) { entry in
                        Text(entry)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
            }
            
            if !requests.isEmpty {
                Section(header: Text("diagnostics_requests".localized)) {
                    ForEach(requests.prefix(60), id: \.self) { entry in
                        Text(entry)
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                }
            }
            
            Section {
                Button("diagnostics_copy".localized) {
                    UIPasteboard.general.string = report
                    ToastHelper.show("copied_to_clipboard".localized)
                }
            }
            
            NonIPadSpacerView()
        }
        .listStyle(GroupedListStyle())
    }
}
