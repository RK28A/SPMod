import SwiftUI

struct SPModBackupSettingsView: View {
    @State private var autoBackup = SPModVault.autoBackupEnabled
    @State private var folderName = SPModVault.folderName
    @State private var lastBackup = SPModVault.lastBackup
    @State private var isBackingUp = false
    
    private var lastBackupText: String {
        guard let lastBackup = lastBackup else {
            return "vault_never".localized
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: lastBackup)
    }
    
    private func refresh() {
        folderName = SPModVault.folderName
        lastBackup = SPModVault.lastBackup
    }
    
    var body: some View {
        List {
            Section(
                header: Text("vault_section".localized),
                footer: Text("vault_description".localized)
            ) {
                Button {
                    SPModVault.chooseFolder()
                } label: {
                    HStack {
                        Label("vault_folder".localized, systemImage: "folder.fill")
                        Spacer()
                        Text(folderName ?? "vault_no_folder".localized)
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    }
                }
                
                Toggle("vault_auto".localized, isOn: $autoBackup)
                
                Button {
                    isBackingUp = true
                    SPModVault.backupNow { success in
                        isBackingUp = false
                        refresh()
                        ToastHelper.show(success ? "vault_backup_done".localized : "vault_backup_failed".localized)
                    }
                } label: {
                    HStack {
                        Label("vault_backup_now".localized, systemImage: "arrow.clockwise.icloud.fill")
                        Spacer()
                        if isBackingUp {
                            ProgressView()
                        }
                        else {
                            Text(lastBackupText)
                                .foregroundColor(.gray)
                                .font(.footnote)
                        }
                    }
                }
                .disabled(isBackingUp)
                
                Button {
                    SPModVault.chooseRestoreFile()
                } label: {
                    Label("vault_restore".localized, systemImage: "arrow.down.doc.fill")
                }
            }
            
            Section(footer: Text("backup_export_description".localized)) {
                Button {
                    SPModBackupHelper.exportSettings()
                } label: {
                    Label("backup_export".localized, systemImage: "square.and.arrow.up")
                }
            }

            Section(footer: Text("backup_import_description".localized)) {
                Button {
                    SPModBackupHelper.importSettings()
                } label: {
                    Label("backup_import".localized, systemImage: "square.and.arrow.down")
                }
            }

            NonIPadSpacerView()
        }
        .listStyle(GroupedListStyle())
        .onChange(of: autoBackup) { value in
            SPModVault.autoBackupEnabled = value
        }
        .onReceive(NotificationCenter.default.publisher(for: SPModVault.didChangeNotification)) { _ in
            refresh()
        }
        .onAppear {
            refresh()
        }
    }
}
