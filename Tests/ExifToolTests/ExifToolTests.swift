import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ExifTool

@Suite("ExifTool bridge")
struct ExifToolTests {
    @Test("embedded runtime reads and writes metadata")
    func readsAndWritesMetadata() throws {
        let fixtureURL = try makeFixtureJPEG()
        let outputURL = fixtureURL.deletingLastPathComponent().appending(path: "output.jpg")
        let runtime = try ExifToolRuntime()
        let versions = try runtime.versions()
        let session = try runtime.makeSession()

        #expect(versions.exiftool == "13.57")
        #expect(versions.perl.starts(with: "v"))

        let writeResult = try session.writeMetadata(
            from: fixtureURL,
            to: outputURL,
            values: [
                "Artist": .string("SwiftPM Test"),
                "Comment": .string("Embedded ExifTool")
            ]
        )

        #expect(writeResult.success)
        #expect(FileManager.default.fileExists(atPath: outputURL.path))

        let metadata = try session.readMetadata(
            at: outputURL,
            tags: [
                "Artist",
                "Comment"
            ]
        )

        #expect(metadata["Artist"] == .string("SwiftPM Test"))
        #expect(metadata["Comment"] == .string("Embedded ExifTool"))
    }

    private func makeFixtureJPEG() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let fixtureURL = directory.appending(path: "fixture.jpg")
        var pixels: [UInt8] = [0xFF, 0xFF, 0xFF, 0xFF]
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try #require(
            CGContext(
                data: &pixels,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        let image = try #require(context.makeImage())
        let destination = try #require(
            CGImageDestinationCreateWithURL(
                fixtureURL as CFURL,
                UTType.jpeg.identifier as CFString,
                1,
                nil
            )
        )

        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return fixtureURL
    }
}
