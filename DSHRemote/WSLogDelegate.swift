import Foundation

final class WSLogDelegate: NSObject, URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol proto: String?) {
        print("[dsh] ws open, proto:", proto ?? "-")
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        print("[dsh] ws close", closeCode.rawValue, reason.flatMap { String(data: $0, encoding: .utf8) } ?? "")
    }
}
