import SwiftUI

struct LocalImageView: View {
    let data: Data
    var maxDimension = 1200
    var mode: ContentMode = .fit
    @State private var decoded: CGImage?

    var body: some View {
        Group {
            if let decoded { Image(decorative: decoded, scale: 1).resizable().aspectRatio(contentMode: mode) }
            else { ProgressView().tint(Theme.accent).frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        .task {
            let bytes = data
            let dimension = maxDimension
            let image = await Task.detached(priority: .userInitiated) { ImagePreparation.thumbnail(bytes, maxDimension: dimension) }.value
            guard !Task.isCancelled else { return }
            decoded = image
        }
    }
}
