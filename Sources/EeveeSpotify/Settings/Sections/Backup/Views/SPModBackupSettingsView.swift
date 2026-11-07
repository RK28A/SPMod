import SwiftUI

struct SPModBackupSettingsView: View {
    var body: some View {
        List {
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
    }
}
