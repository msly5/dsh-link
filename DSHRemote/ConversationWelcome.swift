import SwiftUI

struct ConversationWelcome: View {
    let isConfigured: Bool
    let serverLabel: String
    let onNew: () -> Void
    let onSettings: () -> Void

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 40)
                    BrandMark(size: 48).padding(.bottom, 22)
                    Text("从这里，继续。").font(.system(.largeTitle, design: .serif)).foregroundStyle(Theme.text)
                        .multilineTextAlignment(.center)
                    Text("连上你的 Mac，接着上次的思路。")
                        .font(.subheadline).foregroundStyle(Theme.muted).padding(.top, 14)
                    Button(action: onNew) {
                        Label("新建对话", systemImage: "plus")
                            .font(.body).padding(.horizontal, 24).frame(minHeight: 50)
                            .foregroundStyle(Theme.onAccent).background(Theme.accent, in: .capsule)
                    }.buttonStyle(.plain).padding(.top, 30)
                    Spacer(minLength: 50)
                    Button { onSettings() } label: {
                        HStack(spacing: 7) {
                            Image(systemName: isConfigured ? "laptopcomputer" : "link")
                            Text(serverLabel)
                            Image(systemName: "chevron.right").font(.caption)
                        }.font(.footnote).foregroundStyle(Theme.muted).frame(minHeight: 44)
                    }.buttonStyle(.plain).padding(.bottom, 20)
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: 640)
                .frame(minHeight: geometry.size.height)
                .frame(maxWidth: .infinity)
            }
        }
    }
}
