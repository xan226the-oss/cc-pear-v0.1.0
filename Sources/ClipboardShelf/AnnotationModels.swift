import AppKit
import Foundation

enum AnnotationTool: String, CaseIterable, Identifiable {
    case select
    case rectangle
    case arrow
    case freehand
    case text
    case mosaic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .select: "选择"
        case .rectangle: "矩形"
        case .arrow: "箭头"
        case .freehand: "画笔"
        case .text: "文字"
        case .mosaic: "马赛克"
        }
    }

    var symbolName: String {
        switch self {
        case .select: "cursorarrow"
        case .rectangle: "rectangle"
        case .arrow: "arrow.up.right"
        case .freehand: "pencil.tip"
        case .text: "textformat"
        case .mosaic: "square.grid.3x3.fill"
        }
    }
}

struct AnnotationColor: Equatable {
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat
    var alpha: CGFloat

    static let red = AnnotationColor(red: 1, green: 0.16, blue: 0.12, alpha: 1)

    init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(_ color: NSColor) {
        let converted = color.usingColorSpace(.deviceRGB) ?? color
        red = converted.redComponent
        green = converted.greenComponent
        blue = converted.blueComponent
        alpha = converted.alphaComponent
    }

    var nsColor: NSColor {
        NSColor(deviceRed: red, green: green, blue: blue, alpha: alpha)
    }

    var cgColor: CGColor { nsColor.cgColor }
}

struct AnnotationStyle: Equatable {
    var color: AnnotationColor
    var lineWidth: CGFloat
    var fontSize: CGFloat
    var mosaicBlockSize: CGFloat

    static let `default` = AnnotationStyle(
        color: .red,
        lineWidth: 3,
        fontSize: 24,
        mosaicBlockSize: 18
    )
}

enum Annotation: Identifiable, Equatable {
    case rectangle(id: UUID, rect: CGRect, style: AnnotationStyle)
    case arrow(id: UUID, start: CGPoint, end: CGPoint, style: AnnotationStyle)
    case stroke(id: UUID, points: [CGPoint], style: AnnotationStyle)
    case text(id: UUID, rect: CGRect, text: String, style: AnnotationStyle)
    case mosaic(id: UUID, rect: CGRect, blockSize: CGFloat)

    var id: UUID {
        switch self {
        case let .rectangle(id, _, _),
             let .arrow(id, _, _, _),
             let .stroke(id, _, _),
             let .text(id, _, _, _),
             let .mosaic(id, _, _):
            id
        }
    }

    var bounds: CGRect {
        switch self {
        case let .rectangle(_, rect, _), let .text(_, rect, _, _), let .mosaic(_, rect, _):
            return rect.standardized
        case let .arrow(_, start, end, style):
            return CGRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            ).insetBy(dx: -max(8, style.lineWidth * 2), dy: -max(8, style.lineWidth * 2))
        case let .stroke(_, points, style):
            guard let first = points.first else { return .zero }
            return points.dropFirst().reduce(CGRect(origin: first, size: .zero)) { rect, point in
                rect.union(CGRect(origin: point, size: .zero))
            }.insetBy(dx: -max(6, style.lineWidth), dy: -max(6, style.lineWidth))
        }
    }

    func translated(by delta: CGPoint) -> Annotation {
        func point(_ value: CGPoint) -> CGPoint {
            CGPoint(x: value.x + delta.x, y: value.y + delta.y)
        }
        func rect(_ value: CGRect) -> CGRect {
            value.offsetBy(dx: delta.x, dy: delta.y)
        }

        switch self {
        case let .rectangle(id, value, style):
            return .rectangle(id: id, rect: rect(value), style: style)
        case let .arrow(id, start, end, style):
            return .arrow(id: id, start: point(start), end: point(end), style: style)
        case let .stroke(id, points, style):
            return .stroke(id: id, points: points.map(point), style: style)
        case let .text(id, value, text, style):
            return .text(id: id, rect: rect(value), text: text, style: style)
        case let .mosaic(id, value, blockSize):
            return .mosaic(id: id, rect: rect(value), blockSize: blockSize)
        }
    }
}

enum AnnotationEdit {
    case add(Annotation)
    case replace(Annotation)
    case remove(UUID)
    case clear
}

struct ImageEditSession: Identifiable, Equatable {
    let id: UUID
    let imagePath: String
    var title: String
    var annotations: [Annotation]
    private(set) var undoStack: [[Annotation]]
    private(set) var redoStack: [[Annotation]]
    private(set) var isDirty: Bool

    init(
        id: UUID = UUID(),
        imagePath: String,
        title: String,
        annotations: [Annotation] = []
    ) {
        self.id = id
        self.imagePath = imagePath
        self.title = title
        self.annotations = annotations
        undoStack = []
        redoStack = []
        isDirty = false
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    mutating func apply(_ edit: AnnotationEdit) {
        var updated = annotations
        switch edit {
        case let .add(annotation):
            updated.append(annotation)
        case let .replace(annotation):
            guard let index = updated.firstIndex(where: { $0.id == annotation.id }) else { return }
            updated[index] = annotation
        case let .remove(id):
            guard updated.contains(where: { $0.id == id }) else { return }
            updated.removeAll { $0.id == id }
        case .clear:
            guard !updated.isEmpty else { return }
            updated.removeAll()
        }

        guard updated != annotations else { return }
        undoStack.append(annotations)
        annotations = updated
        redoStack.removeAll()
        isDirty = true
    }

    mutating func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(annotations)
        annotations = previous
        isDirty = true
    }

    mutating func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(annotations)
        annotations = next
        isDirty = true
    }

    mutating func clearAnnotations() {
        apply(.clear)
    }

    mutating func markSaved() {
        isDirty = false
    }
}
