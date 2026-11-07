import SwiftUI

struct SPModPlaybackSettingsView: View {
    @State private var keepScreenOn = UserDefaults.keepScreenOn
    @State private var disableCanvas = UserDefaults.disableCanvas
    @State private var copyOnShake = UserDefaults.copyTrackOnShake
    @State private var copyFormat = UserDefaults.copyTrackFormat

    var body: some View {
        List {
            Section(footer: Text("keep_screen_on_description".localized)) {
                Toggle("keep_screen_on".localized, isOn: $keepScreenOn)
            }

            Section(footer: Text("disable_canvas_description".localized)) {
                Toggle("disable_canvas".localized, isOn: $disableCanvas)
            }

            Section(
                header: Text("copy_track_section".localized),
                footer: Text("copy_on_shake_description".localized)
            ) {
                Toggle("copy_on_shake".localized, isOn: $copyOnShake)

                if copyOnShake {
                    Picker("copy_format".localized, selection: $copyFormat) {
                        ForEach(SPModCopyFormat.allCases, id: \.self) { format in
                            Text(format.title).tag(format)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                }
            }

            NonIPadSpacerView()
        }
        .listStyle(GroupedListStyle())
        .animation(.default, value: copyOnShake)

        .onChange(of: keepScreenOn) { value in
            UserDefaults.keepScreenOn = value
            SPModAlertHelper.askRestart()
        }
        .onChange(of: disableCanvas) { value in
            UserDefaults.disableCanvas = value
            SPModAlertHelper.askRestart()
        }
        .onChange(of: copyOnShake) { value in
            UserDefaults.copyTrackOnShake = value
            SPModAlertHelper.askRestart()
        }
        .onChange(of: copyFormat) { value in
            UserDefaults.copyTrackFormat = value
        }
    }
}
