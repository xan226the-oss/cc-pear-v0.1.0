import AppKit
import Foundation

@MainActor
final class ClipboardStore: ObservableObject {
    @Published private(set) var entries: [ClipboardEntry] = []
    @Published var isPaused: Bool {
        didSet {
            UserDefaults.standard.set(isPaused, forKey: Self.pauseKey)
        }
    }

    private static let pauseKey = "CCPear.isPaused"
    private let historyURL: URL
    private let mediaURL: URL
    private let retention: TimeInterval = 7 * 24 * 60 * 60
    private var ignoredPasteboardChangeCounts = Set<Int>()
    private var cleanupTimer: Timer?

    init() {
        if UserDefaults.standard.object(forKey: Self.pauseKey) == nil,
           let legacyPaused = UserDefaults.standard.object(forKey: "ClipboardShelf.isPaused") as? Bool {
            UserDefaults.standard.set(legacyPaused, forKey: Self.pauseKey)
        }
        isPaused = UserDefaults.standard.bool(forKey: Self.pauseKey)

        let paths: (history: URL, media: URL)
        do {
            let support = try AppPaths.supportDirectory()
            paths = (
                support.appendingPathComponent("history.json"),
                try AppPaths.mediaDirectory()
            )
        } catch {
            let fallback = FileManager.default.temporaryDirectory.appendingPathComponent("cc-pear", isDirectory: true)
            try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
            let media = fallback.appendingPathComponent("Media", isDirectory: true)
            try? FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
            paths = (fallback.appendingPathComponent("history.json"), media)
        }

        historyURL = paths.history
        mediaURL = paths.media

        load()
        pruneAndSaveIfNeeded()
        startCleanupTimer()
    }

    func add(_ entry: ClipboardEntry) {
        guard !isDuplicate(entry) else {
            if let imagePath = entry.imagePath {
                removeStoredImage(at: imagePath)
            }
            return
        }
        entries.insert(entry, at: 0)
        pruneAndSaveIfNeeded()
        save()
    }

    func delete(_ entry: ClipboardEntry) {
        let removedImages = entries
            .filter { $0.id == entry.id }
            .compactMap(\.imagePath)
        entries.removeAll { $0.id == entry.id }
        removeImagesIfUnused(removedImages)
        save()
    }

    func clearAll() {
        entries.removeAll()
        AppPaths.clearSupportDirectory()
        save()
    }

