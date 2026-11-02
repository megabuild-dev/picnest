import AppKit
import SwiftUI

/// The restart note that shows after a language change. Settings and the sidebar bar both use it.
struct LanguageRestartRow: View {
    let language: LanguageStore
    let relauncher: AppRelauncher

    var body: some View {
        if language.needsRestart {
            HStack {
                Text("Restart Picnest to change the language.")
                Spacer()
                Button("Restart") {
                    if relauncher.request() { NSApp.terminate(nil) }
                }
            }
        }
    }
}

/// Appearance and language controls at the bottom of the sidebar. The Settings window (⌘,) keeps the same choices.
struct SidebarPreferencesBar: View {
    @Bindable var appearance: AppearanceStore
    @Bindable var language: LanguageStore
    let relauncher: AppRelauncher

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Appearance", selection: $appearance.mode) {
                Label("System", systemImage: "circle.lefthalf.filled").tag(AppearanceMode.system)
                    .help("System")
                Label("Light", systemImage: "sun.max").tag(AppearanceMode.light)
                    .help("Light")
                Label("Dark", systemImage: "moon").tag(AppearanceMode.dark)
                    .help("Dark")
            }
            .pickerStyle(.segmented)
            .labelStyle(.iconOnly)
            .labelsHidden()
            .accessibilityLabel("Appearance")
            Picker(selection: $language.language) {
                ForEach(AppLanguage.allCases) { Text(verbatim: $0.displayName).tag($0) }
            } label: {
                Label("Language", systemImage: "globe")
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .accessibilityLabel("Language")
            LanguageRestartRow(language: language, relauncher: relauncher)
                .font(.callout)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.sidebar.color)
        .overlay(alignment: .top) { Divider() }
    }
}

/// The stores that the sidebar bar needs.
struct SidebarPreferences {
    let appearance: AppearanceStore
    let language: LanguageStore
    let relauncher: AppRelauncher
}
