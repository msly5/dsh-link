import AppKit
import CoreImage.CIFilterBuiltins
import SwiftUI
import Vision

struct Invitation: Decodable {
    let link: String
    let server: String
    let expiresAt: Double
}

struct PairingWindow: View {
    let image: NSImage
    let brand: NSImage
    let server: String
    let expiresAt: Date
    var body: some View {
        VStack(spacing: 18) {
            Image(nsImage: brand).resizable().scaledToFit().frame(width: 48, height: 48).accessibilityHidden(true)
            Text("dsh link").font(.system(.title, design: .serif).bold())
            Text("用 iPhone 扫码连接你的 Mac").font(.title3)
            Image(nsImage: image).interpolation(.none).resizable().scaledToFit()
                .frame(width: 380, height: 380).padding(12).background(.white)
                .accessibilityLabel("连接二维码，包含私密凭证")
            Text(server).font(.callout.monospaced()).lineLimit(2).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text("\(max(0, Int(expiresAt.timeIntervalSince(context.date)))) 秒后关闭 · 请勿截图或分享")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Text("App → 连接设置 → 扫描 Mac 连接二维码\n识别后确认服务器，点保存即可。")
                .font(.callout).multilineTextAlignment(.center).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("关闭二维码") { NSApplication.shared.terminate(nil) }.keyboardShortcut(.cancelAction)
        }.padding(28).frame(width: 480).background(Color(nsColor: .windowBackgroundColor))
    }
}

final class WindowDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

do {
    let input = FileHandle.standardInput.readDataToEndOfFile()
    guard input.count <= 8192 else { throw CocoaError(.fileReadCorruptFile) }
    let invitation = try JSONDecoder().decode(Invitation.self, from: input)
    let expiry = Date(timeIntervalSince1970: invitation.expiresAt)
    guard invitation.link.hasPrefix("dshremote://configure?data="), invitation.link.utf8.count <= 2000,
          expiry > .now, expiry.timeIntervalSinceNow <= 360 else { throw CocoaError(.fileReadCorruptFile) }
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(invitation.link.utf8)
    filter.correctionLevel = "M"
    guard let code = filter.outputImage else { throw CocoaError(.fileReadCorruptFile) }
    let extent = code.extent.insetBy(dx: -4, dy: -4)
    let bordered = code.composited(over: CIImage(color: .white).cropped(to: extent))
    let enlarged = bordered.transformed(by: CGAffineTransform(scaleX: 6, y: 6))
    guard let cgImage = CIContext().createCGImage(enlarged, from: enlarged.extent) else { throw CocoaError(.fileReadCorruptFile) }
    if CommandLine.arguments.contains("--check") {
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
        guard request.results?.contains(where: { $0.payloadStringValue == invitation.link }) == true else {
            throw CocoaError(.fileReadCorruptFile)
        }
        print("PASS: QR generated and decoded locally. No connection credentials displayed.")
    } else {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = WindowDelegate()
        app.delegate = delegate
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let brand = NSImage(contentsOf: root.appendingPathComponent("DSHRemote/Assets.xcassets/WhaleMark.imageset/WhaleMark.png")) ?? NSImage()
        app.applicationIconImage = brand
        let view = PairingWindow(image: image, brand: brand, server: invitation.server, expiresAt: expiry)
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "dsh link · 扫码连接"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.center(); window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        Timer.scheduledTimer(withTimeInterval: max(1, expiry.timeIntervalSinceNow), repeats: false) { _ in app.terminate(nil) }
        withExtendedLifetime(delegate) { app.run() }
    }
} catch {
    fputs("Cannot display pairing QR. Check the private configuration and try again.\n", stderr)
    exit(1)
}
