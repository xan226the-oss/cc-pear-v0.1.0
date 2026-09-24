import AppKit

@main
enum ImageStorageTests {
    static func main() throws {
        let rep = try require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 1800,
            pixelsHigh: 1200,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        let image = NSImage(size: NSSize(width: 1800, height: 1200))
        image.addRepresentation(rep)

        let data = try require(image.losslessPNGData())
        let output = try require(NSBitmapImageRep(data: data))

        try expect(output.pixelsWide == 1800, "expected width 1800, got \(output.pixelsWide)")
        try expect(output.pixelsHigh == 1200, "expected height 1200, got \(output.pixelsHigh)")
        print("ImageStorageTests passed")
    }

    private static func require<T>(_ value: T?) throws -> T {
        guard let value else { throw TestFailure(message: "required value was nil") }
        return value
    }

    private static func expect(_ condition: Bool, _ message: String) throws {
        guard condition else { throw TestFailure(message: message) }
    }
}

private struct TestFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}
