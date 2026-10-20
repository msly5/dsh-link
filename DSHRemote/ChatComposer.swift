import SwiftUI

struct ChatComposer: View {
    @ObservedObject var stream: ChatStream
    @Binding var input: String
    @Binding var images: [ImageAttachment]
    @Binding var loadingImages: Bool
    @Binding var imageError: String?
    let sending: Bool
    let focus: FocusState<Bool>.Binding
    let onSend: () -> Void
    let onModels: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var canSend: Bool {
        stream.connected && !sending && !stream.cancelling
            && (stream.running || (!loadingImages && (!input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !images.isEmpty)))
    }

    private var currentPermission: String { stream.sessionPermission ?? stream.permissionPreset }

    private var modelText: String {
        let model = stream.sessionModel.isEmpty ? stream.modelLabel : stream.sessionModel
        let name = model.replacingOccurrences(of: "deepseek-", with: "")
        return name.isEmpty ? "选择模型" : name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !images.isEmpty { PendingImageStrip(images: $images, disabled: sending) }
            HStack(alignment: .bottom, spacing: 10) {
                PhotoAttachmentPicker(images: $images, loading: $loadingImages, error: $imageError,
                                      limits: stream.imageLimits, disabled: sending)
                TextField("消息内容", text: $input, prompt: Text("告诉 DSH 下一步做什么…").foregroundStyle(Theme.muted), axis: .vertical)
                    .focused(focus)
                    .font(.body).foregroundStyle(Theme.text)
                    .lineLimit(2...6)
                    .disabled(sending)
                    .padding(.horizontal, 3).padding(.top, 3)
                    .accessibilityLabel("消息内容")
            }
            if let imageError { Text(imageError).font(.caption).foregroundStyle(Theme.warning) }
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 12) {
                    HStack { modelMenu; Spacer(minLength: 6); permissionMenu }
                    HStack { usage; Spacer(); sendButton }
                }
            } else {
                HStack(spacing: 10) {
                    modelMenu
                    permissionMenu
                    Spacer(minLength: 0)
                    usage
                    sendButton
                }
            }
        }
        .padding(14)
        .background(Theme.card, in: .rect(cornerRadius: 23))
        .overlay { RoundedRectangle(cornerRadius: 23).strokeBorder(focus.wrappedValue ? Theme.accent.opacity(0.45) : Theme.stroke) }
        .shadow(color: Color.black.opacity(0.18), radius: 18, y: 5)
        .animation(.easeOut(duration: 0.2), value: focus.wrappedValue)
    }

    private var modelMenu: some View {
        Menu {
            ForEach(stream.modelGroups) { group in
                Menu(group.name) {
                    ForEach(group.models) { model in
                        let efforts = model.reasoning?.efforts ?? []
                        if efforts.isEmpty {
                            Button(model.name) { Task { await stream.selectModel(provider: group.id, model: model.id, effort: nil) } }
                        } else {
                            Menu(model.name) {
                                ForEach(efforts) { effort in
                                    Button(effort.name) { Task { await stream.selectModel(provider: group.id, model: model.id, effort: effort.id) } }
                                }
                            }
                        }
                    }
                }
            }
            Divider()
            Button("模型与思考档位…", action: onModels)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "sparkle").foregroundStyle(Theme.accent)
                Text(stream.sessionEffort.isEmpty ? modelText : "\(modelText) · \(stream.sessionEffort)").lineLimit(1).truncationMode(.middle)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
            .font(.caption.weight(.medium)).foregroundStyle(Theme.text)
            .frame(minHeight: 44)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("模型：\(modelText)，思考档位：\(stream.sessionEffort.isEmpty ? "默认" : stream.sessionEffort)")
        }
        .disabled(stream.updatingSelection || !stream.connected)
    }

    private var permissionMenu: some View {
        Menu {
            ForEach(stream.permissionOptions) { option in
                Button {
                    Task { await stream.setPermission(option.value) }
                } label: {
                    if option.value == currentPermission {
                        Label(permissionLabel(option.value), systemImage: "checkmark")
                    } else { Text(permissionLabel(option.value)) }
                }
            }
        } label: {
            Image(systemName: currentPermission == "danger-full-access" ? "shield.lefthalf.filled" : "lock.shield")
                .font(.body).foregroundStyle(currentPermission == "danger-full-access" ? Theme.warning : Theme.muted)
                .frame(width: 44, height: 44)
                .background(Theme.faint, in: .rect(cornerRadius: 12))
                .accessibilityLabel("访问权限：\(permissionLabel(currentPermission))")
        }
        .disabled(stream.updatingSelection || stream.permissionOptions.isEmpty || !stream.connected)
    }

    @ViewBuilder
    private var usage: some View {
        if let ratio = stream.usageRatio { ContextGauge(ratio: ratio) }
    }

    private var sendButton: some View {
        Button {
            if stream.running { Task { await stream.cancel() } }
            else { onSend() }
        } label: {
            ZStack {
                if sending || stream.cancelling { ProgressView().tint(Theme.onAccent) }
                else { Image(systemName: stream.running ? "stop.fill" : "arrow.up").font(.body.weight(.bold)) }
            }
            .foregroundStyle(canSend ? Theme.onAccent : Theme.muted)
            .frame(width: 44, height: 44)
            .background(canSend ? (stream.running ? Theme.warning : Theme.accent) : Theme.raised, in: .rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
        .accessibilityLabel(stream.running ? "停止生成" : "发送消息")
    }

    private func permissionLabel(_ value: String) -> String {
        switch value {
        case "read-only": "只读"
        case "workspace-write": "工作区可写"
        case "danger-full-access": "完全权限"
        default: value
        }
    }
}
