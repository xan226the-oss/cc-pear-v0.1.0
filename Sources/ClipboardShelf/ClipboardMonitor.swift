import AppKit
import Foundation

@MainActor
final class ClipboardMonitor {
    private let store: ClipboardStore
    private var timer: Timer?
    private var lastChangeCount: Int
    private var lastExternalApp: NSRunningApplication?

    init(store: ClipboardStore) {
        self.store = store
        lastChangeCount = NSPasteboard.general.changeCount
        lastExternalApp = Self.currentExternalApp()
    }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        if let app = Self.currentExternalApp() {
            lastExternalApp = app
        }

        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        guard !store.shouldIgnorePasteboardChange(pasteboard.changeCount) else { return }
        guard !store.isPaused, let entry = makeEntry(from: pasteboard) else { return }
        store.add(entry)
    }

    private func makeEntry(from pasteboard: NSPasteboard) -> ClipboardEntry? {
        let id = UUID()
        let app = lastExternalApp
        let appName = app?.localizedName ?? "未知应用"
        let bundleID = app?.bundleIdentifier
        let color = SourceColor.hex(for: bundleID, appName: appName)

        if let fileURLs = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !fileURLs.isEmpty {
            let paths = fileURLs.map(\.path)
            let preview = paths.map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: ", ")
            return ClipboardEntry(
                id: id,
                createdAt: Date(),
                kind: .file,
                preview: preview,
                maskedPreview: PrivacyMasker.mask(preview),
                fullText: paths.joined(separator: "\n"),
                imagePath: nil,
                filePaths: paths,
                sourceAppName: appName,
                sourceBundleID: bundleID,
                sourceColorHex: color,
                checksum: Hashing.sha256(paths.joined(separator: "|"))
            )
        }

        if let image = NSImage(pasteboard: pasteboard),
           let stored = store.storeImage(image, id: id) {
            return ClipboardEntry(
                id: id,
                createdAt: Date(),
                kind: .image,
                preview: "图片",
                maskedPreview: "图片",
                fullText: nil,
                imagePath: stored.path,
                filePaths: [],
                sourceAppName: appName,
                sourceBundleID: bundleID,
                sourceColorHex: color,
                checksum: stored.checksum
            )
        }

        if let html = pasteboard.string(forType: .html), !html.trimmedSingleLine.isEmpty {
            let plain = pasteboard.string(forType: .string) ?? html
            let preview = String(plain.trimmedSingleLine.prefix(600))
            return ClipboardEntry(
                id: id,
                createdAt: Date(),
                kind: plain.trimmedSingleLine.isLikelyURL ? .link : .richText,
                preview: preview,
                maskedPreview: PrivacyMasker.mask(preview),
                fullText: plain,
                imagePath: nil,
                filePaths: [],
                sourceAppName: appName,
                sourceBundleID: bundleID,
                sourceColorHex: color,
                checksum: Hashing.sha256(plain)
            )
        }

        if let text = pasteboard.string(forType: .string), !text.trimmedSingleLine.isEmpty {
            let trimmed = text.trimmedSingleLine
            let preview = String(trimmed.prefix(600))
            return ClipboardEntry(
                id: id,
                createdAt: Date(),
                kind: trimmed.isLikelyURL ? .link : .text,
                preview: preview,
                maskedPreview: PrivacyMasker.mask(preview),
                fullText: text,
                imagePath: nil,
                filePaths: [],
                sourceAppName: appName,
                sourceBundleID: bundleID,
                sourceColorHex: color,
                checksum: Hashing.sha256(text)
            )
        }

        return nil
    }

    private static func currentExternalApp() -> NSRunningApplication? {
        let ownPID = NSRunningApplication.current.processIdentifier
        let app = NSWorkspace.shared.frontmostApplication
        return app?.processIdentifier == ownPID ? nil : app
    }
}
