import PhotosUI
import SwiftUI

struct PhotoAttachmentPicker: View {
    @Binding var images: [ImageAttachment]
    @Binding var loading: Bool
    @Binding var error: String?
    let limits: ImageLimits
    let disabled: Bool
    @State private var selected: [PhotosPickerItem] = []
    @State private var loadTask: Task<Void, Never>?

    var body: some View {
        PhotosPicker(selection: $selected, maxSelectionCount: max(1, limits.selectionLimit - images.count),
                     matching: .images, preferredItemEncoding: .current) {
            Group {
                if loading { ProgressView().tint(Theme.accent) }
                else { Image(systemName: "photo.badge.plus").font(.body) }
            }
            .foregroundStyle(Theme.accent)
            .frame(width: 44, height: 44)
            .background(Theme.faint, in: .rect(cornerRadius: 12))
        }
        .disabled(disabled || loading || images.count >= limits.selectionLimit)
        .accessibilityLabel(loading ? "正在读取图片" : "添加图片")
        .onChange(of: selected) { _, items in
            guard !items.isEmpty else { return }
            loadTask?.cancel()
            loading = true
            error = nil
            let limit = limits
            let remaining = max(0, limits.selectionLimit - images.count)
            loadTask = Task {
                defer { loading = false; selected = [] }
                for item in items.prefix(remaining) {
                    do {
                        guard let data = try await item.loadTransferable(type: Data.self) else {
                            throw RemoteError(message: "无法读取所选图片，请确认照片已经从 iCloud 下载。")
                        }
                        let prepared = try await Task.detached(priority: .userInitiated) {
                            try ImagePreparation.prepare(data, limits: limit)
                        }.value
                        try Task.checkCancellation()
                        images.append(prepared)
                    } catch is CancellationError { return }
                    catch let failure { error = failure.localizedDescription }
                }
            }
        }
        .onDisappear { loadTask?.cancel() }
    }
}