    func toggleFavorite(_ entry: ClipboardEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index].isFavorite.toggle()
        save()
    }

    func hasImageChecksum(_ checksum: String) -> Bool {
        entries.contains { $0.kind == .image && $0.checksum == checksum }
    }

    func recentScreenshots(limit: Int = 10) -> [RecentScreenshotReference] {
        RecentScreenshotSelector.select(from: entries, limit: limit)
    }

    func filteredEntries(query: String, filter: KindFilter, scope: TimeScope) -> [ClipboardEntry] {
        let cutoff = scope == .favorites ? nil : Date().addingTimeInterval(-scope.interval)
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return entries.filter { entry in
            let matchesScope = scope == .favorites ? entry.isFavorite : entry.createdAt >= (cutoff ?? .distantPast)
            guard matchesScope, filter.matches(entry.kind) else { return false }
            guard !normalizedQuery.isEmpty else { return true }

            let haystack = [
                entry.preview,
                entry.fullText ?? "",
                entry.sourceAppName,
                entry.kind.title,
                entry.filePaths.joined(separator: " ")
            ].joined(separator: " ").lowercased()
            return haystack.contains(normalizedQuery)
        }
    }

    func copyToPasteboard(_ entry: ClipboardEntry, textSuffix: String = "") {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch entry.kind {
        case .image:
            if let imagePath = entry.imagePath,
               let item = imagePasteboardItem(for: imagePath) {
                pasteboard.writeObjects([item])
            }
        case .file:
            let urls = entry.filePaths.map(URL.init(fileURLWithPath:))
            pasteboard.writeObjects(urls as [NSURL])
        case .text, .link, .richText:
            pasteboard.setString((entry.fullText ?? entry.preview) + textSuffix, forType: .string)
        }

        ignorePasteboardChange(pasteboard.changeCount)
    }

    @discardableResult
    func addCurrentPasteboardImageAsScreenshot(changeCount: Int) -> ClipboardEntry? {
        let pasteboard = NSPasteboard.general
        guard let image = NSImage(pasteboard: pasteboard) else { return nil }

        let id = UUID()
        guard let stored = storeImage(image, id: id) else { return nil }
        if let existing = entries.first(where: { $0.kind == .image && $0.checksum == stored.checksum }) {
            removeStoredImage(at: stored.path)
            ignorePasteboardChange(changeCount)
            return existing
        }

        let entry = ClipboardEntry(
            id: id,
            createdAt: Date(),
            kind: .image,
            preview: "截图",
            maskedPreview: "截图",
            fullText: nil,
            imagePath: stored.path,
            filePaths: [],
            sourceAppName: "系统截图",
            sourceBundleID: "com.apple.screencapture",
            sourceColorHex: "#0A84FF",
            checksum: stored.checksum
        )
        add(entry)
        ignorePasteboardChange(changeCount)
        return entry
    }

    @discardableResult
    func addRenderedImage(_ image: NSImage, title: String) -> ClipboardEntry? {
        let id = UUID()
        guard let stored = storeImage(image, id: id) else { return nil }

        if let existing = entries.first(where: { $0.kind == .image && $0.checksum == stored.checksum }) {
            removeStoredImage(at: stored.path)
            copyToPasteboard(existing)
            return existing
        }

        let entry = ClipboardEntry(
            id: id,
            createdAt: Date(),
            kind: .image,
            preview: title.isEmpty ? "编辑后的图片" : "\(title)（已编辑）",
            maskedPreview: title.isEmpty ? "编辑后的图片" : "\(title)（已编辑）",
            fullText: nil,
            imagePath: stored.path,
            filePaths: [],
            sourceAppName: "cc-pear 编辑",
            sourceBundleID: AppInfo.bundleIdentifier,
            sourceColorHex: "#FF453A",
            checksum: stored.checksum
        )
        add(entry)
        copyToPasteboard(entry)
        return entry
    }

    func shouldIgnorePasteboardChange(_ changeCount: Int) -> Bool {
        ignoredPasteboardChangeCounts.remove(changeCount) != nil
    }

    private func ignorePasteboardChange(_ changeCount: Int) {
        ignoredPasteboardChangeCounts.insert(changeCount)
        if ignoredPasteboardChangeCounts.count > 8 {
            ignoredPasteboardChangeCounts.remove(ignoredPasteboardChangeCounts.min() ?? changeCount)
        }
    }

    private func imagePasteboardItem(for path: String) -> NSPasteboardItem? {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else { return nil }

        let item = NSPasteboardItem()
        item.setString(url.absoluteString, forType: .fileURL)

        if let data = try? Data(contentsOf: url) {
            item.setData(data, forType: .png)
        }

        if let image = NSImage(contentsOf: url),
           let tiff = image.tiffRepresentation {
            item.setData(tiff, forType: .tiff)
        }

        return item
    }

    func storeImage(_ image: NSImage, id: UUID) -> (path: String, checksum: String)? {
        guard let data = image.losslessPNGData() else { return nil }
        let fileURL = mediaURL.appendingPathComponent("\(id.uuidString).png")
        do {
            try data.write(to: fileURL, options: .atomic)
            return (fileURL.path, Hashing.sha256(data))
        } catch {
            return nil
        }
    }

    func removeStoredImage(at path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }

    private func isDuplicate(_ entry: ClipboardEntry) -> Bool {
        guard let latest = entries.first else { return false }
        return latest.checksum == entry.checksum && latest.kind == entry.kind
    }

    private func startCleanupTimer() {
        cleanupTimer?.invalidate()
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pruneAndSaveIfNeeded()
            }
        }
    }

    private func pruneAndSaveIfNeeded() {
        if prune() {
            save()
        }
    }

    @discardableResult
    private func prune() -> Bool {
        let cutoff = Date().addingTimeInterval(-retention)
        let removedEntries = entries.filter { !$0.isFavorite && $0.createdAt < cutoff }
        let removedImages = removedEntries
            .compactMap(\.imagePath)

        entries.removeAll { !$0.isFavorite && $0.createdAt < cutoff }
        removeImagesIfUnused(removedImages)
        cleanupOrphanedMediaFiles(olderThan: cutoff)

        return !removedEntries.isEmpty
    }

    private func removeImagesIfUnused(_ paths: [String]) {
        for path in Set(paths) where !entries.contains(where: { $0.imagePath == path }) {
            removeStoredImage(at: path)
        }
    }

    private func cleanupOrphanedMediaFiles(olderThan cutoff: Date) {
        let referencedPaths = Set(entries.compactMap(\.imagePath))
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: mediaURL,
            includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for file in files {
            guard !referencedPaths.contains(file.path),
                  shouldDeleteOrphanedMediaFile(file, olderThan: cutoff) else {
                continue
            }
            try? FileManager.default.removeItem(at: file)
        }
    }

    private func shouldDeleteOrphanedMediaFile(_ file: URL, olderThan cutoff: Date) -> Bool {
        guard file.pathExtension.lowercased() == "png",
              let values = try? file.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey, .isRegularFileKey]),
              values.isRegularFile == true else {
            return false
        }

        let date = values.creationDate ?? values.contentModificationDate ?? .distantPast
        return date < cutoff
    }

    private func load() {
        guard let data = try? Data(contentsOf: historyURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = (try? decoder.decode([ClipboardEntry].self, from: data)) ?? []
        entries = decoded.map(rewritingLegacyImagePathIfNeeded)
        if entries != decoded {
            save()
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: historyURL, options: .atomic)
    }

    private func rewritingLegacyImagePathIfNeeded(_ entry: ClipboardEntry) -> ClipboardEntry {
        guard let imagePath = entry.imagePath,
              imagePath.contains("/Application Support/\(AppPaths.legacyAppFolderName)/") else {
            return entry
        }

        let fileName = URL(fileURLWithPath: imagePath).lastPathComponent
        let migratedPath = mediaURL.appendingPathComponent(fileName).path
        guard FileManager.default.fileExists(atPath: migratedPath) else { return entry }

        return ClipboardEntry(
            id: entry.id,
            createdAt: entry.createdAt,
            kind: entry.kind,
            preview: entry.preview,
            maskedPreview: entry.maskedPreview,
            fullText: entry.fullText,
            imagePath: migratedPath,
            filePaths: entry.filePaths,
            sourceAppName: entry.sourceAppName,
            sourceBundleID: entry.sourceBundleID,
            sourceColorHex: entry.sourceColorHex,
            checksum: entry.checksum,
            isFavorite: entry.isFavorite
        )
    }
}

extension ClipboardStore: ImageEditorOutput {
    func saveEditedImage(_ image: NSImage, title: String) -> Bool {
        addRenderedImage(image, title: title) != nil
    }
}
