import AppKit
import Combine
import Foundation

@MainActor
protocol ImageEditorOutput: AnyObject {
    func saveEditedImage(_ image: NSImage, title: String) -> Bool
}

@MainActor
final class ImageEditorStore: ObservableObject {
    @Published private(set) var sessions: [ImageEditSession] = []
    @Published var selectedSessionID: UUID?
    @Published var selectedAnnotationID: UUID?
    @Published var tool: AnnotationTool = .select
    @Published var style: AnnotationStyle = .default
    @Published var errorMessage: String?

    private weak var output: ImageEditorOutput?

    init(output: ImageEditorOutput) {
        self.output = output
    }

    var selectedSession: ImageEditSession? {
        guard let selectedSessionID else { return nil }
        return sessions.first { $0.id == selectedSessionID }
    }

    var hasDirtySessions: Bool {
        sessions.contains(where: \.isDirty)
    }

    @discardableResult
    func enqueue(path: String, title: String) -> UUID {
        let canonicalPath = canonicalPath(path)
        if let existing = sessions.first(where: { $0.imagePath == canonicalPath }) {
            selectedSessionID = existing.id
            selectedAnnotationID = nil
            return existing.id
        }

        let session = ImageEditSession(imagePath: canonicalPath, title: title)
        sessions.append(session)
        selectedSessionID = session.id
        selectedAnnotationID = nil
        return session.id
    }

    func prepare(
        recentScreenshots: [RecentScreenshotReference],
        selectedPath: String,
        selectedTitle: String
    ) {
        let selectedPath = canonicalPath(selectedPath)
        var sessionsByPath = Dictionary(uniqueKeysWithValues: sessions.map { ($0.imagePath, $0) })
        var orderedPaths: [String] = []

        for reference in recentScreenshots {
            let path = canonicalPath(reference.path)
            if sessionsByPath[path] == nil {
                sessionsByPath[path] = ImageEditSession(imagePath: path, title: reference.title)
            }
            if !orderedPaths.contains(path) {
                orderedPaths.append(path)
            }
        }

        if sessionsByPath[selectedPath] == nil {
            sessionsByPath[selectedPath] = ImageEditSession(
                imagePath: selectedPath,
                title: selectedTitle
            )
        }
        if !orderedPaths.contains(selectedPath) {
            orderedPaths.insert(selectedPath, at: 0)
        }

        for session in sessions where session.isDirty && !orderedPaths.contains(session.imagePath) {
            orderedPaths.append(session.imagePath)
        }

        sessions = orderedPaths.compactMap { sessionsByPath[$0] }
        selectedSessionID = sessionsByPath[selectedPath]?.id
        selectedAnnotationID = nil
    }

    func session(id: UUID) -> ImageEditSession? {
        sessions.first { $0.id == id }
    }

    func select(id: UUID) {
        guard sessions.contains(where: { $0.id == id }) else { return }
        selectedSessionID = id
        selectedAnnotationID = nil
    }

    func removeSession(id: UUID) {
        sessions.removeAll { $0.id == id }
        if selectedSessionID == id {
            selectedSessionID = sessions.last?.id
            selectedAnnotationID = nil
        }
    }

    func apply(_ edit: AnnotationEdit) {
        mutateSelectedSession { $0.apply(edit) }
    }

    func undo() {
        mutateSelectedSession { $0.undo() }
        selectedAnnotationID = nil
    }

    func redo() {
        mutateSelectedSession { $0.redo() }
        selectedAnnotationID = nil
    }

    func clear() {
        mutateSelectedSession { $0.clearAnnotations() }
        selectedAnnotationID = nil
    }

    func removeSelectedAnnotation() {
        guard let selectedAnnotationID else { return }
        apply(.remove(selectedAnnotationID))
        self.selectedAnnotationID = nil
    }

    @discardableResult
    func completeCurrent() -> Bool {
        guard let selectedSessionID else { return false }
        return complete(sessionID: selectedSessionID)
    }

    @discardableResult
    func complete(sessionID: UUID) -> Bool {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return false }
        let session = sessions[index]
        guard let image = NSImage(contentsOfFile: session.imagePath) else {
            errorMessage = "原图已不可用，无法完成编辑。"
            return false
        }
        guard let rendered = AnnotationRenderer.render(image: image, annotations: session.annotations) else {
            errorMessage = "图片渲染失败，已保留当前标注。"
            return false
        }
        guard output?.saveEditedImage(rendered, title: session.title) == true else {
            errorMessage = "无法保存编辑结果，已保留当前标注。"
            return false
        }

        sessions[index].markSaved()
        errorMessage = nil
        return true
    }

    func saveAllDirty() -> Bool {
        let dirtyIDs = sessions.filter(\.isDirty).map(\.id)
        for id in dirtyIDs where !complete(sessionID: id) {
            selectedSessionID = id
            return false
        }
        return true
    }

    func discardAllChanges() {
        sessions.removeAll()
        selectedSessionID = nil
        selectedAnnotationID = nil
        errorMessage = nil
    }

    @discardableResult
    func exportCurrent(to url: URL) -> Bool {
        guard let session = selectedSession,
              let image = NSImage(contentsOfFile: session.imagePath),
              let rendered = AnnotationRenderer.render(image: image, annotations: session.annotations),
              let data = rendered.losslessPNGData() else {
            errorMessage = "无法生成导出图片，已保留当前标注。"
            return false
        }

        do {
            try data.write(to: url, options: .atomic)
            errorMessage = nil
            return true
        } catch {
            errorMessage = "导出失败：\(error.localizedDescription)"
            return false
        }
    }

    private func mutateSelectedSession(_ mutation: (inout ImageEditSession) -> Void) {
        guard let selectedSessionID,
              let index = sessions.firstIndex(where: { $0.id == selectedSessionID }) else {
            return
        }
        mutation(&sessions[index])
    }

    private func canonicalPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }
}
