import CoreGraphics

struct CanvasTransform {
    let imageSize: CGSize
    let viewSize: CGSize
    let zoom: CGFloat
    let pan: CGPoint

    init(imageSize: CGSize, viewSize: CGSize, zoom: CGFloat, pan: CGPoint) {
        self.imageSize = imageSize
        self.viewSize = viewSize
        self.zoom = min(max(zoom, 0.1), 8)
        self.pan = pan
    }

    var scale: CGFloat {
        guard imageSize.width > 0, imageSize.height > 0 else { return 1 }
        let fit = min(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        return max(0.0001, fit * zoom)
    }

    var imageRectInView: CGRect {
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (viewSize.width - size.width) / 2 + pan.x,
            y: (viewSize.height - size.height) / 2 + pan.y,
            width: size.width,
            height: size.height
        )
    }

    func viewPoint(fromImagePoint point: CGPoint) -> CGPoint {
        let rect = imageRectInView
        return CGPoint(
            x: rect.minX + point.x * scale,
            y: rect.maxY - point.y * scale
        )
    }

    func imagePoint(fromViewPoint point: CGPoint) -> CGPoint {
        let rect = imageRectInView
        return CGPoint(
            x: (point.x - rect.minX) / scale,
            y: (rect.maxY - point.y) / scale
        )
    }

    func viewRect(fromImageRect imageRect: CGRect) -> CGRect {
        let rect = imageRect.standardized
        let topLeft = viewPoint(fromImagePoint: CGPoint(x: rect.minX, y: rect.minY))
        return CGRect(
            x: topLeft.x,
            y: topLeft.y - rect.height * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
    }
}
