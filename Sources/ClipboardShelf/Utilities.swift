import AppKit
import CryptoKit
import Foundation

enum AppPaths {
    static let appFolderName = "cc-pear"
    static let legacyAppFolderName = "ClipboardShelf"

    static func supportDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent(appFolderName, isDirectory: true)
        try migrateLegacySupportDirectoryIfNeeded(base: base, target: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func mediaDirectory() throws -> URL {
        let directory = try supportDirectory().appendingPathComponent("Media", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func clearSupportDirectory() {
        guard let directory = try? supportDirectory() else { return }
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let media = directory.appendingPathComponent("Media", isDirectory: true)
        try? FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
    }

    private static func migrateLegacySupportDirectoryIfNeeded(base: URL, target: URL) throws {
        let fileManager = FileManager.default
        let legacy = base.appendingPathComponent(legacyAppFolderName, isDirectory: true)
        let history = target.appendingPathComponent("history.json")
        guard !fileManager.fileExists(atPath: history.path),
              fileManager.fileExists(atPath: legacy.path) else {
            return
        }

        try fileManager.createDirectory(at: target, withIntermediateDirectories: true)

        let legacyHistory = legacy.appendingPathComponent("history.json")
        if fileManager.fileExists(atPath: legacyHistory.path) {
            try? fileManager.copyItem(at: legacyHistory, to: history)
        }

        let legacyMedia = legacy.appendingPathComponent("Media", isDirectory: true)
        let media = target.appendingPathComponent("Media", isDirectory: true)
        if fileManager.fileExists(atPath: legacyMedia.path) {
            try? fileManager.copyItem(at: legacyMedia, to: media)
        }
    }
}

enum Hashing {
    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func sha256(_ string: String) -> String {
        sha256(Data(string.utf8))
    }
}

extension NSImage {
    func losslessPNGData() -> Data? {
        guard let tiff = tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }

    func pngData(maxPixelSize: CGFloat = 960) -> Data? {
        let image = resizedToFit(maxPixelSize: maxPixelSize)
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }

    private func resizedToFit(maxPixelSize: CGFloat) -> NSImage {
        let largestSide = max(size.width, size.height)
        guard largestSide > maxPixelSize, largestSide > 0 else {
            return self
        }

        let scale = maxPixelSize / largestSide
        let newSize = NSSize(width: size.width * scale, height: size.height * scale)
        let image = NSImage(size: newSize)
        image.lockFocus()
        draw(in: NSRect(origin: .zero, size: newSize), from: .zero, operation: .copy, fraction: 1)
        image.unlockFocus()
        return image
    }
}

extension String {
    var trimmedSingleLine: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    var isLikelyURL: Bool {
        guard let url = URL(string: self.trimmedSingleLine),
              let scheme = url.scheme?.lowercased() else {
            return false
        }
        return scheme == "http" || scheme == "https" || scheme == "ftp"
    }
}

enum SourceColor {
    static func hex(for bundleID: String?, appName: String) -> String {
        let known: [String: String] = [
            "com.google.Chrome": "#4B8BF4",
            "com.tencent.xinWeChat": "#15B857",
            "com.tencent.WeWorkMac": "#2A7DFF",
            "com.microsoft.Word": "#2B579A",
            "com.apple.Safari": "#00A2FF",
            "com.apple.TextEdit": "#667085",
            "com.apple.finder": "#0A84FF"
        ]

        if let bundleID, let color = known[bundleID] {
            return color
        }

        let seed = abs((bundleID ?? appName).hashValue)
        let palette = ["#E5484D", "#F76808", "#F5A524", "#12A150", "#0091FF", "#7C3AED", "#DB2777", "#64748B"]
        return palette[seed % palette.count]
    }
}

extension Date {
    var shortTimeText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: self)
    }
}
