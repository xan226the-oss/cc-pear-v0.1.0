import AppKit
import SwiftUI

struct AnnotationCanvasView: NSViewRepresentable {
    let imageKey: String
    let image: NSImage
    let annotations: [Annotation]
    let tool: AnnotationTool
    let style: AnnotationStyle
    let selectedAnnotationID: UUID?
    let onEdit: (AnnotationEdit) -> Void
    let onSelect: (UUID?) -> Void

    func makeNSView(context: Context) -> AnnotationDrawingView {
        let view = AnnotationDrawingView()
        view.onEdit = onEdit
        view.onSelect = onSelect
        view.setState(
            imageKey: imageKey,
            image: image,
            annotations: annotations,
            tool: tool,
            style: style,
            selectedAnnotationID: selectedAnnotationID
        )
        return view
    }

    func updateNSView(_ view: AnnotationDrawingView, context: Context) {
        view.onEdit = onEdit
        view.onSelect = onSelect
        view.setState(
            imageKey: imageKey,
            image: image,
            annotations: annotations,
            tool: tool,
            style: style,
            selectedAnnotationID: selectedAnnotationID
        )
    }
}

final class AnnotationDrawingView: NSView, NSTextFieldDelegate {
    var onEdit: ((AnnotationEdit) -> Void)?
    var onSelect: ((UUID?) -> Void)?

    private var sourceImage: NSImage?
    private var sourceImageKey: String?
    private var displayImage: NSImage?
    private var annotations: [Annotation] = []
    private var tool: AnnotationTool = .select
    private var style: AnnotationStyle = .default
    private var selectedAnnotationID: UUID?
    private var zoom: CGFloat = 1
    private var pan = CGPoint.zero
    private var startImagePoint: CGPoint?
    private var lastImagePoint: CGPoint?
    private var strokePoints: [CGPoint] = []
    private var previewAnnotation: Annotation?
    private var movingAnnotation: Annotation?
    private var textField: NSTextField?
    private var textOrigin: CGPoint?

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    func setState(
        imageKey: String,
        image: NSImage,
        annotations: [Annotation],
        tool: AnnotationTool,
        style: AnnotationStyle,
        selectedAnnotationID: UUID?
    ) {
        let imageChanged = sourceImageKey != imageKey
        let annotationsChanged = self.annotations != annotations
        sourceImageKey = imageKey
        sourceImage = image
        self.annotations = annotations
        self.tool = tool
        self.style = style
        self.selectedAnnotationID = selectedAnnotationID
        if imageChanged || annotationsChanged || displayImage == nil {
            displayImage = AnnotationRenderer.render(image: image, annotations: annotations) ?? image
        }
        if imageChanged {
            zoom = 1
            pan = .zero
            cancelCurrentInteraction()
        }
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.controlBackgroundColor.setFill()
        bounds.fill()

        guard let displayImage else { return }
        let transform = canvasTransform
        let imageRect = transform.imageRectInView
        NSGraphicsContext.current?.imageInterpolation = .high
        displayImage.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1)

        if let previewAnnotation {
            drawOverlay(previewAnnotation, transform: transform, alpha: 0.9)
        }

