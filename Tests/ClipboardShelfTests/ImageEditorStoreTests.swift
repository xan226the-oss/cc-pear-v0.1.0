import AppKit

@MainActor
@main
enum ImageEditorStoreTests {
    static func main() throws {
        try enqueueSelectsNewestWithoutDroppingExistingSession()
        try enqueueSamePathSelectsExistingSession()
        try prepareLoadsRecentScreenshotsAndSelectsRequestedImage()
        try preparePreservesDirtySessionState()
        try completionMarksOnlyCurrentSessionSaved()
        print("ImageEditorStoreTests passed")
    }

    private static func enqueueSelectsNewestWithoutDroppingExistingSession() throws {
        let output = RecordingOutput()
        let store = ImageEditorStore(output: output)
        let first = store.enqueue(path: "/tmp/a.png", title: "A")
        let second = store.enqueue(path: "/tmp/b.png", title: "B")

        try expect(store.sessions.map(\.id) == [first, second], "enqueue dropped or reordered a session")
        try expect(store.selectedSessionID == second, "newest session was not selected")
    }

    private static func enqueueSamePathSelectsExistingSession() throws {
        let store = ImageEditorStore(output: RecordingOutput())
        let first = store.enqueue(path: "/tmp/a.png", title: "A")
        let second = store.enqueue(path: "/tmp/../tmp/a.png", title: "A again")

        try expect(first == second, "canonical duplicate path created a second session")
        try expect(store.sessions.count == 1, "duplicate path was not deduplicated")
    }

    private static func prepareLoadsRecentScreenshotsAndSelectsRequestedImage() throws {
        let store = ImageEditorStore(output: RecordingOutput())
        store.prepare(
            recentScreenshots: [
                RecentScreenshotReference(path: "/tmp/new.png", title: "New"),
                RecentScreenshotReference(path: "/tmp/old.png", title: "Old")
            ],
            selectedPath: "/tmp/old.png",
            selectedTitle: "Old"
        )

        let expected = [canonicalPath("/tmp/new.png"), canonicalPath("/tmp/old.png")]
        try expect(store.sessions.map(\.imagePath) == expected, "recent screenshot order changed")
        try expect(store.selectedSession?.imagePath == canonicalPath("/tmp/old.png"), "requested image was not selected")
    }

    private static func preparePreservesDirtySessionState() throws {
        let store = ImageEditorStore(output: RecordingOutput())
        let id = store.enqueue(path: "/tmp/dirty.png", title: "Dirty")
        store.apply(.add(.rectangle(
            id: UUID(),
            rect: CGRect(x: 0, y: 0, width: 8, height: 8),
            style: .default
        )))

        store.prepare(
            recentScreenshots: [RecentScreenshotReference(path: "/tmp/new.png", title: "New")],
            selectedPath: "/tmp/new.png",
            selectedTitle: "New"
        )

        try expect(store.session(id: id)?.isDirty == true, "sync discarded a dirty session")
        try expect(store.session(id: id)?.annotations.count == 1, "sync discarded annotations")
    }

    private static func completionMarksOnlyCurrentSessionSaved() throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("cc-pear-store-test-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: temp) }
        let source = NSImage(size: NSSize(width: 40, height: 30))
        source.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 40, height: 30).fill()
        source.unlockFocus()
        try require(source.losslessPNGData()).write(to: temp)

        let output = RecordingOutput()
        let store = ImageEditorStore(output: output)
        let id = store.enqueue(path: temp.path, title: "Capture")
        store.apply(.add(.rectangle(
            id: UUID(),
            rect: CGRect(x: 2, y: 2, width: 10, height: 10),
            style: .default
        )))

        try expect(store.session(id: id)?.isDirty == true, "annotation did not mark session dirty")
        try expect(store.completeCurrent(), "completion unexpectedly failed")
        try expect(store.session(id: id)?.isDirty == false, "successful completion did not mark session saved")
        try expect(output.savedImages.count == 1, "rendered image was not sent to output")
    }

    private static func require<T>(_ value: T?) throws -> T {
        guard let value else { throw TestFailure(message: "required value was nil") }
        return value
    }

    private static func canonicalPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }

    private static func expect(_ condition: Bool, _ message: String) throws {
        guard condition else { throw TestFailure(message: message) }
    }
}

@MainActor
private final class RecordingOutput: ImageEditorOutput {
    var savedImages: [NSImage] = []

    func saveEditedImage(_ image: NSImage, title: String) -> Bool {
        savedImages.append(image)
        return true
    }
}

private struct TestFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}
