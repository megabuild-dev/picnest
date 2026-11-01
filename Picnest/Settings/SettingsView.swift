import SwiftUI

/// The Settings window (⌘,). Task 0.6 adds the Language picker to this form.
struct SettingsView: View {
    @Bindable var appearance: AppearanceStore

    init(appearance: AppearanceStore) {
        self.appearance = appearance
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
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}
