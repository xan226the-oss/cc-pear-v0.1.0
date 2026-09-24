import AppKit

@main
enum CanvasTransformTests {
    static func main() throws {
        try roundTripLandscapeImage()
        try roundTripPortraitImageWithZoomAndPan()
        try zoomIsClamped()
        print("CanvasTransformTests passed")
    }

    private static func roundTripLandscapeImage() throws {
        let transform = CanvasTransform(
            imageSize: CGSize(width: 1200, height: 800),
            viewSize: CGSize(width: 600, height: 500),
            zoom: 1,
            pan: .zero
        )
        let original = CGPoint(x: 720, y: 310)
        let restored = transform.imagePoint(fromViewPoint: transform.viewPoint(fromImagePoint: original))
        try expect(distance(original, restored) < 0.001, "landscape coordinate round trip drifted")
    }

    private static func roundTripPortraitImageWithZoomAndPan() throws {
        let transform = CanvasTransform(
            imageSize: CGSize(width: 800, height: 1400),
            viewSize: CGSize(width: 900, height: 650),
            zoom: 2.5,
            pan: CGPoint(x: 70, y: -35)
        )
        let original = CGPoint(x: 140, y: 1200)
        let restored = transform.imagePoint(fromViewPoint: transform.viewPoint(fromImagePoint: original))
        try expect(distance(original, restored) < 0.001, "portrait coordinate round trip drifted")
    }

    private static func zoomIsClamped() throws {
        let low = CanvasTransform(imageSize: CGSize(width: 100, height: 100), viewSize: CGSize(width: 500, height: 500), zoom: 0.01, pan: .zero)
        let high = CanvasTransform(imageSize: CGSize(width: 100, height: 100), viewSize: CGSize(width: 500, height: 500), zoom: 20, pan: .zero)
        try expect(low.zoom == 0.1, "minimum zoom was not clamped")
        try expect(high.zoom == 8, "maximum zoom was not clamped")
    }

    private static func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }

    private static func expect(_ condition: Bool, _ message: String) throws {
        guard condition else { throw TestFailure(message: message) }
    }
}

private struct TestFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}
