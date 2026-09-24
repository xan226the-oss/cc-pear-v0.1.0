import AppKit
import Darwin
import Foundation

@MainActor
final class ScreenshotMonitor {
    private let store: ClipboardStore
    private var timer: Timer?
    private var desktopSource: DispatchSourceFileSystemObject?
    private var desktopFileDescriptor: CInt = -1
    private var seenKeys = Set<String>()

    init(store: ClipboardStore) {
        self.store = store
    }

    func start() {
        seedExistingDesktopFiles()
        scanDesktop(cutoff: Date().addingTimeInterval(-30 * 60))
        startDesktopWatcher()

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.scanDesktop(cutoff: Date().addingTimeInterval(-2 * 60))
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        desktopSource?.cancel()
        desktopSource = nil
    }

    private func seedExistingDesktopFiles() {
        let cutoff = Date().addingTimeInterval(-2 * 24 * 60 * 60)
        for file in screenshotFiles(cutoff: cutoff) {
            if file.date < Date().addingTimeInterval(-30 * 60) {
                seenKeys.insert(file.key)
            }
        }
    }

    private func scanDesktop(cutoff: Date) {
        for file in screenshotFiles(cutoff: cutoff) {
            guard !seenKeys.contains(file.key) else { continue }
            if addScreenshot(file.url, createdAt: file.date) {
                seenKeys.insert(file.key)
            }
        }
    }

    @discardableResult
    private func addScreenshot(_ url: URL, createdAt: Date) -> Bool {
        guard fileLooksReady(url),
              let image = NSImage(contentsOf: url) else {
            return false
        }

        let id = UUID()
        guard let stored = store.storeImage(image, id: id) else { return false }

        if store.hasImageChecksum(stored.checksum) {
            store.removeStoredImage(at: stored.path)
            return true
        }

        let entry = ClipboardEntry(
            id: id,
            createdAt: createdAt,
            kind: .image,
            preview: url.lastPathComponent,
            maskedPreview: url.lastPathComponent,
            fullText: nil,
            imagePath: stored.path,
            filePaths: [url.path],
            sourceAppName: "系统截图",
            sourceBundleID: "com.apple.screencapture",
            sourceColorHex: "#0A84FF",
            checksum: stored.checksum
        )
        store.add(entry)
        return true
    }

    private func startDesktopWatcher() {
        let desktop = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
        let fd = open(desktop.path, O_EVTONLY)
        guard fd >= 0 else { return }

        desktopFileDescriptor = fd
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .attrib, .rename],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.scanSoon()
            }
        }
        source.setCancelHandler { [fd] in
            close(fd)
        }
        source.resume()
        desktopSource = source
    }

    private func scanSoon() {
        scanDesktop(cutoff: Date().addingTimeInterval(-2 * 60))

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            Task { @MainActor in
                self?.scanDesktop(cutoff: Date().addingTimeInterval(-2 * 60))
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            Task { @MainActor in
                self?.scanDesktop(cutoff: Date().addingTimeInterval(-2 * 60))
            }
        }
    }

    private func fileLooksReady(_ url: URL) -> Bool {
        guard let first = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              first > 0 else {
            return false
        }

        Thread.sleep(forTimeInterval: 0.03)
        guard let second = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            return false
        }

        return first == second
    }

    private func screenshotFiles(cutoff: Date) -> [(url: URL, date: Date, key: String)] {
        let desktop = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: desktop,
            includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return urls.compactMap { url in
            guard isScreenshotFile(url) else { return nil }
            guard let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true else {
                return nil
            }

            let date = values.creationDate ?? values.contentModificationDate ?? .distantPast
            guard date >= cutoff else { return nil }

            let mod = values.contentModificationDate ?? date
            return (url, date, "\(url.path)|\(Int(mod.timeIntervalSince1970))")
        }
        .sorted { $0.date < $1.date }
    }

    private func isScreenshotFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        guard ["png", "jpg", "jpeg", "heic", "tiff"].contains(ext) else { return false }

        let name = url.deletingPathExtension().lastPathComponent.lowercased()
        return name.hasPrefix("screenshot")
            || name.hasPrefix("screen shot")
            || name.hasPrefix("截屏")
            || name.hasPrefix("屏幕快照")
    }
}
