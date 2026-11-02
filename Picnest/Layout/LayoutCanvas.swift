import PicnestCore
import SwiftUI

/// The page on the editor ground, with the cell overlays and the drop target. The scale, the cells, and the
/// drop index come from the view model: this view does no layout math besides points times scale.
struct LayoutCanvas: View {
    @Bindable var model: LayoutEditorViewModel
    private static let inset: CGFloat = 24

    var body: some View {
        GeometryReader { geometry in
            ScrollView([.horizontal, .vertical]) {
                page
                    .padding(Self.inset)
                    .frame(minWidth: geometry.size.width, minHeight: geometry.size.height)
            }
            .onGeometryChange(for: CGSize.self, of: \.size) { size in
                model.canvasWidth = max(size.width - 2 * Self.inset, 1)
                model.canvasHeight = max(size.height - 2 * Self.inset, 1)
            }
        }
        .background(Theme.canvasBackground.color)
    }

    private var page: some View {
        let scale = model.scale, size = model.currentPage.size
        return ZStack(alignment: .topLeading) {
            if let image = model.pageImage {
                Image(decorative: image, scale: 1).resizable()
            } else {
                Rectangle().fill(model.document.background.color).overlay { ProgressView().controlSize(.small) }
            }
            Color.clear.contentShape(Rectangle()).onTapGesture { model.selectCell(nil) }
            if !model.isPreviewing {
                ForEach(model.currentPage.cells, id: \.index) { LayoutCellOverlay(model: model, cell: $0, scale: scale) }
            }
        }
        .frame(width: size.width * scale, height: size.height * scale)
        .shadow(color: Theme.pageShadow.color.opacity(Theme.pageShadowAlpha), radius: 12, y: 4)
        .dropDestination(for: MediaIDs.self) { items, location in
            let point = CGPoint(x: location.x / scale, y: location.y / scale)
            model.drop(items.flatMap(\.ids), onCell: model.cell(atPagePoint: point))
            return true
        }
    }
}

/// The outline, the drag, and the accessibility element of 1 cell.
private struct LayoutCellOverlay: View {
    let model: LayoutEditorViewModel
    let cell: LayoutCell
    let scale: Double

    var body: some View {
        let frame = cell.frame
        let selected = model.selectedCell == cell.index
        Rectangle().fill(Color.clear).contentShape(Rectangle())
            .overlay { outline(selected: selected) }
            .frame(width: frame.width * scale, height: frame.height * scale)
            .offset(x: frame.x * scale, y: frame.y * scale)
            .onTapGesture { model.selectCell(cell.index) }
            .modifier(CellDrag(id: cell.mediaID))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: model.cellLabel(for: cell)))
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            .modifier(CellActions(model: model, cell: cell))
    }

    @ViewBuilder private func outline(selected: Bool) -> some View {
        if selected {
            Rectangle().strokeBorder(Theme.cellOutline.color, lineWidth: 2)
        } else if cell.mediaID == nil {
            Rectangle().strokeBorder(Theme.cellOutline.color.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        } else {
            Rectangle().strokeBorder(Theme.shadow.color.opacity(0.15), lineWidth: 1)
        }
    }
}

/// A cell with a photo drags that photo. Dropped on another cell, it swaps.
private struct CellDrag: ViewModifier {
    let id: MediaID?

    @ViewBuilder func body(content: Content) -> some View {
        if let id { content.draggable(MediaIDs(ids: [id])) } else { content }
    }
}

/// **Move Earlier**, **Move Later**, and **Remove from Layout** for a cell with a photo.
private struct CellActions: ViewModifier {
    let model: LayoutEditorViewModel
    let cell: LayoutCell

    @ViewBuilder func body(content: Content) -> some View {
        if cell.mediaID != nil {
            content
                .accessibilityAction(named: Text("Move Earlier")) { model.movePhoto(at: cell.index, by: -1) }
                .accessibilityAction(named: Text("Move Later")) { model.movePhoto(at: cell.index, by: 1) }
                .accessibilityAction(named: Text("Remove from Layout")) { model.removePhoto(at: cell.index) }
        } else {
            content
        }
    }
}
