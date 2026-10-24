import SwiftUI

struct ConnectionCard: View {
    let loading: Bool
    let failed: Bool
    let total: Int
    let running: Int
    let openSettings: () -> Void
    private var status: String { !AppConfig.isConfigured ? "待配置" : loading ? "同步中" : failed ? "连接中断" : "已连接" }
    var body: some View {
        Button(action: openSettings) {
            HStack(spacing: 12) {
                Image(systemName: "laptopcomputer").foregroundStyle(Theme.muted)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mac · " + status).font(.subheadline).foregroundStyle(Theme.text)
                    Text(AppConfig.isConfigured ? AppConfig.baseURL.host ?? "Mac" : "填写你的服务器与凭证")
                        .font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.muted)
            }.padding(.vertical, 12).contentShape(.rect)
        }.buttonStyle(.plain)
    }
}
