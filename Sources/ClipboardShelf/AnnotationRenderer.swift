import AppKit
import Foundation

enum AnnotationRenderer {
    static func render(image: NSImage, annotations: [Annotation]) -> NSImage? {
        guard let source = pixelSource(from: image),
              let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: source.width,
                pixelsHigh: source.height,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
              ),
              let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
            return nil
        }

        let canvasSize = NSSize(width: source.width, height: source.height)
        let normalizedSource = NSImage(cgImage: source.cgImage, size: canvasSize)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        graphics.imageInterpolation = .high
        normalizedSource.draw(
            in: NSRect(origin: .zero, size: canvasSize),
            from: .zero,
            operation: .copy,
            fraction: 1
        )

        for annotation in annotations {
            draw(annotation, source: normalizedSource, canvasHeight: canvasSize.height, graphics: graphics)
        }
        graphics.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        let output = NSImage(size: canvasSize)
        output.addRepresentation(bitmap)
        return output
    }

    static func pixelSize(of image: NSImage) -> CGSize? {
        guard let source = pixelSource(from: image) else { return nil }
        return CGSize(width: source.width, height: source.height)
    }

    private static func pixelSource(from image: NSImage) -> (cgImage: CGImage, width: Int, height: Int)? {
        var proposed = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else {
            return nil
        }
        return (cgImage, cgImage.width, cgImage.height)
    }

    private static func draw(
        _ annotation: Annotation,
        source: NSImage,
        canvasHeight: CGFloat,
        graphics: NSGraphicsContext
    ) {
        switch annotation {
        case let .rectangle(_, rect, style):
            let path = NSBezierPath(rect: appKitRect(rect, canvasHeight: canvasHeight))
            configure(path, style: style)
            path.stroke()

        case let .arrow(_, start, end, style):
            drawArrow(
                from: appKitPoint(start, canvasHeight: canvasHeight),
                to: appKitPoint(end, canvasHeight: canvasHeight),
                style: style
            )

        case let .stroke(_, points, style):
            guard let first = points.first else { return }
            let path = NSBezierPath()
            path.move(to: appKitPoint(first, canvasHeight: canvasHeight))
            for point in points.dropFirst() {
                path.line(to: appKitPoint(point, canvasHeight: canvasHeight))
            }
            configure(path, style: style)
            path.lineJoinStyle = .round
            path.lineCapStyle = .round
            path.stroke()

        case let .text(_, rect, text, style):
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byWordWrapping
            (text as NSString).draw(
                in: appKitRect(rect, canvasHeight: canvasHeight),
                withAttributes: [
                    .font: NSFont.systemFont(ofSize: style.fontSize, weight: .medium),
                    .foregroundColor: style.color.nsColor,
                    .paragraphStyle: paragraph
                ]
            )

        case let .mosaic(_, rect, blockSize):
            drawMosaic(
                source: source,
                rect: appKitRect(rect, canvasHeight: canvasHeight),
                blockSize: blockSize,
                graphics: graphics
            )
        }
    }

    private static func configure(_ path: NSBezierPath, style: AnnotationStyle) {
        style.color.nsColor.setStroke()
        path.lineWidth = style.lineWidth
        path.lineJoinStyle = .round
        path.lineCapStyle = .round
    }

    private static func drawArrow(from start: CGPoint, to end: CGPoint, style: AnnotationStyle) {
        let path = NSBezierPath()
        path.move(to: start)
        path.line(to: end)
        configure(path, style: style)
        path.stroke()

        let angle = atan2(end.y - start.y, end.x - start.x)
        let headLength = max(12, style.lineWidth * 4.5)
        let spread = CGFloat.pi / 7
        let left = CGPoint(
            x: end.x - headLength * cos(angle - spread),
            y: end.y - headLength * sin(angle - spread)
        )
        let right = CGPoint(
            x: end.x - headLength * cos(angle + spread),
            y: end.y - headLength * sin(angle + spread)
        )
        let head = NSBezierPath()
        head.move(to: left)
        head.line(to: end)
        head.line(to: right)
        configure(head, style: style)
        head.stroke()
    }

    private static func drawMosaic(
        source: NSImage,
        rect: CGRect,
        blockSize: CGFloat,
        graphics: NSGraphicsContext
    ) {
        let clipped = rect.standardized.intersection(NSRect(origin: .zero, size: source.size))
        guard clipped.width >= 1, clipped.height >= 1 else { return }

        let size = max(2, blockSize)
        let tinyWidth = max(1, Int(ceil(clipped.width / size)))
        let tinyHeight = max(1, Int(ceil(clipped.height / size)))
        guard let tinyRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: tinyWidth,
            pixelsHigh: tinyHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let tinyContext = NSGraphicsContext(bitmapImageRep: tinyRep) else {
            return
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = tinyContext
        tinyContext.imageInterpolation = .low
        source.draw(
            in: NSRect(x: 0, y: 0, width: tinyWidth, height: tinyHeight),
            from: clipped,
            operation: .copy,
            fraction: 1
        )
        tinyContext.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        let tinyImage = NSImage(size: NSSize(width: tinyWidth, height: tinyHeight))
        tinyImage.addRepresentation(tinyRep)
        NSGraphicsContext.current = graphics
        graphics.imageInterpolation = .none
        tinyImage.draw(in: clipped, from: .zero, operation: .copy, fraction: 1)
        graphics.imageInterpolation = .high
    }

    private static func appKitPoint(_ point: CGPoint, canvasHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: canvasHeight - point.y)
    }

    private static func appKitRect(_ rect: CGRect, canvasHeight: CGFloat) -> CGRect {
        let rect = rect.standardized
        return CGRect(x: rect.minX, y: canvasHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}
