import CryptoKit
import Foundation

/// Only completed messages are cached. Connection state and pending actions stay live.
actor ConversationCache {
    static let shared = ConversationCache()
    static let messageLimit = 200
    // Earlier display caches lack call/reasoning metadata. Rebuild them from the event log once.
    private static let version = 3
    private static let fileLimit = 4 * 1024 * 1024
    private static let totalLimit = 32 * 1024 * 1024
    private static let conversationLimit = 50

    struct Snapshot: Codable, Sendable {
        let version: Int
        let server: String
        let sessionId: String
        let savedAt: Date
        let cursor: Int
        let oldestSeq: Int?
        let messages: [ChatMessage]
    }

    private let directory: URL
    private var newestRecordings: [String: Date] = [:]

    init(directory: URL? = nil) {
        self.directory = directory ?? URL.cachesDirectory.appending(path: "DSHRemote/Conversations-v1", directoryHint: .isDirectory)
    }

    func load(server: URL, sessionId: String) -> Snapshot? {
        let file = fileURL(server: server, sessionId: sessionId)
        guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= Self.fileLimit,
              let data = try? Data(contentsOf: file),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
              snapshot.version == Self.version, snapshot.server == serverKey(server), snapshot.sessionId == sessionId,
              snapshot.cursor >= 0, snapshot.messages.count <= Self.messageLimit,
              snapshot.messages.isEmpty || snapshot.oldestSeq.map({ $0 >= 0 && $0 <= snapshot.cursor }) == true,
              Set(snapshot.messages.map(\.id)).count == snapshot.messages.count,
              snapshot.messages.allSatisfy({ $0.seq >= (snapshot.oldestSeq ?? 0) && $0.seq <= snapshot.cursor }) else { return nil }
        newestRecordings[file.lastPathComponent] = max(newestRecordings[file.lastPathComponent] ?? .distantPast, snapshot.savedAt)
        return snapshot
    }

    func save(server: URL, sessionId: String, cursor: Int, oldestSeq: Int?, messages: [ChatMessage], recordedAt: Date = Date()) {
        guard cursor >= 0 else { return }
        let file = fileURL(server: server, sessionId: sessionId)
        guard recordedAt >= (newestRecordings[file.lastPathComponent] ?? .distantPast) else { return }
        let completed = messages.filter { $0.activity?.phase != .running }
        var retained = Array(completed.suffix(Self.messageLimit))
        var boundary = retained.count == completed.count ? oldestSeq : retained.first?.seq
        var data: Data
        while true {
            let snapshot = Snapshot(version: Self.version, server: serverKey(server), sessionId: sessionId,
                                    savedAt: recordedAt, cursor: cursor, oldestSeq: boundary, messages: retained)
            guard let encoded = try? JSONEncoder().encode(snapshot) else { return }
            data = encoded
            if data.count <= Self.fileLimit { break }
            guard !retained.isEmpty else { return }
            retained.removeFirst()
            boundary = retained.first?.seq
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            var folder = directory
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try folder.setResourceValues(values)
            #if os(iOS)
            try data.write(to: file, options: [.atomic, .completeFileProtection])
            #else
            try data.write(to: file, options: .atomic)
            #endif
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            newestRecordings[file.lastPathComponent] = recordedAt
            prune()
        } catch {
            // A full disk, a locked device, or OS cache eviction must not stop live chat.
        }
    }

    private func serverKey(_ server: URL) -> String {
        var components = URLComponents(url: server, resolvingAgainstBaseURL: false)!
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        if (components.scheme == "https" && components.port == 443) || (components.scheme == "http" && components.port == 80) {
            components.port = nil
        }
        while components.path.hasSuffix("/") { components.path.removeLast() }
        return components.string ?? server.absoluteString
    }

    private func fileURL(server: URL, sessionId: String) -> URL {
        let identity = (try? JSONEncoder().encode([serverKey(server), sessionId])) ?? Data()
        let name = SHA256.hash(data: identity).map { String(format: "%02x", $0) }.joined()
        return directory.appending(path: name + ".json")
    }

    private func prune() {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys)) else { return }
        let entries = files.filter { $0.pathExtension == "json" }.compactMap { file -> (URL, Int, Date)? in
            guard let values = try? file.resourceValues(forKeys: keys) else { return nil }
            return (file, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
        }.sorted { $0.2 > $1.2 }
        var bytes = 0
        for (index, entry) in entries.enumerated() {
            bytes += entry.1
            if index >= Self.conversationLimit || bytes > Self.totalLimit { try? FileManager.default.removeItem(at: entry.0) }
        }
    }
}
