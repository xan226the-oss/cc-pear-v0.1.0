import AppKit

@main
enum AnnotationRendererTests {
    static func main() throws {
        try rendererPreservesPixelDimensions()
        try rectangleChangesExpectedPixels()
        try mosaicStaysInsideRequestedBounds()
        print("AnnotationRendererTests passed")
    }

    private static func rendererPreservesPixelDimensions() throws {
        let source = try solidImage(width: 640, height: 480, color: .white)
        let rendered = try require(AnnotationRenderer.render(image: source, annotations: []))
        let rep = try require(NSBitmapImageRep(data: try require(rendered.losslessPNGData())))
        try expect(rep.pixelsWide == 640, "renderer changed output width")
        try expect(rep.pixelsHigh == 480, "renderer changed output height")
    }

    private static func rectangleChangesExpectedPixels() throws {
        let source = try solidImage(width: 100, height: 100, color: .white)
        let annotation = Annotation.rectangle(
            id: UUID(),
            rect: CGRect(x: 10, y: 10, width: 50, height: 40),
            style: AnnotationStyle(color: .red, lineWidth: 4, fontSize: 24, mosaicBlockSize: 18)
        )
        let rendered = try require(AnnotationRenderer.render(image: source, annotations: [annotation]))
        let rep = try require(NSBitmapImageRep(data: try require(rendered.losslessPNGData())))
        let border = try require(rep.colorAt(x: 11, y: 50)?.usingColorSpace(.deviceRGB))
        let center = try require(rep.colorAt(x: 30, y: 70)?.usingColorSpace(.deviceRGB))
        try expect(border.redComponent > 0.8 && border.greenComponent < 0.5, "rectangle border was not rendered red")
        try expect(center.greenComponent > 0.9 && center.blueComponent > 0.9, "rectangle unexpectedly filled its center")
    }

    private static func mosaicStaysInsideRequestedBounds() throws {
        let source = try splitImage(width: 80, height: 40)
        let mosaic = Annotation.mosaic(
            id: UUID(),
            rect: CGRect(x: 40, y: 0, width: 40, height: 40),
            blockSize: 16
        )
        let rendered = try require(AnnotationRenderer.render(image: source, annotations: [mosaic]))
        let sourceRep = try require(NSBitmapImageRep(data: try require(source.losslessPNGData())))
        let rep = try require(NSBitmapImageRep(data: try require(rendered.losslessPNGData())))
        let expected = try require(sourceRep.colorAt(x: 10, y: 20)?.usingColorSpace(.deviceRGB))
        let untouched = try require(rep.colorAt(x: 10, y: 20)?.usingColorSpace(.deviceRGB))
        try expect(abs(untouched.redComponent - expected.redComponent) < 0.01, "mosaic modified red outside its bounds")
        try expect(abs(untouched.blueComponent - expected.blueComponent) < 0.01, "mosaic modified blue outside its bounds")
    }

    private static func solidImage(width: Int, height: Int, color: NSColor) throws -> NSImage {
        let rep = try bitmap(width: width, height: height)
        let context = try require(NSGraphicsContext(bitmapImageRep: rep))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        color.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: NSSize(width: width, height: height))
        image.addRepresentation(rep)
        return image
    }

    private static func splitImage(width: Int, height: Int) throws -> NSImage {
        let rep = try bitmap(width: width, height: height)
        let context = try require(NSGraphicsContext(bitmapImageRep: rep))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: width / 2, height: height).fill()
        NSColor.blue.setFill()
        NSRect(x: width / 2, y: 0, width: width / 2, height: height).fill()
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: NSSize(width: width, height: height))
        image.addRepresentation(rep)
        return image
    }

    private static func bitmap(width: Int, height: Int) throws -> NSBitmapImageRep {
        try require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
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
