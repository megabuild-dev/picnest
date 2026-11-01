import PicnestCore
import SwiftUI

/// The preview, and over it the crop frame with its shade, grid, and handles. The view model decides what shows.
struct EditorCanvas: View {
    @Bindable var model: PhotoEditorViewModel

    var body: some View {
        ZStack {
            Theme.canvasBackground.color
            if let image = model.previewImage {
                Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fit)
                    .overlay { GeometryReader { overlay(size: $0.size) } }
                    .padding(16)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder private func overlay(size: CGSize) -> some View {
        if model.showsCropFrame {
            CropFrame(model: model, size: size)
        } else if model.showsGrid {
            Grid3x3().stroke(Theme.cropLine.color.opacity(0.7), lineWidth: 1)
        }
    }
}

/// A 3 × 3 grid: 2 vertical and 2 horizontal lines.
private struct Grid3x3: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for i in 1...2 {
            let x = rect.minX + rect.width * Double(i) / 3, y = rect.minY + rect.height * Double(i) / 3
            path.move(to: CGPoint(x: x, y: rect.minY)); path.addLine(to: CGPoint(x: x, y: rect.maxY))
            path.move(to: CGPoint(x: rect.minX, y: y)); path.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        return path
    }
}

/// The shade, the frame, the grid, and the 8 handles. A drag converts points to 0…1 units of the preview.
private struct CropFrame: View {
    @Bindable var model: PhotoEditorViewModel
    let size: CGSize

    private var rect: CGRect {
        let c = model.edit.crop
        return CGRect(x: c.x * size.width, y: c.y * size.height, width: c.width * size.width, height: c.height * size.height)
    }

    var body: some View {
        let rect = rect
        ZStack(alignment: .topLeading) {
            Path { path in
                path.addRect(CGRect(origin: .zero, size: size))
                path.addRect(rect)
            }
            .fill(Theme.cropShade.color.opacity(Theme.cropShadeAlpha), style: FillStyle(eoFill: true))
            .allowsHitTesting(false)

            Rectangle().fill(Color.clear).contentShape(Rectangle())
                .frame(width: rect.width, height: rect.height)
                .overlay { Grid3x3().stroke(Theme.cropLine.color.opacity(0.7), lineWidth: 1) }
                .overlay { Rectangle().stroke(Theme.cropLine.color, lineWidth: 1) }
                .gesture(drag(.move))
                .offset(x: rect.minX, y: rect.minY)

            ForEach(CropHandle.allCases.filter { $0 != .move }, id: \.self) { handle in
                handleView(handle)
                    .position(position(of: handle, in: rect))
                    .gesture(drag(handle))
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .accessibilityElement()
        .accessibilityLabel(Text("Crop frame"))
        .accessibilityValue(Text(verbatim: model.outputSizeText))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: model.scaleCrop(by: 1.05)
            case .decrement: model.scaleCrop(by: 0.95)
            @unknown default: break
            }
        }
    }

    private func handleView(_ handle: CropHandle) -> some View {
        let corner = [CropHandle.topLeft, .topRight, .bottomLeft, .bottomRight].contains(handle)
        let horizontal = handle == .top || handle == .bottom
        return RoundedRectangle(cornerRadius: 2).fill(Theme.cropLine.color)
            .frame(width: corner ? 14 : (horizontal ? 28 : 6), height: corner ? 14 : (horizontal ? 6 : 28))
            .shadow(color: Theme.shadow.color.opacity(0.3), radius: 1)
            .padding(8).contentShape(Rectangle())
    }

    private func position(of handle: CropHandle, in r: CGRect) -> CGPoint {
        let x: CGFloat, y: CGFloat
        switch handle {
        case .topLeft, .left, .bottomLeft: x = r.minX
        case .top, .bottom, .move: x = r.midX
        case .topRight, .right, .bottomRight: x = r.maxX
        }
        switch handle {
        case .topLeft, .top, .topRight: y = r.minY
        case .left, .right, .move: y = r.midY
        case .bottomLeft, .bottom, .bottomRight: y = r.maxY
        }
        return CGPoint(x: x, y: y)
    }

    /// Sends the whole translation since the drag started, in 0…1 units of the preview.
    private func drag(_ handle: CropHandle) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard size.width > 0, size.height > 0 else { return }
                model.dragCrop(handle, dx: value.translation.width / size.width, dy: value.translation.height / size.height)
            }
            .onEnded { _ in model.endDrag() }
    }
}
