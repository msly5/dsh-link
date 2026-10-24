import SwiftUI

struct NewSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var path = ""
    @State private var workspaces: [DesktopWorkspace] = []
    @State private var selection = ""
    @State private var loading = true
    @State private var creationId = "session-" + UUID().uuidString.lowercased()
    @State private var creating = false
    @State private var errorText: String?

    var preferredSessionId: String?
    let onCreated: (String) -> Void
    private let serverURL = AppConfig.baseURL

    private var selectedWorkspace: DesktopWorkspace? { workspaces.first { $0.id == selection } }
    private var canCreate: Bool {
        !loading && !creating && (selectedWorkspace != nil || path.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("/"))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("开始新的对话").font(.system(.title2, design: .serif)).foregroundStyle(Theme.text)
                            Text("在 Mac 上创建会话，随时从手机继续。")
                                .font(.subheadline).foregroundStyle(Theme.muted).lineSpacing(4)
                        }
                    }
                    .padding(.top, 12)
                    VStack(alignment: .leading, spacing: 14) {
                        Label("桌面工作区", systemImage: "folder")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                        if loading {
                            ProgressView("正在读取 Mac 工作区…").tint(Theme.accent)
                                .foregroundStyle(Theme.muted)
                        } else {
                            Picker("桌面工作区", selection: $selection) {
                                ForEach(workspaces) { workspace in
                                    Text(workspace.displayName).tag(workspace.id)
                                }
                                Text("其他 Mac 目录…").tag("")
                            }
                            .pickerStyle(.menu).tint(Theme.accent).disabled(creating)
                        }
                        if let workspace = selectedWorkspace {
                            Text(workspace.path).font(.callout.monospaced())
                                .foregroundStyle(Theme.muted).textSelection(.enabled)
                        } else if !loading {
                            TextField("Mac 工作目录", text: $path, prompt: Text("/Users/你/项目").foregroundStyle(Theme.muted), axis: .vertical)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .font(.callout.monospaced()).foregroundStyle(Theme.text)
                            .lineLimit(1...4)
                            .padding(15)
                            .background(Theme.code, in: .rect(cornerRadius: 13))
                            .overlay { RoundedRectangle(cornerRadius: 13).strokeBorder(Theme.stroke) }
                            .disabled(creating)
                        }
                        Text(selection.isEmpty ? "填写 Mac 上已有目录，将同步添加为桌面工作区。" : "会话会出现在桌面端的同名工作区，电脑和手机共用聊天记录。")
                            .font(.footnote).foregroundStyle(Theme.muted)
                    }
                    .padding(.vertical, 12)
                    if let errorText {
                        Label(errorText, systemImage: "exclamationmark.circle")
                            .font(.footnote).foregroundStyle(Theme.warning)
                        if workspaces.isEmpty && !loading {
                            Button("重新读取工作区") { Task { await loadWorkspaces() } }
                                .tint(Theme.accent).disabled(creating)
                        }
                    }
                }
                .padding(.horizontal, Theme.Space.screen).padding(.bottom, 24)
                .frame(maxWidth: 680).frame(maxWidth: .infinity)
            }
            .background(Theme.bg)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button { Task { await create() } } label: {
                    HStack(spacing: 9) {
                        if creating { ProgressView().tint(Theme.onAccent) }
                        else { Image(systemName: "plus") }
                        Text(creating ? "正在创建…" : "开始对话")
                    }
                }
                .buttonStyle(PrimaryButtonStyle()).disabled(!canCreate)
                .padding(.horizontal, Theme.Space.screen).padding(.top, 12).padding(.bottom, 12)
                .background(Theme.bg)
            }
            .interactiveDismissDisabled(creating)
            .navigationTitle("新建对话").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(creating) }
            }
        }
        .tint(Theme.accent)
        .task { await loadWorkspaces() }
        .onChange(of: selection) { _, _ in resetCreationId() }
        .onChange(of: path) { _, _ in resetCreationId() }
    }

    private func resetCreationId() { creationId = "session-" + UUID().uuidString.lowercased() }

    private func loadWorkspaces() async {
        #if DEBUG
        if DesignPreview.enabled { workspaces = DesignPreview.workspaces; selection = workspaces.first?.id ?? ""; loading = false; return }
        #endif
        loading = true
        errorText = nil
        defer { loading = false }
        do {
            let snapshot = try await RemoteClient.shared.workspaceSnapshot(baseURL: serverURL)
            guard !Task.isCancelled else { return }
            workspaces = snapshot.items
            let saved = UserDefaults.standard.string(forKey: "newSessionWorkspace." + serverURL.absoluteString)
            selection = snapshot.preferredWorkspace(sessionId: preferredSessionId, savedId: saved)?.id ?? ""
        } catch {
            guard !Task.isCancelled else { return }
            errorText = error.localizedDescription
        }
    }

    private func create() async {
        #if DEBUG
        if DesignPreview.enabled { onCreated(DesignPreview.sessions[0].id); dismiss(); return }
        #endif
        guard !creating else { return }
        errorText = nil
        creating = true
        defer { creating = false }
        do {
            let workspace: DesktopWorkspace
            if let selectedWorkspace { workspace = selectedWorkspace }
            else {
                let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.hasPrefix("/") else { throw RemoteError(message: "请填写 Mac 上的完整目录路径") }
                workspace = try await RemoteClient.shared.resolveWorkspace(path: trimmed, baseURL: serverURL)
            }
            let id = try await RemoteClient.shared.createSession(workspaceId: workspace.id, sessionId: creationId, baseURL: serverURL)
            UserDefaults.standard.set(workspace.id, forKey: "newSessionWorkspace." + serverURL.absoluteString)
            onCreated(id)
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}
