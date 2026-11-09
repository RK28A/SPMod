import SwiftUI

struct SPModLabsSettingsView: View {
    @State private var enabled = UserDefaults.enabledLabGroups

    private func binding(for group: SPModLabGroup) -> Binding<Bool> {
        Binding(
            get: { enabled.contains(group.id) },
            set: { isOn in
                if isOn {
                    enabled.insert(group.id)
                } else {
                    enabled.remove(group.id)
                }
                UserDefaults.enabledLabGroups = enabled
                SPModAlertHelper.askRestart()
            }
        )
    }

    var body: some View {
        List {
            Section(footer: Text("labs_description".localized)) {
                ForEach(SPModLabs.groups) { group in
                    Toggle(isOn: binding(for: group)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.title.localized)
                            Text(group.subtitle.localized)
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                }
            }

            NonIPadSpacerView()
        }
        .listStyle(GroupedListStyle())
    }
}
