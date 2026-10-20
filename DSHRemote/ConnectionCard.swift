import SwiftUI

struct ConnectionCard: View {
    let loading: Bool
    let failed: Bool
    let total: Int
    let running: Int
    let openSettings: () -> Void

    private var status: String { !AppConfig.isConfigured ? "待配置" : loading ? "同步中" : failed ? "连接中断" : "已连接" }
    private var color: Color { failed ? Theme.warning : Theme.accent }

    var body: some View {
        Button(action: openSettings) {
            VStack(alignment: .leading, spacing: 23) {
                HStack(alignment: .top) {
                    Image(systemName: "laptopcomputer")
                        .font(.title2)
                        .foregroundStyle(Theme.accent)
                        .frame(width: 48, height: 48)
                        .background(Theme.accent.opacity(0.08), in: .rect(cornerRadius: 15))
                    Spacer()
                    HStack(spacing: 6) {
                        if loading { ProgressView().controlSize(.mini).tint(color) }
                        else { Circle().fill(color).frame(width: 5, height: 5) }
                        Text(status).font(.caption.weight(.medium))
                    }
                    .foregroundStyle(color)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(color.opacity(0.10), in: .capsule)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("Mac 工作站").font(.title3.weight(.semibold)).foregroundStyle(Theme.text)
                    Text(AppConfig.isConfigured ? (AppConfig.baseURL.host ?? "DSH") : "填写你的服务器与凭证")
                        .font(.caption.monospaced()).foregroundStyle(Theme.muted)
                }
                HStack(spacing: 20) {
                    Label("\(total) 个会话", systemImage: "bubble.left.and.bubble.right")
                    Label("\(running) 个运行中", systemImage: "bolt")
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right")
                }
                .font(.caption).foregroundStyle(Theme.muted)
            }
            .padding(22)
            .background {
                RoundedRectangle(cornerRadius: 25)
                    .fill(LinearGradient(colors: [Color(red: 0.075, green: 0.15, blue: 0.17), Theme.card, Color(red: 0.115, green: 0.10, blue: 0.19)], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .overlay { RoundedRectangle(cornerRadius: 25).strokeBorder(Theme.accent.opacity(0.16)) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Mac 工作站，\(status)，\(total) 个会话，\(running) 个运行中。管理连接")
    }
}
