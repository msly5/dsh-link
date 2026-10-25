import Foundation

/// Never forward Access headers through redirects, or persist authentication cookies/caches.
final class SecureTransport: NSObject, URLSessionTaskDelegate {
    // DSH snapshots include tool output and multiple history records. Foundation's
    // 1 MiB default can reject a normal conversation before any rows are decoded.
    // Keep a finite buffer limit rather than disabling the memory bound.
    static func webSocketTask(session: URLSession, request: URLRequest) -> URLSessionWebSocketTask {
        let socket = session.webSocketTask(with: request)
        socket.maximumMessageSize = 32 * 1024 * 1024
        return socket
    }

    static func session(configuration: URLSessionConfiguration = .ephemeral) -> URLSession {
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration, delegate: SecureTransport(), delegateQueue: nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
