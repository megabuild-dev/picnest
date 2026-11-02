import PicnestCore
import SwiftUI
import UniformTypeIdentifiers

/// Welcome screen (spec 4.3): header, drop zone, **Choose Folder…**, recent folder cards.
struct WelcomeView: View {
    @Bindable var model: WelcomeViewModel
    @State private var isImporting = false
    @State private var isTargeted = false
    /// True when the importer finds a missing recent folder, not a new one.
    @State private var isFinding = false

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                header
                dropZone
                if !model.recent.isEmpty { recentList }
                Label("Your photos stay on this Mac.", systemImage: "lock.shield")
                    .font(.callout)
                    .foregroundStyle(Theme.textSecondary.color)
            }
            .frame(maxWidth: 640)
            .padding(40)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background.color)
        .onAppear(perform: model.refresh)
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.folder]) { result in
            guard case .success(let url) = result else { return }
            if isFinding { model.findFolder(url) } else { model.choose(url) }
        }
        .alert("Folder not found", isPresented: missingBinding, presenting: model.missingFolder) { _ in
            Button("Find Folder…") {
                model.beginFindingFolder()
                isFinding = true
                isImporting = true
            }
            Button("Cancel", role: .cancel, action: model.dismissMissingFolder)
        } message: { folder in
            Text("“\(model.name(folder))” was moved, renamed, or deleted. Find it to continue.")
        }
        .alert(model.newSortRequest?.sortedText ?? "", isPresented: newSortBinding) {
            if model.newSortRequest?.canUndo == true {
                Button("Undo Last Sort") { Task { await model.undoFromDialog() } }
            }
            Button("Start a New Sort", role: .destructive) { Task { await model.confirmNewSort() } }
            Button("Cancel", role: .cancel, action: model.cancelNewSort)
        } message: {
            Text(WelcomeViewModel.newSortMessage)
        }
        .alert("Undo Last Sort", isPresented: undoBinding) {
            Button("OK", role: .cancel) { model.undoMessage = nil }
        } message: {
            Text(model.undoMessage ?? "")
        }
        .alert("Could not open the folder", isPresented: errorBinding) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)
            Text("Picnest")
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(Theme.textPrimary.color)
        }
    }

    private var dropZone: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.stack")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Theme.accent.color)
                .accessibilityHidden(true)
            Text("Drop a folder of photos here")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.textPrimary.color)
            Button("Choose Folder…") {
                isFinding = false
                isImporting = true
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .tint(Theme.accent.color)
            .disabled(model.isBusy)
            if model.isOpening {
                ProgressView().controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(isTargeted ? Theme.selection.color : Theme.surface.color))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(isTargeted ? Theme.accent.color : Theme.textSecondary.color.opacity(0.35),
                              style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
        .dropDestination(for: URL.self) { urls, _ in
            model.drop(urls)
        } isTargeted: { isTargeted = $0 }
        .disabled(model.isBusy)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Drop zone")
        .accessibilityHint("Drop a folder of photos here to open it.")
    }

    private var recentList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Folders")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary.color)
            ForEach(model.recent) { folder in
                RecentFolderCard(name: model.name(folder), path: folder.path,
                                 count: model.photoCountText(folder), sorted: model.sortedText(folder),
                                 canUndo: model.canUndoLastSort(folder),
                                 isUndoing: model.undoingID == folder.id,
                                 open: { model.openRecent(folder) },
                                 undo: { Task { await model.undoLastSort(folder) } })
                .disabled(model.isBusy)
                .contextMenu {
                    Button("Remove from Recent") { model.removeRecent(folder) }
                }
            }
            Button("Clear Recent Folders", action: model.clearRecent)
                .buttonStyle(.link)
                .controlSize(.small)
                .disabled(model.isBusy)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var missingBinding: Binding<Bool> {
        // Both alert buttons clear `missingFolder` themselves. Clearing it here too would drop the
        // folder that **Find Folder…** is looking for.
        Binding(get: { model.missingFolder != nil }, set: { _ in })
    }

    private var newSortBinding: Binding<Bool> {
        // Both alert buttons clear the request themselves.
        Binding(get: { model.newSortRequest != nil }, set: { _ in })
    }

    private var undoBinding: Binding<Bool> {
        Binding(get: { model.undoMessage != nil }, set: { if !$0 { model.undoMessage = nil } })
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
    }
}
