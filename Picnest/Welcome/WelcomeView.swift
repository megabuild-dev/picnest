import PicnestCore
import SwiftUI
import UniformTypeIdentifiers

/// Welcome screen (spec 3.1): drop zone, **Choose Folder…**, recent folders.
struct WelcomeView: View {
    @Bindable var model: WelcomeViewModel
    @State private var isImporting = false
    @State private var isTargeted = false
    /// True when the importer finds a missing recent folder, not a new one.
    @State private var isFinding = false

    var body: some View {
        VStack(spacing: 24) {
            dropZone
            if !model.recent.isEmpty { recentList }
            Label("Everything runs on this Mac. No photos leave your computer.", systemImage: "lock.shield")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: 560)
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
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

    private var dropZone: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.stack")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tint)
            Text("Drop a folder of photos here")
                .font(.title3.weight(.semibold))
            Button("Choose Folder…") {
                isFinding = false
                isImporting = true
            }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
            if model.isOpening {
                ProgressView().controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isTargeted ? AnyShapeStyle(.tint.opacity(0.12)) : AnyShapeStyle(.quinary)))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(isTargeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator),
                              style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
        .dropDestination(for: URL.self) { urls, _ in
            model.drop(urls)
        } isTargeted: { isTargeted = $0 }
        .disabled(model.isBusy)
    }

    private var recentList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("RECENT")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            VStack(spacing: 0) {
                ForEach(model.recent) { folder in
                    RecentFolderRow(name: model.name(folder), path: folder.path,
                                    count: model.photoCountText(folder), sorted: model.sortedText(folder),
                                    canUndo: model.canUndoLastSort(folder),
                                    isUndoing: model.undoingID == folder.id,
                                    open: { model.openRecent(folder) },
                                    undo: { Task { await model.undoLastSort(folder) } })
                    .disabled(model.isBusy)
                    .contextMenu {
                        Button("Remove from Recent") { model.removeRecent(folder) }
                    }
                    if folder.id != model.recent.last?.id { Divider().padding(.leading, 48) }
                }
            }
            .background(RoundedRectangle(cornerRadius: 12).fill(.background.secondary))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
            Button("Clear Recent Folders", action: model.clearRecent)
                .buttonStyle(.link)
                .controlSize(.small)
                .padding(.leading, 4)
                .disabled(model.isBusy)
        }
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

private struct RecentFolderRow: View {
    let name: String
    let path: String
    let count: String
    /// "Sorted <date>", or nil.
    let sorted: String?
    let canUndo: Bool
    let isUndoing: Bool
    let open: () -> Void
    let undo: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: open) { label }
                .buttonStyle(.plain)
            if isUndoing {
                ProgressView().controlSize(.small)
            } else if canUndo {
                Button("Undo Last Sort", action: undo)
                    .controlSize(.small)
                    .help("Put the photos of the last sort back")
            }
        }
        .padding(.trailing, canUndo || isUndoing ? 10 : 0)
    }

    private var label: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .foregroundStyle(.tint)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 6).fill(.tint.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text(name).lineLimit(1)
                Text(path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(count).font(.callout).foregroundStyle(.secondary).monospacedDigit()
                if let sorted {
                    Text(sorted).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}
