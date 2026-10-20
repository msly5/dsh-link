import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImagePreparation {
    static func thumbnail(_ data: Data, maxDimension: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
        ] as CFDictionary)
    }

    static func prepare(_ data: Data, limits: ImageLimits = .fallback) throws -> ImageAttachment {
        guard data.count <= 50 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0,
              limits.maxImageBytes > 0, limits.maxImageDimension > 0, limits.maxImagePixels > 0 else {
            throw RemoteError(message: "无法读取这张图片，或原图过大。请选择其他图片。")
        }
        let sourceType = CGImageSourceGetType(source) as String?
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let hasAlpha = properties?[kCGImagePropertyHasAlpha] as? Bool ?? false
        let usePNG = limits.mediaTypes.contains("image/png") && (hasAlpha || sourceType == UTType.png.identifier || !limits.mediaTypes.contains("image/jpeg"))
        let type = usePNG ? UTType.png : UTType.jpeg
        let mime = usePNG ? "image/png" : "image/jpeg"
        guard limits.mediaTypes.contains(mime) else { throw RemoteError(message: "服务器不支持 PNG 或 JPEG 图片。") }
        var dimension = min(3072, limits.maxImageDimension, Int(Double(limits.maxImagePixels).squareRoot()))
        let byteLimit = min(5 * 1024 * 1024, limits.maxImageBytes)
        // Decoding a bounded thumbnail also applies EXIF orientation. Re-encoding strips location metadata.
        while dimension > 0 {
            guard let image = thumbnail(data, maxDimension: dimension),
                  let encoded = encode(image, type: type) else { break }
            if encoded.count <= byteLimit,
               let small = thumbnail(encoded, maxDimension: 240), let preview = encode(small, type: .jpeg) {
                return ImageAttachment(data: encoded, preview: preview, mediaType: mime,
                                       name: "image-\(UUID().uuidString.prefix(8)).\(usePNG ? "png" : "jpg")")
            }
            let next = Int(Double(dimension) * 0.75)
            if next == dimension { break }
            dimension = next
        }
        throw RemoteError(message: "图片无法处理到服务器要求的大小，请换一张图片。")
    }

    private static func encode(_ image: CGImage, type: UTType) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.88] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}
