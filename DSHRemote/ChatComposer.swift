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
    private var suggestionQuery: String? { focus.wrappedValue && !sending ? SlashCommand.suggestionQuery(in: input) : nil }

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
        VStack(alignment: .leading, spacing: 6) {
            if !images.isEmpty { PendingImageStrip(images: $images, disabled: sending) }
            if let query = suggestionQuery {
                CommandSuggestionsView(commands: stream.commands, query: query, loading: stream.loadingCommands,
                                       error: stream.commandsError, refresh: { Task { await stream.loadCommands(force: true) } }) { command in
                    input = "/\(command.name) "
                    focus.wrappedValue = true
                }
            }
            TextField("消息内容", text: $input, prompt: Text("回复 DSH…").foregroundStyle(Theme.muted), axis: .vertical)
                .focused(focus).font(.body).foregroundStyle(Theme.text)
                .lineLimit(1...6).disabled(sending)
                .padding(.horizontal, 6).padding(.top, 7).padding(.bottom, 4)
                .accessibilityLabel("消息内容")
            if let imageError { Text(imageError).font(.footnote).foregroundStyle(Theme.warning) }
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 5) {
                    HStack { attachmentButton; permissionMenu; Spacer(); usage }
                    HStack { modelMenu; Spacer(minLength: 6); sendButton }
                }
            } else {
                HStack(spacing: 0) {
                    attachmentButton
                    permissionMenu
                    usage.padding(.leading, 4)
                    Spacer(minLength: 4)
                    modelMenu
                    sendButton.padding(.leading, 8)
                }
            }
        }
        .padding(10)
        .background(Theme.card, in: .rect(cornerRadius: 23))
        .overlay { RoundedRectangle(cornerRadius: 23).strokeBorder(focus.wrappedValue ? Theme.muted.opacity(0.5) : Theme.stroke, lineWidth: 0.9) }
        .task(id: suggestionQuery != nil) {
            if suggestionQuery != nil { await stream.loadCommands() }
        }
        .onChange(of: stream.connected) { _, connected in
            if connected && suggestionQuery != nil { Task { await stream.loadCommands(force: true) } }
        }
    }

    private var attachmentButton: some View {
        PhotoAttachmentPicker(images: $images, loading: $loadingImages, error: $imageError,
                              limits: stream.imageLimits, disabled: sending)
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
                Text(stream.sessionEffort.isEmpty ? modelText : "\(modelText) · \(stream.sessionEffort)")
                    .lineLimit(1).truncationMode(.middle)
                Image(systemName: "chevron.down").font(.caption2)
            }
            .font(.footnote).foregroundStyle(Theme.text).frame(minHeight: 44)
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
                    if option.value == currentPermission { Label(permissionLabel(option.value), systemImage: "checkmark") }
                    else { Text(permissionLabel(option.value)) }
                }
            }
        } label: {
            Image(systemName: currentPermission == "danger-full-access" ? "shield.lefthalf.filled" : "lock.shield")
                .font(.callout).foregroundStyle(currentPermission == "danger-full-access" ? Theme.warning : Theme.muted)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .frame(width: 44, height: 44)
                .accessibilityLabel("访问权限：\(permissionLabel(currentPermission))")
        }
        .disabled(stream.updatingSelection || stream.permissionOptions.isEmpty || !stream.connected)
    }

    @ViewBuilder private var usage: some View {
        if let ratio = stream.usageRatio { ContextGauge(ratio: ratio) }
    }
    private var sendButton: some View {
        Button {
            if stream.running { Task { await stream.cancel() } }
            else { onSend() }
        } label: {
            ZStack {
                if sending || stream.cancelling { ProgressView().tint(Theme.onAccent) }
                else {
                    Image(systemName: stream.running ? "stop.fill" : "arrow.up").font(.body.weight(.medium))
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                }
            }
            .foregroundStyle(canSend ? Theme.onAccent : Theme.muted)
            .frame(width: 44, height: 44)
            .background(canSend ? Theme.accent : Theme.code, in: .circle)
        }
        .buttonStyle(.plain).disabled(!canSend)
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
