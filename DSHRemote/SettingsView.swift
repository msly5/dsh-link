import SwiftUI

extension Notification.Name {
    static let dshServerChanged = Notification.Name("dsh.serverChanged")
}

struct SettingsView: View {
    let pairingURL: URL?
    init(pairingURL: URL? = nil) { self.pairingURL = pairingURL }
    @Environment(\.dismiss) private var dismiss
    @State private var server = ""
    @State private var clientID = ""
    @State private var clientSecret = ""
    @State private var testing = false
    @State private var testResult: String?
    @State private var validationError: String?
    @State private var confirmClear = false
    @State private var loaded = false
    @State private var showScanner = false
    @State private var pairingMessage: String?
    @State private var credentialServer: URL?
    @State private var pushEnabled = UserDefaults.standard.bool(forKey: "pushEnabled")
    private var previewing: Bool {
        #if DEBUG
        return DesignPreview.enabled
        #else
        return false
        #endif
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("连接你的 Mac").font(.system(.title2, design: .serif)).foregroundStyle(Theme.text)
                    Text("填写你自己的 Cloudflare Access 连接信息。凭证仅保存在本机系统钥匙串中。")
                        .font(.subheadline).foregroundStyle(Theme.muted)
                    Button("扫描 Mac 连接二维码", systemImage: "qrcode.viewfinder") { showScanner = true }
                        .buttonStyle(PrimaryButtonStyle()).disabled(previewing)
                    if let pairingMessage {
                        Label(pairingMessage, systemImage: "checkmark.circle")
                            .font(.footnote).foregroundStyle(Theme.text)
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        Text("服务器地址").font(.subheadline.bold())
                        field("https://dsh.example.com", text: $server).keyboardType(.URL)
                            .accessibilityLabel("服务器地址")
                        Text("Client ID").font(.subheadline.bold())
                        field("Service Token Client ID", text: $clientID).accessibilityLabel("Client ID")
                        Text("Client Secret").font(.subheadline.bold())
                        SecureField("Service Token Client Secret", text: $clientSecret)
                            .textContentType(.password).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .padding(14).background(Theme.code, in: .rect(cornerRadius: 13))
                            .accessibilityLabel("Client Secret")
                        Text("这两项来自 Cloudflare 的 Service Token，不是 Cloudflare API Token 或 Tunnel Token。")
                            .font(.footnote).foregroundStyle(Theme.muted)
                        if let validationError {
                            Label(validationError, systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(Theme.warning)
                        }
                        Button { Task { await test() } } label: {
                            HStack {
                                if testing { ProgressView().tint(Theme.onAccent) }
                                Text(testing ? "正在测试…" : "测试连接")
                            }
                        }.buttonStyle(PrimaryButtonStyle()).disabled(testing || previewing)
                        if let testResult { Text(testResult).font(.footnote).foregroundStyle(Theme.muted) }
                    }
                    .foregroundStyle(Theme.text).padding(.vertical, 8)
                    if PushRegistrar.isAvailable {
                        Toggle("审批与提问通知", isOn: $pushEnabled).foregroundStyle(Theme.text).disabled(previewing)
                    } else {
                        Text("此构建未启用 APNs。需要通知时，请按仓库文档配置推送签名。")
                            .font(.footnote).foregroundStyle(Theme.muted)
                    }
                    Text("测试不会保存凭证。点“保存”后应用；更换服务器时请填写对应凭证。")
                        .font(.footnote).foregroundStyle(Theme.muted)
                    Button("清除已保存的连接", role: .destructive) { confirmClear = true }
                        .disabled(previewing)
                    Text("dsh link · 非官方 DSH 远程客户端").font(.caption).foregroundStyle(Theme.muted)
                }.padding(Theme.Space.screen).frame(maxWidth: 680).frame(maxWidth: .infinity)
            }
            .background(Theme.bg)
            .navigationTitle("连接设置").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { save() }.bold().disabled(previewing) }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                guard !previewing else { return }
                do {
                    if let profile = try CredentialStore.shared.load() {
                        credentialServer = profile.serverURL
                        server = profile.serverURL.absoluteString
                        clientID = profile.clientID
                        clientSecret = profile.clientSecret
                    }
                } catch { validationError = error.localizedDescription }
                if let pairingURL { importPairing(pairingURL.absoluteString) }
            }
            .onChange(of: pairingURL) { _, url in
                if let url { importPairing(url.absoluteString) }
            }
            .sheet(isPresented: $showScanner) { QRCodeScannerView(onScan: importPairing) }
            .onChange(of: server) { _, _ in
                clearResult()
                if let credentialServer, AppConfig.validatedServerURL(server) != credentialServer {
                    clientID = ""; clientSecret = ""; self.credentialServer = nil
                    pairingMessage = nil
                }
            }
            .onChange(of: clientID) { _, _ in clearResult() }
            .onChange(of: clientSecret) { _, _ in clearResult() }
            .confirmationDialog("清除连接及钥匙串中的凭证？", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("清除连接", role: .destructive) {
                    do {
                        try CredentialStore.shared.delete()
                        UserDefaults.standard.set(false, forKey: "pushEnabled")
                        UIApplication.shared.unregisterForRemoteNotifications()
                        NotificationCenter.default.post(name: .dshServerChanged, object: nil)
                        dismiss()
                    } catch { validationError = error.localizedDescription }
                }
            }
        }.tint(Theme.accent)
    }

    private func field(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text).font(.callout.monospaced())
            .textInputAutocapitalization(.never).autocorrectionDisabled()
            .padding(14).background(Theme.code, in: .rect(cornerRadius: 13))
    }
    private func clearResult() { validationError = nil; testResult = nil }
    private func importPairing(_ value: String) {
        do {
            let invitation = try PairingInvitation(scannedValue: value)
            let profile = invitation.profile
            credentialServer = profile.serverURL
            server = profile.serverURL.absoluteString
            clientID = profile.clientID
            clientSecret = profile.clientSecret
            clearResult()
            pairingMessage = "已填入 \(profile.serverURL.host ?? "Mac") 的连接信息。确认服务器后，点“保存”即可连接。"
        } catch { validationError = error.localizedDescription; pairingMessage = nil }
    }
    private func candidate() throws -> ConnectionProfile {
        try ConnectionProfile(server: server, clientID: clientID, clientSecret: clientSecret)
    }
    private func save() {
        do {
            try CredentialStore.shared.save(candidate())
            UserDefaults.standard.removeObject(forKey: "serverURL")
            UserDefaults.standard.set(pushEnabled, forKey: "pushEnabled")
            NotificationCenter.default.post(name: .dshServerChanged, object: nil)
            if pushEnabled { PushRegistrar.enableNotifications() }
            else { UIApplication.shared.unregisterForRemoteNotifications() }
            dismiss()
        } catch { validationError = error.localizedDescription }
    }
    private func test() async {
        guard !testing else { return }
        let profile: ConnectionProfile
        do { profile = try candidate() } catch { validationError = error.localizedDescription; return }
        testing = true
        testResult = nil
        defer { testing = false }
        let start = Date.now
        do {
            let sessions = try await RemoteClient.shared.listSessions(baseURL: profile.serverURL, credentials: profile)
            guard (try? candidate()) == profile else { return }
            testResult = "连接成功：\(sessions.count) 个会话，\(Int(Date.now.timeIntervalSince(start) * 1_000)) ms"
        } catch {
            guard (try? candidate()) == profile else { return }
            testResult = "连接失败：\(error.localizedDescription)"
        }
    }
}
