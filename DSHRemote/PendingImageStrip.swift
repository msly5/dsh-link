import SwiftUI

struct PendingImageStrip: View {
    @Binding var images: [ImageAttachment]
    let disabled: Bool
    @State private var preview: ImageAttachment?

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                ForEach(images) { image in
                    Button { preview = image } label: {
                        LocalImageView(data: image.preview, maxDimension: 240, mode: .fill)
                            .frame(width: 74, height: 74).clipped()
                            .clipShape(.rect(cornerRadius: 12))
                    }
                    .buttonStyle(.plain).accessibilityLabel("预览待发送图片")
                    .overlay(alignment: .topTrailing) {
                        Button("移除图片", systemImage: "xmark.circle.fill") { images.removeAll { $0.id == image.id } }
                            .labelStyle(.iconOnly).font(.title3)
                            .foregroundStyle(.white).shadow(color: .black.opacity(0.8), radius: 3)
                            .frame(width: 44, height: 44).offset(x: 8, y: -8).disabled(disabled)
                    }
                }
            }
            .padding(.top, 6).padding(.trailing, 8)
        }
        .scrollIndicators(.hidden)
        .fullScreenCover(item: $preview) { ImagePreview(data: $0.data) }
    }
}
