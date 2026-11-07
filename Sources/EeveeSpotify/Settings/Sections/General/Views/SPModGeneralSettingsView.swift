import SwiftUI

struct SPModGeneralSettingsView: View {
    @State private var language = UserDefaults.spmodLanguage

    var body: some View {
        List {
            Section(
                header: Text("language".localized),
                footer: Text("language_description".localized)
            ) {
                ForEach(SPModLanguage.allCases, id: \.self) { option in
                    Button {
                        guard option != language else {
                            return
                        }
                        language = option
                        UserDefaults.spmodLanguage = option
                        SPModAlertHelper.askRestart()
                    } label: {
                        HStack {
                            Text(option.title)
                                .foregroundColor(.white)
                            Spacer()
                            if option == language {
                                Image(systemName: "checkmark")
                                    .foregroundColor(EeveeSettingsView.spotifyAccentColor)
                            }
                        }
                    }
                }
            }

            NonIPadSpacerView()
        }
        .listStyle(GroupedListStyle())
        .animation(.default, value: language)
    }
}
