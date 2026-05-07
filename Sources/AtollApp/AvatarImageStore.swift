import AppKit
import AtollCore
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum AvatarImageStore {
    static let maxImportBytes = 10 * 1024 * 1024
    static let maxPixelDimension: CGFloat = 256
    /// Reject images whose decoded pixel dimensions exceed this on either side.
    /// 8192 covers the largest realistic camera/screen capture; anything larger
    /// is almost certainly hostile (decompression bomb).
    static let maxSourcePixelDimension = 8192

    private static let directoryName = "OpenIsland"
    private static let fileName = "custom-avatar.png"

    enum ImportError: LocalizedError {
        case unsupportedImage
        case fileTooLarge(limitBytes: Int)
        case pixelDimensionsTooLarge(width: Int, height: Int, limit: Int)
        case encodeFailed

        var errorDescription: String? {
            switch self {
            case .unsupportedImage:
                return "The selected file is not a supported static image."
            case .fileTooLarge(let limitBytes):
                let limitMB = limitBytes / (1024 * 1024)
                return "The selected file is too large. Choose an image under \(limitMB) MB."
            case let .pixelDimensionsTooLarge(width, height, limit):
                return "The image (\(width)×\(height) px) exceeds the \(limit)-pixel safety limit."
            case .encodeFailed:
                return "Open Island could not process that image."
            }
        }
    }

    static func currentImage(fileManager: FileManager = .default) -> NSImage? {
        let url = avatarURL(fileManager: fileManager)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return NSImage(contentsOf: url)
    }

    static func removeCurrentImage(fileManager: FileManager = .default) throws {
        let url = avatarURL(fileManager: fileManager)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    @discardableResult
    static func importImage(from sourceURL: URL, fileManager: FileManager = .default) throws -> NSImage {
        let values = try sourceURL.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey])
        if let fileSize = values.fileSize, fileSize > maxImportBytes {
            throw ImportError.fileTooLarge(limitBytes: maxImportBytes)
        }
        if let contentType = values.contentType {
            let supportedTypes: [UTType] = [.png, .jpeg, .heic, .tiff]
            guard supportedTypes.contains(where: { contentType.conforms(to: $0) }) else {
                throw ImportError.unsupportedImage
            }
        }

        // Inspect dimensions WITHOUT fully decoding (defense against
        // decompression bombs). CGImageSource reads only the header.
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let imageSource = CGImageSourceCreateWithURL(sourceURL as CFURL, sourceOptions as CFDictionary) else {
            throw ImportError.unsupportedImage
        }

        guard let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            throw ImportError.unsupportedImage
        }

        if width > maxSourcePixelDimension || height > maxSourcePixelDimension {
            throw ImportError.pixelDimensionsTooLarge(
                width: width,
                height: height,
                limit: maxSourcePixelDimension
            )
        }

        // Generate a downsampled thumbnail straight from the source — never
        // materialize the full-resolution pixels in memory.
        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: false,
            kCGImageSourceThumbnailMaxPixelSize: 1024,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, thumbOptions as CFDictionary) else {
            throw ImportError.encodeFailed
        }

        let thumbnailNSImage = NSImage(cgImage: thumbnail, size: .zero)
        let normalizedImage = normalizedAvatarImage(from: thumbnailNSImage)

        let targetURL = avatarURL(fileManager: fileManager)
        try UserPrivateFileWrite.ensurePrivateDirectory(
            at: targetURL.deletingLastPathComponent(),
            fileManager: fileManager
        )

        // Re-encode through CGImageDestination so we can explicitly drop
        // EXIF/GPS/IPTC metadata. NSBitmapImageRep already strips most of
        // it, but we belt-and-suspender it here.
        guard
            let tiffData = normalizedImage.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData),
            let cgImage = bitmap.cgImage
        else {
            throw ImportError.encodeFailed
        }

        let pngData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            pngData as CFMutableData,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw ImportError.encodeFailed
        }
        // Explicitly empty metadata; this drops any EXIF/IPTC/GPS that survived
        // the Foundation re-encode roundtrip.
        let destinationProperties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.85,
        ]
        CGImageDestinationAddImage(destination, cgImage, destinationProperties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ImportError.encodeFailed
        }

        try writeUserPrivate(pngData as Data, to: targetURL)
        return normalizedImage
    }

    private static func avatarURL(fileManager: FileManager) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)
        return appSupport
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent(fileName)
    }

    private static func normalizedAvatarImage(from sourceImage: NSImage) -> NSImage {
        guard let cgImage = sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return sourceImage
        }
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let squareSide = min(width, height)
        let cropRect = CGRect(
            x: (width - squareSide) / 2,
            y: (height - squareSide) / 2,
            width: squareSide,
            height: squareSide
        ).integral
        guard let croppedCGImage = cgImage.cropping(to: cropRect) else {
            return sourceImage
        }
        let targetSize = CGSize(width: maxPixelDimension, height: maxPixelDimension)
        let image = NSImage(size: targetSize)
        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        NSImage(cgImage: croppedCGImage, size: targetSize)
            .draw(in: CGRect(origin: .zero, size: targetSize))
        image.unlockFocus()
        return image
    }
}
