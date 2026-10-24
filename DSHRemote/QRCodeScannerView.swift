import AVFoundation
import SwiftUI
import VisionKit

struct QRCodeScannerView: View {
    let onScan: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var authorized = false
    @State private var errorText: String?
    @State private var denied = false

    var body: some View {
        NavigationStack {
            Group {
                if authorized {
                    LiveQRScanner(onScan: { value in onScan(value); dismiss() }, onError: { errorText = $0; authorized = false })
                        .overlay(alignment: .bottom) {
                            Text("扫描 Mac 上的 dsh link 连接二维码")
                                .font(.callout).padding(16).background(.regularMaterial, in: .rect(cornerRadius: 16)).padding()
                        }
                } else if let errorText {
                    ContentUnavailableView {
                        Label("无法使用相机", systemImage: "camera")
                    } description: { Text(errorText) } actions: {
                        if denied {
                            Button("打开系统设置") {
                                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                            }
                        }
                    }
                } else { ProgressView("正在打开相机…") }
            }
            .background(Theme.bg)
            .navigationTitle("扫码连接").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
            .task {
                guard DataScannerViewController.isSupported else {
                    errorText = "此设备不支持 App 内扫码。可使用系统相机扫描二维码，或手动填写连接信息。"; return
                }
                let allowed = await AVCaptureDevice.requestAccess(for: .video)
                guard !Task.isCancelled else { return }
                guard allowed else {
                    denied = true; errorText = "请允许相机访问，以扫描 Mac 的连接二维码。你也可以返回手动填写。"; return
                }
                guard DataScannerViewController.isAvailable else {
                    errorText = "相机暂不可用，请稍后重试或使用系统相机扫描。"; return
                }
                authorized = true
            }
        }.tint(Theme.accent)
    }
}

private struct LiveQRScanner: UIViewControllerRepresentable {
    let onScan: (String) -> Void
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan, onError: onError) }
    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced, recognizesMultipleItems: false, isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true, isGuidanceEnabled: true, isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        return scanner
    }
    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        guard !scanner.isScanning, !context.coordinator.finished else { return }
        do { try scanner.startScanning() }
        catch { Task { @MainActor in onError("无法启动相机，请关闭后重试。") } }
    }
    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) { scanner.stopScanning() }

    @MainActor final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (String) -> Void
        let onError: (String) -> Void
        var finished = false
        init(onScan: @escaping (String) -> Void, onError: @escaping (String) -> Void) { self.onScan = onScan; self.onError = onError }
        func dataScanner(_ scanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !finished else { return }
            for item in addedItems {
                if case .barcode(let barcode) = item, let value = barcode.payloadStringValue {
                    finished = true; scanner.stopScanning(); onScan(value); return
                }
            }
        }
        func dataScanner(_ scanner: DataScannerViewController, becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
            guard !finished else { return }
            finished = true; scanner.stopScanning(); onError("相机暂不可用，请关闭后重试。")
        }
    }
}
