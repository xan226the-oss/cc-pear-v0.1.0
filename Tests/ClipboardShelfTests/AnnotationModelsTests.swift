import AppKit

@main
enum AnnotationModelsTests {
    static func main() throws {
        try undoRedoDoesNotCrossSessions()
        try newOperationClearsRedoHistory()
        try replacingAndRemovingAnnotationsIsUndoable()
        print("AnnotationModelsTests passed")
    }

    private static func undoRedoDoesNotCrossSessions() throws {
        var first = ImageEditSession(id: UUID(), imagePath: "/tmp/a.png", title: "A")
        var second = ImageEditSession(id: UUID(), imagePath: "/tmp/b.png", title: "B")
        let box = Annotation.rectangle(
            id: UUID(),
            rect: CGRect(x: 10, y: 10, width: 50, height: 40),
            style: .default
        )

        first.apply(.add(box))
        second.apply(.add(box))
        first.undo()

        try expect(first.annotations.isEmpty, "first session should undo independently")
        try expect(second.annotations == [box], "second session must remain unchanged")

        first.redo()
        try expect(first.annotations == [box], "redo should restore first session")
    }

    private static func newOperationClearsRedoHistory() throws {
        var session = ImageEditSession(id: UUID(), imagePath: "/tmp/a.png", title: "A")
        let first = Annotation.rectangle(
            id: UUID(), rect: CGRect(x: 0, y: 0, width: 20, height: 20), style: .default
        )
        let second = Annotation.rectangle(
            id: UUID(), rect: CGRect(x: 30, y: 30, width: 20, height: 20), style: .default
        )

        session.apply(.add(first))
        session.undo()
        session.apply(.add(second))

        try expect(!session.canRedo, "a new edit must clear redo history")
    }

    private static func replacingAndRemovingAnnotationsIsUndoable() throws {
        var session = ImageEditSession(id: UUID(), imagePath: "/tmp/a.png", title: "A")
        let id = UUID()
        let original = Annotation.rectangle(
            id: id, rect: CGRect(x: 1, y: 2, width: 20, height: 30), style: .default
        )
        let moved = Annotation.rectangle(
            id: id, rect: CGRect(x: 11, y: 12, width: 20, height: 30), style: .default
        )

        session.apply(.add(original))
        session.apply(.replace(moved))
        try expect(session.annotations == [moved], "replace should preserve the annotation identity")
        session.apply(.remove(id))
        try expect(session.annotations.isEmpty, "remove should delete the matching annotation")
        session.undo()
        try expect(session.annotations == [moved], "undo should restore a removed annotation")
    }

    private static func expect(_ condition: Bool, _ message: String) throws {
        guard condition else { throw TestFailure(message: message) }
    }
}

private struct TestFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}
