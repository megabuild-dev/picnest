import AppKit
import SwiftUI

/// The Settings window (⌘,): appearance and language.
struct SettingsView: View {
    @Bindable var appearance: AppearanceStore
    @Bindable var language: LanguageStore

    init(appearance: AppearanceStore, language: LanguageStore) {
        self.appearance = appearance
        self.language = language
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
                        Button("Restart", action: Self.relaunch)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Opens a new copy of the app, then quits this one the normal way, so the sort-in-progress prompt still shows.
    private static func relaunch() {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/open")
        process.arguments = ["-n", Bundle.main.bundleURL.path]
        try? process.run()
        NSApp.terminate(nil)
    }
}
