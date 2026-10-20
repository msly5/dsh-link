import CryptoKit
import Foundation

actor ImageAttachmentStore {
    static let shared = ImageAttachmentStore()
    private let directory: URL
    private var pending: [String: Task<Data, Error>] = [:]

    init(directory: URL? = nil) {
        self.directory = directory ?? URL.cachesDirectory.appending(path: "DSHRemote/Images-v1", directoryHint: .isDirectory)
    }

    func data(server: URL, sessionId: String, image: ChatImage, client: RemoteClient = .shared) async throws -> Data {
        let identity = try JSONEncoder().encode([server.absoluteString, sessionId, image.attachmentId])
        let key = SHA256.hash(data: identity).map { String(format: "%02x", $0) }.joined()
        let file = directory.appending(path: key + ".image")
        if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 20 * 1024 * 1024,
           let bytes = try? Data(contentsOf: file), ImagePreparation.thumbnail(bytes, maxDimension: 32) != nil { return bytes }
        if let request = pending[key] { return try await request.value }
        let request = Task { try await client.imageAttachment(sessionId: sessionId, attachmentId: image.attachmentId, baseURL: server) }
        pending[key] = request
        defer { pending[key] = nil }
        let bytes = try await request.value
        guard ImagePreparation.thumbnail(bytes, maxDimension: 32) != nil else { throw RemoteError(message: "图片数据无法解码。") }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            var folder = directory
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try folder.setResourceValues(values)
            #if os(iOS)
            try bytes.write(to: file, options: [.atomic, .completeFileProtection])
            #else
            try bytes.write(to: file, options: .atomic)
            #endif
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys))
            let entries = files.filter { $0.pathExtension == "image" }.compactMap { url -> (URL, Int, Date)? in
                guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
                return (url, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
            }.sorted { $0.2 > $1.2 }
            var total = 0
            for (index, entry) in entries.enumerated() {
                total += entry.1
                if index >= 100 || total > 64 * 1024 * 1024 { try? FileManager.default.removeItem(at: entry.0) }
            }
        } catch { /* Cached images are optional; a successful network read still displays. */ }
        return bytes
    }
}
