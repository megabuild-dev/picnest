import AppKit
import PicnestCore
import UniformTypeIdentifiers

/// The save panel of **Export edited copy** and of the layout export: a suggested name, a folder, and a format menu.
/// It returns the chosen file and format, or nil on cancel. The panel does not replace a photo by itself:
/// the export refuses a protected name (`ProtectedFiles`).
@MainActor
enum EditorSavePanel {
    static func choose<F: ExportFileFormat>(
        suggestedName: String, folder: URL, format: F, title: (F) -> String
    ) async -> (URL, F)? {
        let panel = NSSavePanel()
        panel.directoryURL = folder
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = [format.utType]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        let formats = Array(F.allCases)
        let popUp = NSPopUpButton(frame: .zero, pullsDown: false)
        popUp.addItems(withTitles: formats.map(title))
        popUp.selectItem(at: formats.firstIndex(of: format) ?? 0)
        let target = FormatTarget(panel: panel, popUp: popUp, types: formats.map(\.utType), extensions: formats.map(\.fileExtension))
        popUp.target = target
        popUp.action = #selector(FormatTarget.changed)
        let label = NSTextField(labelWithString: String(localized: "Format"))
        let row = NSStackView(views: [label, popUp])
        row.spacing = 8
        row.edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        panel.accessoryView = row

        let response = await withCheckedContinuation { continuation in
            panel.begin { continuation.resume(returning: $0) }
        }
        withExtendedLifetime(target) {}
        guard response == .OK, let url = panel.url else { return nil }
        return (url, formats[max(popUp.indexOfSelectedItem, 0)])
    }

    /// The menu titles of the photo editor formats.
    static func title(of format: ExportFormat) -> String {
        switch format {
        case .jpeg: "JPEG"
        case .heic: "HEIC"
        case .png: "PNG"
        }
    }

    /// The menu titles of the layout formats.
    static func title(of format: LayoutExportFormat) -> String {
        switch format {
        case .png: "PNG"
        case .pdf: "PDF"
        }
    }

    /// Changes the extension of the name and the allowed type when the user picks another format.
    private final class FormatTarget: NSObject {
        let panel: NSSavePanel
        let popUp: NSPopUpButton
        let types: [UTType]
        let extensions: [String]

        init(panel: NSSavePanel, popUp: NSPopUpButton, types: [UTType], extensions: [String]) {
            self.panel = panel
            self.popUp = popUp
            self.types = types
            self.extensions = extensions
        }

        @objc func changed() {
            let index = max(popUp.indexOfSelectedItem, 0)
            let stem = (panel.nameFieldStringValue as NSString).deletingPathExtension
            panel.allowedContentTypes = [types[index]]
            panel.nameFieldStringValue = stem + "." + extensions[index]
        }
    }
}
