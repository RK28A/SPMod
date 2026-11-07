import SwiftUI

extension EeveeLyricsSettingsView {
    private var fallbackCandidates: [LyricsSource] {
        let enabled = fallbackOrder.filter { $0 != viewModel.lyricsSource }
        let disabled = LyricsSource.allCases.filter {
            $0 != viewModel.lyricsSource && !fallbackOrder.contains($0)
        }
        return enabled + disabled
    }
    
    private func isAvailable(_ source: LyricsSource) -> Bool {
        source != .musixmatch || !viewModel.musixmatchToken.isEmpty
    }
    
    private func move(_ source: LyricsSource, by offset: Int) {
        var visible = fallbackOrder.filter { $0 != viewModel.lyricsSource }
        guard let index = visible.firstIndex(of: source) else {
            return
        }
        let target = index + offset
        guard visible.indices.contains(target) else {
            return
        }
        visible.swapAt(index, target)
        fallbackOrder = visible
    }
    
    private func toggleBinding(_ source: LyricsSource) -> Binding<Bool> {
        Binding<Bool>(
            get: { fallbackOrder.contains(source) },
            set: { isOn in
                if isOn {
                    if !fallbackOrder.contains(source) {
                        fallbackOrder.append(source)
                    }
                }
                else {
                    fallbackOrder.removeAll { $0 == source }
                }
            }
        )
    }
    
    func refreshCacheSize() {
        DispatchQueue.global(qos: .utility).async {
            let size = LyricsCache.size()
            DispatchQueue.main.async {
                cacheSize = size
            }
        }
    }
    
    @ViewBuilder func fallbackOrderSection() -> some View {
        Section(
            header: Text("lyrics_fallback_order".localized),
            footer: Text("lyrics_fallback_order_description"
                .localizeWithFormat(viewModel.lyricsSource.description))
        ) {
            ForEach(fallbackCandidates, id: \.self) { source in
                HStack(spacing: 10) {
                    if let position = fallbackOrder.filter({ $0 != viewModel.lyricsSource }).firstIndex(of: source) {
                        Text("\(position + 1)")
                            .font(.footnote.weight(.bold))
                            .foregroundColor(.black)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(EeveeSettingsView.spotifyAccentColor))
                        
                        Button {
                            move(source, by: -1)
                        } label: {
                            Image(systemName: "chevron.up")
                        }
                        .buttonStyle(BorderlessButtonStyle())
                        .disabled(position == 0)
                        
                        Button {
                            move(source, by: 1)
                        } label: {
                            Image(systemName: "chevron.down")
                        }
                        .buttonStyle(BorderlessButtonStyle())
                        .disabled(position == fallbackOrder.filter({ $0 != viewModel.lyricsSource }).count - 1)
                    }
                    
                    Toggle(source.description, isOn: toggleBinding(source))
                        .disabled(!isAvailable(source))
                }
            }
            
            if !fallbackOrder.filter({ $0 != viewModel.lyricsSource }).isEmpty {
                Toggle(
                    "show_fallback_reasons".localized,
                    isOn: $viewModel.lyricsOptions.showFallbackReasons
                )
            }
        }
    }
    
    @ViewBuilder func cacheSection() -> some View {
        Section(
            header: Text("lyrics_cache".localized),
            footer: Text("lyrics_cache_description".localized)
        ) {
            Toggle("lyrics_cache_enabled".localized, isOn: $cacheEnabled)
            
            Button {
                DispatchQueue.global(qos: .userInitiated).async {
                    LyricsCache.clear()
                    refreshCacheSize()
                }
            } label: {
                HStack {
                    Text("lyrics_cache_clear".localized)
                        .foregroundColor(.red)
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: cacheSize, countStyle: .file))
                        .foregroundColor(.gray)
                }
            }
        }
    }
}
