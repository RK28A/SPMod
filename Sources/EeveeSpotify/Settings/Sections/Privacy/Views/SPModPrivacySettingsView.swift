import SwiftUI

struct SPModPrivacySettingsView: View {
    @State private var mode = UserDefaults.privacyMode
    @State private var custom = UserDefaults.privacyCustomCategories
    @State private var stats = PrivacyStatsStore.snapshot()
    @State private var logsEnabled = UserDefaults.spmodLogsEnabled
    @State private var declutter = UserDefaults.declutterEnabled
    @State private var hasPendingChanges = false

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    private var activeCategories: Set<PrivacyCategory> {
        mode == .custom ? custom : mode.categories
    }

    private func customBinding(_ category: PrivacyCategory) -> Binding<Bool> {
        Binding<Bool>(
            get: { custom.contains(category) },
            set: { isOn in
                if isOn {
                    custom.insert(category)
                }
                else {
                    custom.remove(category)
                }
            }
        )
    }

    var body: some View {
        let total = stats.values.reduce(0) { $0 + $1.count }

        List {
            Section(
                header: Text("privacy_mode".localized),
                footer: Text("privacy_mode_description".localized)
            ) {
                Picker("privacy_mode".localized, selection: $mode) {
                    ForEach(PrivacyMode.allCases, id: \.self) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
            }

            Section(header: Text("privacy_categories".localized)) {
                ForEach(PrivacyCategory.allCases) { category in
                    VStack(alignment: .leading, spacing: 4) {
                        if mode == .custom {
                            Toggle(category.title, isOn: customBinding(category))
                        }
                        else {
                            HStack {
                                Text(category.title)
                                Spacer()
                                Image(systemName: activeCategories.contains(category) ? "checkmark.shield.fill" : "shield")
                                    .foregroundColor(activeCategories.contains(category) ? .green : .gray)
                            }
                        }
                        Text(category.effect)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding(.vertical, 2)
                }
            }

            Section(
                header: Text("declutter".localized),
                footer: Text("declutter_description".localized)
            ) {
                Toggle("declutter_enabled".localized, isOn: $declutter)
            }

            if hasPendingChanges {
                Section(footer: Text("restart_is_required_description".localized)) {
                    Button("restart_now".localized) {
                        PrivacyStatsStore.flush()
                        exitApplication()
                    }
                }
            }

            Section(
                header: Text("privacy_dashboard".localized),
                footer: Text("privacy_dashboard_description".localized)
            ) {
                HStack {
                    Text("privacy_total_blocked".localized)
                    Spacer()
                    Text("\(total)").foregroundColor(.gray)
                }
                ForEach(PrivacyCategory.allCases) { category in
                    let entry = stats[category.rawValue]
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(category.title)
                            Text(entry?.last.map { "privacy_last_blocked".localizeWithFormat(dateFormatter.string(from: $0)) } ?? "privacy_never_blocked".localized)
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        Spacer()
                        Text("\(entry?.count ?? 0)")
                            .foregroundColor(.white)
                    }
                }
                Button("privacy_reset_counters".localized) {
                    PrivacyStatsStore.reset()
                    stats = [:]
                }
            }

            Section(
                header: Text("privacy_local_data".localized),
                footer: Text("privacy_local_data_description".localized)
            ) {
                Toggle("privacy_logs".localized, isOn: $logsEnabled)

                Button("privacy_delete_listening".localized) {
                    SPModAlertHelper.confirm([
                        SPModAlertStep(
                            title: "listening_delete_title".localized,
                            message: "listening_delete_all_message".localized,
                            confirmTitle: "history_delete_entry".localized,
                            isDestructive: true
                        )
                    ]) {
                        ListeningStore.shared.deleteAll()
                        ToastHelper.show("listening_deleted".localized)
                    }
                }
                .foregroundColor(.red)

                Button("privacy_delete_lyrics_cache".localized) {
                    DispatchQueue.global(qos: .userInitiated).async {
                        LyricsCache.clear()
                        ToastHelper.show("listening_deleted".localized)
                    }
                }
                .foregroundColor(.red)

                Button("privacy_revoke_translation".localized) {
                    UserDefaults.lyricsTranslationConsent = false
                    UserDefaults.lyricsTranslationEnabled = false
                    ToastHelper.show("listening_deleted".localized)
                }
                .foregroundColor(.red)
            }

            NonIPadSpacerView()
        }
        .listStyle(GroupedListStyle())
        .animation(.default, value: mode)
        .animation(.default, value: hasPendingChanges)
        .onAppear {
            stats = PrivacyStatsStore.snapshot()
        }
        .onChange(of: mode) { value in
            UserDefaults.privacyMode = value
            hasPendingChanges = true
        }
        .onChange(of: custom) { value in
            UserDefaults.privacyCustomCategories = value
            hasPendingChanges = true
        }
        .onChange(of: logsEnabled) { value in
            UserDefaults.spmodLogsEnabled = value
        }
        .onChange(of: declutter) { value in
            UserDefaults.declutterEnabled = value
            hasPendingChanges = true
        }
    }
}
