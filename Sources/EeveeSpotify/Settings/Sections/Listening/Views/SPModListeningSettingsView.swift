import SwiftUI

struct SPModListeningSettingsView: View {
    @State private var collectionEnabled = UserDefaults.listeningCollectionEnabled
    @State private var deletePeriod: StatsPeriod = .today
    @State private var customStart = Date()
    @State private var customEnd = Date()

    private func confirmDelete(_ interval: DateInterval?) {
        SPModAlertHelper.confirm([
            SPModAlertStep(
                title: "listening_delete_title".localized,
                message: interval == nil
                    ? "listening_delete_all_message".localized
                    : "listening_delete_period_message".localized,
                confirmTitle: "history_delete_entry".localized,
                isDestructive: true
            )
        ]) {
            if let interval = interval {
                ListeningStore.shared.delete(in: interval)
            }
            else {
                ListeningStore.shared.deleteAll()
            }
            ToastHelper.show("listening_deleted".localized)
        }
    }

    var body: some View {
        List {
            Section {
                Button {
                    SPModSettingsNavigator.push(SPModStatsView(), title: "stats".localized)
                } label: {
                    NavigationSectionView(color: .green, title: "stats".localized, imageSystemName: "chart.bar.fill")
                }
                Button {
                    SPModSettingsNavigator.push(SPModHistoryView(), title: "history".localized)
                } label: {
                    NavigationSectionView(color: .blue, title: "history".localized, imageSystemName: "clock.fill")
                }
            }

            Section(footer: Text("listening_collection_description".localized)) {
                Toggle("listening_collection".localized, isOn: $collectionEnabled)
            }

            Section(
                header: Text("listening_data".localized),
                footer: Text("listening_data_description".localized)
            ) {
                Button {
                    ListeningExport.export(.json)
                } label: {
                    Label("listening_export_json".localized, systemImage: "square.and.arrow.up")
                }
                Button {
                    ListeningExport.export(.csv)
                } label: {
                    Label("listening_export_csv".localized, systemImage: "tablecells")
                }
                Button {
                    ListeningExport.importData()
                } label: {
                    Label("listening_import".localized, systemImage: "square.and.arrow.down")
                }
            }

            PeriodPickerSection(period: $deletePeriod, customStart: $customStart, customEnd: $customEnd)

            Section {
                Button("listening_delete_period".localized) {
                    let interval = deletePeriod.interval(
                        customStart: customStart,
                        customEnd: customEnd,
                        firstRecord: ListeningStore.shared.allRecords().first?.start
                    )
                    confirmDelete(interval)
                }
                .foregroundColor(.red)

                Button("listening_delete_all".localized) {
                    confirmDelete(nil)
                }
                .foregroundColor(.red)
            }

            NonIPadSpacerView()
        }
        .listStyle(GroupedListStyle())
        .onChange(of: collectionEnabled) { enabled in
            UserDefaults.listeningCollectionEnabled = enabled
            if enabled {
                ListeningTracker.start()
            }
        }
    }
}
