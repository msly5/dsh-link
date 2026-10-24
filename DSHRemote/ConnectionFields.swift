import SwiftUI

struct ConnectionFields: View {
    @Binding var authMode: ConnectionProfile.AuthMode
    @Binding var server: String
    @Binding var clientID: String
    @Binding var clientSecret: String
    @Binding var connectionKey: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("连接方式", selection: $authMode) {
                Text("Cloudflare Access").tag(ConnectionProfile.AuthMode.access)
                Text("Quick Tunnel").tag(ConnectionProfile.AuthMode.quickTunnel)
            }.pickerStyle(.segmented)
            Text(authMode == .access ? "使用自己的域名与 Cloudflare Service Token。" : "免域名连接，使用 Mac 窗口中的临时地址与连接密钥。")
                .font(.footnote).foregroundStyle(Theme.muted)
            Text("服务器地址").font(.subheadline.bold())
            field(authMode == .access ? "https://dsh.example.com" : "https://….trycloudflare.com", text: $server)
                .keyboardType(.URL).accessibilityLabel("服务器地址")
            if authMode == .access {
                Text("Client ID").font(.subheadline.bold())
                field("Service Token Client ID", text: $clientID).accessibilityLabel("Client ID")
                Text("Client Secret").font(.subheadline.bold())
                secureField("Service Token Client Secret", text: $clientSecret).accessibilityLabel("Client Secret")
                Text("这两项来自 Cloudflare 的 Service Token，不是 Cloudflare API Token 或 Tunnel Token。")
                    .font(.footnote).foregroundStyle(Theme.muted)
            } else {
                Text("连接密钥").font(.subheadline.bold())
                secureField("Mac 窗口中的 64 位连接密钥", text: $connectionKey).accessibilityLabel("连接密钥")
                Text("Mac 重新启动 Quick Tunnel 后，地址和密钥都会变化，请重新扫码。无需 Cloudflare 账户或域名。")
                    .font(.footnote).foregroundStyle(Theme.muted)
            }
        }
    }

    private func field(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text).font(.callout.monospaced())
            .textInputAutocapitalization(.never).autocorrectionDisabled()
            .padding(14).background(Theme.code, in: .rect(cornerRadius: 13))
    }
    private func secureField(_ placeholder: String, text: Binding<String>) -> some View {
        SecureField(placeholder, text: text).textContentType(.password)
            .textInputAutocapitalization(.never).autocorrectionDisabled()
            .padding(14).background(Theme.code, in: .rect(cornerRadius: 13))
    }
}
