#if DEBUG
import SwiftUI

/// Deterministic, non-personal fixtures for visual QA. Never enabled in Release builds.
enum DesignPreview {
    static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("--ui-preview") }
    static var colorScheme: ColorScheme? {
        if ProcessInfo.processInfo.arguments.contains("--preview-dark") { return .dark }
        if ProcessInfo.processInfo.arguments.contains("--preview-light") { return .light }
        return nil
    }
    static let sessions: [SessionSummary] = [
        "手机与电脑的同步方案", "客户端界面优化", "整理项目的下一步计划", "图片发送与预览", "你好，DSH", "连接与部署笔记"
    ].enumerated().map { index, title in
        SessionSummary(sessionId: "preview-\(index)", updatedAt: Date.now.addingTimeInterval(Double(-index * 1800)).timeIntervalSince1970 * 1000,
                       running: index == 2, blank: false, cwd: "/workspace/dsh-link",
                       projections: Projections(values: ProjectionValues(title: title, contextPressure: nil, permissions: nil, modelSelection: nil, imageLimits: nil)))
    }
    static let workspaces = [
        DesktopWorkspace(workspaceId: "preview-workspace", path: "/workspace/dsh-link", title: "dsh link", sessionIds: sessions.prefix(4).map(\.id)),
        DesktopWorkspace(workspaceId: "preview-notes", path: "/workspace/notes", title: "随手记", sessionIds: sessions.suffix(2).map(\.id))
    ]
    static let archivedSessionIds = ["preview-5"]
    static let messages: [ChatMessage] = [
        ChatMessage(id: "preview-user", seq: 1, role: .user, text: "帮我整理一下手机和电脑的同步方案。"),
        ChatMessage(id: "preview-thinking", seq: 2, role: .tool, text: "先核对桌面工作区、会话标识和历史读取方式，再整理切换设备时的行为。", activity: ExecutionActivity(kind: .reasoning, phase: .completed)),
        ChatMessage(id: "preview-read", seq: 3, role: .tool, text: "已读取工作区与会话配置。", activity: ExecutionActivity(kind: .tool, name: "read", arguments: "{\"path\":\"/workspace/docs/sync.md\",\"description\":\"核对会话同步配置\"}", phase: .completed)),
        ChatMessage(id: "preview-assistant", seq: 4, role: .assistant, text: """
        可以。两端连接同一个 Mac，就能继续同一段对话。

        ### 让切换更自然

        - **同一个工作区**：新对话同步到桌面项目。
        - **同一份记录**：消息和进度随时同步。
        
        | 内容 | Mac | iPhone |
        | --- | --- | --- |
        | 对话记录 | 完整记录 | 同步查看 |
        | 工具执行 | 本地执行 | 查看与确认 |
        | 图片 | 支持 | 支持上传 |

        从侧栏打开已有对话，就能接着工作。
        """
        )
    ]
    static let catalog = ModelCatalog(default: ModelCatalogSelection(provider: "deepseek", model: "deepseek-chat", reasoningEffort: nil),
                                     groups: [ModelProviderGroup(id: "deepseek", name: "DeepSeek", models: [
                                        ModelCatalogModel(id: "deepseek-chat", name: "DeepSeek", description: "适合日常对话与项目工作", reasoning: nil)
                                     ])], failures: nil)
}
#endif
