import SwiftUI

struct EeveeLyricsSettingsView: View {
    @StateObject var viewModel = EeveeLyricsSettingsViewModel()
    @State var fallbackOrder = UserDefaults.lyricsFallbackOrder
    @State var cacheEnabled = UserDefaults.lyricsCacheEnabled
    @State var cacheSize: Int64 = 0
    
    var body: some View {
        List {
            lyricsSourceSection()
            
            if viewModel.lyricsSource != .notReplaced {
                fallbackOrderSection()
                cacheSection()
                
                hideOnErrorSection()
                romanizedLyricsSection()
                
                if viewModel.lyricsSource == .musixmatch {
                    musixmatchLanguageSection()
                }
            }
            
            NonIPadSpacerView()
        }
        .onReceive(viewModel.musixmatchTokenInputAlertPublisher) { showAnonymousTokenOption in
            showMusixmatchTokenAlert(UserDefaults.lyricsSource, showAnonymousTokenOption)
        }
        .listStyle(GroupedListStyle())
        .disabled(viewModel.isRequestingMusixmatchToken)
        .animation(.default, value: viewModel.animationValues)
        .animation(.default, value: fallbackOrder)
        .animation(.default, value: cacheEnabled)
        .onChange(of: fallbackOrder) { order in
            UserDefaults.lyricsFallbackOrder = order
            viewModel.lyricsOptions.geniusFallback = order.contains(.genius)
        }
        .onChange(of: cacheEnabled) { enabled in
            UserDefaults.lyricsCacheEnabled = enabled
        }
        .onAppear {
            refreshCacheSize()
        }
    }
    
    @ViewBuilder private func romanizedLyricsSection() -> some View {
        Section {
            Toggle(
                "romanized_lyrics".localized,
                isOn: $viewModel.lyricsOptions.romanization
            )
        } footer: {
            Text("romanized_lyrics_description".localized)
        }
    }
    
    @ViewBuilder private func hideOnErrorSection() -> some View {
        Section {
            Toggle(
                "hide_lyrics_on_error".localized,
                isOn: $viewModel.lyricsOptions.hideOnError
            )
        } footer: {
            Text("hide_lyrics_on_error_description".localized)
        }
    }
    
    @ViewBuilder private func musixmatchLanguageSection() -> some View {
        Section {
            HStack {
                Text("musixmatch_language".localized)
                
                Spacer()
                
                TextField("en", text: $viewModel.lyricsOptions.musixmatchLanguage)
                    .frame(maxWidth: 20)
                    .foregroundColor(.gray)
            }
            .icon(
                "exclamationmark.triangle.fill",
                color: .yellow,
                when: $viewModel.showMusixmatchInvalidLanguageWarning
            )
        } footer: {
            Text("musixmatch_language_description".localized)
        }
    }
}
