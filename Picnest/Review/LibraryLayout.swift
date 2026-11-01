import SwiftUI

/// How the Library shows its photos. Kept in `@AppStorage("libraryLayout")`.
enum LibraryLayout: String, CaseIterable, Identifiable {
    case grid, list

    static let storageKey = "libraryLayout"

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .grid: "Grid"
        case .list: "List"
        }
    }

    var symbol: String {
        switch self {
        case .grid: "square.grid.2x2"
        case .list: "list.bullet"
        }
    }
}

/// The segmented control of the toolbar: grid icon, list icon.
struct LibraryLayoutPicker: View {
    @Binding var layout: LibraryLayout

    var body: some View {
        Picker("Layout", selection: $layout) {
            ForEach(LibraryLayout.allCases) { option in
                Label(option.title, systemImage: option.symbol)
                    .labelStyle(.iconOnly)
                    .tag(option)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .help("Grid or list")
        .accessibilityLabel("Layout")
    }
}
