import AppKit
import PicnestCore
import UniformTypeIdentifiers

/// The save panel of **Export edited copy**: a suggested name, the folder of the photo, and a format menu.
/// It returns the chosen file and format, or nil on cancel. The panel does not replace a photo by itself:
/// the export refuses a protected name (`ProtectedFiles`).
@MainActor
enum EditorSavePanel {
    static func choose(suggestedName: String, folder: URL, format: ExportFormat) async -> (URL, ExportFormat)? {
        let panel = NSSavePanel()
        panel.directoryURL = folder
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = [format.utType]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        let formats = ExportFormat.allCases
        let popUp = NSPopUpButton(frame: .zero, pullsDown: false)
        popUp.addItems(withTitles: formats.map(title(of:)))
        popUp.selectItem(at: formats.firstIndex(of: format) ?? 0)
        let target = FormatTarget(panel: panel, popUp: popUp, formats: formats)
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

    private static func title(of format: ExportFormat) -> String {
        switch format {
        case .jpeg: "JPEG"
        case .heic: "HEIC"
        case .png: "PNG"
        }
    }

    /// Changes the extension of the name and the allowed type when the user picks another format.
    private final class FormatTarget: NSObject {
        let panel: NSSavePanel
        let popUp: NSPopUpButton
        let formats: [ExportFormat]

        init(panel: NSSavePanel, popUp: NSPopUpButton, formats: [ExportFormat]) {
            self.panel = panel
            self.popUp = popUp
            self.formats = formats
        }

        @objc func changed() {
            let format = formats[max(popUp.indexOfSelectedItem, 0)]
            let stem = (panel.nameFieldStringValue as NSString).deletingPathExtension
            panel.allowedContentTypes = [format.utType]
            panel.nameFieldStringValue = stem + "." + format.fileExtension
        }
    }
}
