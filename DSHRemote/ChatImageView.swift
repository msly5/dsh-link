import SwiftUI

struct ChatImageView: View {
    let image: ChatImage
    let sessionId: String
    let serverURL: URL
    @State private var data: Data?
    @State private var failed = false
    @State private var retry = 0
    @State private var preview = false

    var body: some View {
        Button {
            if data != nil { preview = true }
            else if failed { retry += 1 }
        } label: {
            Group {
                if let data { LocalImageView(data: data).frame(maxWidth: 240, maxHeight: 220) }
                else if failed {
                    Label("图片加载失败，点击重试", systemImage: "arrow.clockwise")
                        .font(.caption).foregroundStyle(Theme.muted).frame(width: 220, height: 100)
                } else {
                    ProgressView().tint(Theme.accent).frame(width: 180, height: 120)
                }
            }
            .background(Theme.code, in: .rect(cornerRadius: 13))
            .clipShape(.rect(cornerRadius: 13))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(failed ? "重新加载图片" : "查看图片：\(image.name ?? "附件")")
        .task(id: retry) {
            failed = false
            do {
                let bytes = try await ImageAttachmentStore.shared.data(server: serverURL, sessionId: sessionId, image: image)
                guard !Task.isCancelled else { return }
                data = bytes
            } catch {
                guard !Task.isCancelled else { return }
                failed = true
            }
        }
        .fullScreenCover(isPresented: $preview) { if let data { ImagePreview(data: data) } }
    }
}