        if let selectedAnnotationID,
           let selected = (previewAnnotation?.id == selectedAnnotationID ? previewAnnotation : annotations.first { $0.id == selectedAnnotationID }) {
            let selectionRect = transform.viewRect(fromImageRect: selected.bounds).insetBy(dx: -4, dy: -4)
            let path = NSBezierPath(rect: selectionRect)
            path.setLineDash([5, 4], count: 2, phase: 0)
            path.lineWidth = 1
            NSColor.controlAccentColor.setStroke()
            path.stroke()
        }
    }

    override func resetCursorRects() {
        let cursor: NSCursor = tool == .select ? .arrow : .crosshair
        addCursorRect(bounds, cursor: cursor)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        commitTextIfNeeded()
        let viewPoint = convert(event.locationInWindow, from: nil)
        let transform = canvasTransform
        guard transform.imageRectInView.contains(viewPoint) else { return }
        let imagePoint = clampedImagePoint(transform.imagePoint(fromViewPoint: viewPoint))
        startImagePoint = imagePoint
        lastImagePoint = imagePoint

        switch tool {
        case .select:
            let hitPadding = 8 / transform.scale
            let hit = annotations.reversed().first { $0.bounds.insetBy(dx: -hitPadding, dy: -hitPadding).contains(imagePoint) }
            selectedAnnotationID = hit?.id
            movingAnnotation = hit
            onSelect?(hit?.id)
        case .freehand:
            strokePoints = [imagePoint]
        case .text:
            beginTextEntry(at: imagePoint, viewPoint: viewPoint)
        case .rectangle, .arrow, .mosaic:
            break
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let startImagePoint else { return }
        let transform = canvasTransform
        let viewPoint = convert(event.locationInWindow, from: nil)
        let point = clampedImagePoint(transform.imagePoint(fromViewPoint: viewPoint))
        lastImagePoint = point

        switch tool {
        case .select:
            guard let movingAnnotation else { return }
            previewAnnotation = movingAnnotation.translated(by: CGPoint(
                x: point.x - startImagePoint.x,
                y: point.y - startImagePoint.y
            ))
        case .rectangle:
            previewAnnotation = .rectangle(id: UUID(), rect: imageRect(from: startImagePoint, to: point), style: style)
        case .arrow:
            previewAnnotation = .arrow(id: UUID(), start: startImagePoint, end: point, style: style)
        case .freehand:
            strokePoints.append(point)
            previewAnnotation = .stroke(id: UUID(), points: strokePoints, style: style)
        case .mosaic:
            previewAnnotation = .mosaic(id: UUID(), rect: imageRect(from: startImagePoint, to: point), blockSize: style.mosaicBlockSize)
        case .text:
            break
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { finishGesture() }
        guard let startImagePoint, let end = lastImagePoint else { return }

        switch tool {
        case .select:
            if let previewAnnotation {
                onEdit?(.replace(previewAnnotation))
            }
        case .rectangle:
            let rect = imageRect(from: startImagePoint, to: end)
            if rect.width >= 2, rect.height >= 2 {
                onEdit?(.add(.rectangle(id: UUID(), rect: rect, style: style)))
            }
        case .arrow:
            if hypot(end.x - startImagePoint.x, end.y - startImagePoint.y) >= 3 {
                onEdit?(.add(.arrow(id: UUID(), start: startImagePoint, end: end, style: style)))
            }
        case .freehand:
            if strokePoints.count >= 2 {
                onEdit?(.add(.stroke(id: UUID(), points: strokePoints, style: style)))
            }
        case .mosaic:
            let rect = imageRect(from: startImagePoint, to: end)
            if rect.width >= 2, rect.height >= 2 {
                onEdit?(.add(.mosaic(id: UUID(), rect: rect, blockSize: style.mosaicBlockSize)))
            }
        case .text:
            break
        }
    }

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            let cursor = convert(event.locationInWindow, from: nil)
            let oldTransform = canvasTransform
            let imagePoint = oldTransform.imagePoint(fromViewPoint: cursor)
            zoom = min(max(zoom * (1 - event.scrollingDeltaY * 0.015), 0.1), 8)
            let base = CanvasTransform(imageSize: imagePixelSize, viewSize: bounds.size, zoom: zoom, pan: .zero)
            let basePoint = base.viewPoint(fromImagePoint: imagePoint)
            pan = CGPoint(x: cursor.x - basePoint.x, y: cursor.y - basePoint.y)
        } else {
            pan.x += event.scrollingDeltaX
            pan.y -= event.scrollingDeltaY
        }
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117 {
            if let selectedAnnotationID {
                onEdit?(.remove(selectedAnnotationID))
                onSelect?(nil)
            }
            return
        }
        if event.keyCode == 53 {
            cancelCurrentInteraction()
            return
        }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        cancelCurrentInteraction()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        commitTextIfNeeded()
    }

    @objc private func commitTextFieldAction(_ sender: NSTextField) {
        commitTextIfNeeded()
        window?.makeFirstResponder(self)
    }

    private var imagePixelSize: CGSize {
        sourceImage.flatMap(AnnotationRenderer.pixelSize) ?? sourceImage?.size ?? CGSize(width: 1, height: 1)
    }

    private var canvasTransform: CanvasTransform {
        CanvasTransform(imageSize: imagePixelSize, viewSize: bounds.size, zoom: zoom, pan: pan)
    }

    private func beginTextEntry(at imagePoint: CGPoint, viewPoint: CGPoint) {
        cancelTextEntry()
        let field = NSTextField(frame: NSRect(x: viewPoint.x, y: viewPoint.y - 32, width: 220, height: 32))
        field.placeholderString = "输入文字"
        field.font = .systemFont(ofSize: max(12, style.fontSize * canvasTransform.scale), weight: .medium)
        field.textColor = style.color.nsColor
        field.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.88)
        field.isBordered = true
        field.focusRingType = .exterior
        field.delegate = self
        field.target = self
        field.action = #selector(commitTextFieldAction(_:))
        addSubview(field)
        textField = field
        textOrigin = imagePoint
        window?.makeFirstResponder(field)
    }

    private func commitTextIfNeeded() {
        guard let field = textField, let origin = textOrigin else { return }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let scale = canvasTransform.scale
        let rect = CGRect(
            x: origin.x,
            y: origin.y,
            width: max(80, field.frame.width / scale),
            height: max(style.fontSize * 1.5, field.frame.height / scale)
        )
        cancelTextEntry()
        if !text.isEmpty {
            onEdit?(.add(.text(id: UUID(), rect: rect, text: text, style: style)))
        }
    }

    private func cancelTextEntry() {
        textField?.delegate = nil
        textField?.removeFromSuperview()
        textField = nil
        textOrigin = nil
    }

    private func cancelCurrentInteraction() {
        cancelTextEntry()
        finishGesture()
    }

    private func finishGesture() {
        startImagePoint = nil
        lastImagePoint = nil
        strokePoints.removeAll()
        previewAnnotation = nil
        movingAnnotation = nil
        needsDisplay = true
    }

    private func clampedImagePoint(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(0, point.x), imagePixelSize.width),
            y: min(max(0, point.y), imagePixelSize.height)
        )
    }

    private func imageRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    private func drawOverlay(_ annotation: Annotation, transform: CanvasTransform, alpha: CGFloat) {
        switch annotation {
        case let .rectangle(_, rect, annotationStyle):
            let path = NSBezierPath(rect: transform.viewRect(fromImageRect: rect))
            configure(path, style: annotationStyle, scale: transform.scale, alpha: alpha)
            path.stroke()
        case let .arrow(_, start, end, annotationStyle):
            let from = transform.viewPoint(fromImagePoint: start)
            let to = transform.viewPoint(fromImagePoint: end)
            let path = NSBezierPath()
            path.move(to: from)
            path.line(to: to)
            configure(path, style: annotationStyle, scale: transform.scale, alpha: alpha)
            path.stroke()
        case let .stroke(_, points, annotationStyle):
            guard let first = points.first else { return }
            let path = NSBezierPath()
            path.move(to: transform.viewPoint(fromImagePoint: first))
            for point in points.dropFirst() {
                path.line(to: transform.viewPoint(fromImagePoint: point))
            }
            configure(path, style: annotationStyle, scale: transform.scale, alpha: alpha)
            path.stroke()
        case let .text(_, rect, text, annotationStyle):
            (text as NSString).draw(
                in: transform.viewRect(fromImageRect: rect),
                withAttributes: [
                    .font: NSFont.systemFont(ofSize: max(8, annotationStyle.fontSize * transform.scale), weight: .medium),
                    .foregroundColor: annotationStyle.color.nsColor.withAlphaComponent(alpha)
                ]
            )
        case let .mosaic(_, rect, _):
            NSColor.controlAccentColor.withAlphaComponent(0.28).setFill()
            transform.viewRect(fromImageRect: rect).fill()
        }
    }

    private func configure(_ path: NSBezierPath, style: AnnotationStyle, scale: CGFloat, alpha: CGFloat) {
        style.color.nsColor.withAlphaComponent(alpha).setStroke()
        path.lineWidth = max(1, style.lineWidth * scale)
        path.lineJoinStyle = .round
        path.lineCapStyle = .round
    }
}
