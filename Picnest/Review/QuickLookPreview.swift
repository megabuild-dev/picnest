import QuickLook
import SwiftUI

extension View {
    /// Shows the photo of `model.previewURL` in Quick Look, with the visible photos to step through
    /// (spec 3.3). Space and double-click set `previewURL` through `ReviewViewModel.openPreview`.
    func photoQuickLook(_ model: ReviewViewModel) -> some View {
        modifier(PhotoQuickLook(model: model))
    }
}

private struct PhotoQuickLook: ViewModifier {
    @Bindable var model: ReviewViewModel

    func body(content: Content) -> some View {
        content.quickLookPreview($model.previewURL, in: model.previewURLs)
    }
}
