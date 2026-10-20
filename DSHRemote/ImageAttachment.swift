import Foundation

struct ImageAttachment: Identifiable, Sendable {
    static let selectionLimit = 4
    let id = UUID()
    let data: Data
    let preview: Data
    let mediaType: String
    let name: String

    var content: [String: Any] {
        ["type": "image", "mediaType": mediaType, "data": data.base64EncodedString(), "name": name]
    }
}

struct ChatImage: Codable, Hashable, Identifiable, Sendable {
    let attachmentId: String
    let mediaType: String
    let name: String?
    var id: String { attachmentId }
}

struct ImageLimits: Codable, Hashable, Sendable {
    let maxImageBytes: Int
    let maxImagesPerMessage: Int
    let maxMessageImageBytes: Int
    let maxImagePixels: Int
    let maxImageDimension: Int
    let mediaTypes: [String]

    static let fallback = ImageLimits(maxImageBytes: 5 * 1024 * 1024, maxImagesPerMessage: 4,
                                     maxMessageImageBytes: 20 * 1024 * 1024, maxImagePixels: 64_000_000,
                                     maxImageDimension: 8192, mediaTypes: ["image/jpeg", "image/png"])

    var selectionLimit: Int { max(0, min(ImageAttachment.selectionLimit, maxImagesPerMessage)) }

    func validate(_ images: [ImageAttachment]) throws {
        guard images.count <= selectionLimit else { throw RemoteError(message: "每条消息最多发送 \(selectionLimit) 张图片。") }
        guard images.allSatisfy({ !$0.data.isEmpty && $0.data.count <= maxImageBytes && mediaTypes.contains($0.mediaType) }) else {
            throw RemoteError(message: "图片格式或大小不符合服务器要求，请重新选择。")
        }
        guard images.reduce(0, { $0 + $1.data.count }) <= maxMessageImageBytes else {
            throw RemoteError(message: "这组图片超过服务器大小限制，请减少图片数量。")
        }
    }
}
