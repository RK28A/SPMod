import SwiftUI

extension EeveeLyricsSettingsView {
    private var translationBinding: Binding<Bool> {
        Binding<Bool>(
            get: { translationEnabled },
            set: { isOn in
                guard isOn else {
                    translationEnabled = false
                    UserDefaults.lyricsTranslationEnabled = false
                    return
                }
                if OnDeviceTranslation.isAvailable || UserDefaults.lyricsTranslationConsent {
                    translationEnabled = true
                    UserDefaults.lyricsTranslationEnabled = true
                    return
                }
                SPModAlertHelper.confirm([
                    SPModAlertStep(
                        title: "translation_consent_title".localized,
                        message: "translation_consent_message".localized,
                        confirmTitle: "translation_consent_accept".localized
                    )
                ]) {
                    UserDefaults.lyricsTranslationConsent = true
                    UserDefaults.lyricsTranslationEnabled = true
                    translationEnabled = true
                }
            }
        )
    }
    
    @ViewBuilder func translationSection() -> some View {
        Section(
            header: Text("translation".localized),
            footer: Text(
                OnDeviceTranslation.isAvailable
                    ? "translation_description_local".localized
                    : "translation_description".localized
            )
        ) {
            Toggle("translation_enabled".localized, isOn: translationBinding)
            
            if translationEnabled {
                Picker("translation_target".localized, selection: $translationTarget) {
                    ForEach(TranslationLanguage.all, id: \.code) { language in
                        Text(language.name).tag(language.code)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                
                Picker("translation_mode".localized, selection: $translationMode) {
                    ForEach(LyricsTranslationMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                
                if OnDeviceTranslation.isAvailable {
                    Toggle(
                        "translation_online_fallback".localized,
                        isOn: Binding<Bool>(
                            get: { UserDefaults.lyricsTranslationConsent },
                            set: { isOn in
                                guard isOn else {
                                    UserDefaults.lyricsTranslationConsent = false
                                    return
                                }
                                SPModAlertHelper.confirm([
                                    SPModAlertStep(
                                        title: "translation_consent_title".localized,
                                        message: "translation_consent_message".localized,
                                        confirmTitle: "translation_consent_accept".localized
                                    )
                                ]) {
                                    UserDefaults.lyricsTranslationConsent = true
                                }
                            }
                        )
                    )
                }
                else {
                    Button("translation_revoke".localized) {
                        UserDefaults.lyricsTranslationConsent = false
                        UserDefaults.lyricsTranslationEnabled = false
                        translationEnabled = false
                    }
                    .foregroundColor(.red)
                }
            }
        }
    }
}
