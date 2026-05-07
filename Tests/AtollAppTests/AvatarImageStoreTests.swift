import AppKit
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import AtollApp

struct AvatarImageStoreTests {
    private static func tempImageURL(width: Int, height: Int, name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("avatar-\(UUID().uuidString)-\(name)")
        let bytesPerRow = width * 4
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let cgImage = context.makeImage()!

        let data = NSMutableData()
        let dest = CGImageDestinationCreateWithData(
            data as CFMutableData,
            UTType.png.identifier as CFString,
            1,
            nil
        )!
        CGImageDestinationAddImage(dest, cgImage, nil)
        CGImageDestinationFinalize(dest)
        try (data as Data).write(to: url)
        return url
    }

    @Test
    func acceptsImageWithinPixelLimit() throws {
        let url = try Self.tempImageURL(width: 64, height: 64, name: "small.png")
        defer { try? FileManager.default.removeItem(at: url) }

        let tempSupport = FileManager.default.temporaryDirectory
            .appendingPathComponent("avatar-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempSupport) }

        // Use a fake FileManager-like setup by writing to default location.
        // We just exercise the import path; ensure it doesn't throw.
        _ = try AvatarImageStore.importImage(from: url)
        try? AvatarImageStore.removeCurrentImage()
    }

    @Test
    func rejectsImageOverPixelLimit() throws {
        // 8193 px > 8192 cap.
        let url = try Self.tempImageURL(width: 8193, height: 16, name: "huge.png")
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            _ = try AvatarImageStore.importImage(from: url)
            Issue.record("expected ImportError.pixelDimensionsTooLarge")
        } catch let error as AvatarImageStore.ImportError {
            guard case .pixelDimensionsTooLarge = error else {
                Issue.record("wrong error: \(error)")
                return
            }
        }
    }
}
