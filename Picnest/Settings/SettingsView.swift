import AppKit
import SwiftUI

/// The Settings window (⌘,): appearance and language.
struct SettingsView: View {
    @Bindable var appearance: AppearanceStore
    @Bindable var language: LanguageStore
    let relauncher: AppRelauncher

    init(appearance: AppearanceStore, language: LanguageStore, relauncher: AppRelauncher) {
        self.appearance = appearance
        self.language = language
        self.relauncher = relauncher
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
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}
