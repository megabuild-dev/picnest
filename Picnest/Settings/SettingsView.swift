import AppKit
import SwiftUI

/// The Settings window (⌘,): appearance, language, and updates.
struct SettingsView: View {
    @Bindable var appearance: AppearanceStore
    @Bindable var language: LanguageStore
    let relauncher: AppRelauncher
    /// Nil in the test host; the Updates section then shows the note only.
    let updater: (any AppUpdater)?

    init(appearance: AppearanceStore, language: LanguageStore, relauncher: AppRelauncher,
         updater: (any AppUpdater)? = nil) {
        self.appearance = appearance
        self.language = language
        self.relauncher = relauncher
        self.updater = updater
    }

    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: $appearance.mode) {
                    Text("System").tag(AppearanceMode.system)
                    Text("Light").tag(AppearanceMode.light)
                    Text("Dark").tag(AppearanceMode.dark)
                }
                .pickerStyle(.menu)
            }
            Section {
                Picker("Language", selection: $language.language) {
                    ForEach(AppLanguage.allCases) { Text(verbatim: $0.displayName).tag($0) }
                }
                .pickerStyle(.menu)
                LanguageRestartRow(language: language, relauncher: relauncher)
            }
            Section("Updates") {
                if let updater {
                    CheckForUpdatesView(updater: updater)
                }
                Text("Picnest checks for a new version once a day. It sends no photos and no personal data.")
                    .font(.callout)
                    .foregroundStyle(Theme.textSecondary.color)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}
