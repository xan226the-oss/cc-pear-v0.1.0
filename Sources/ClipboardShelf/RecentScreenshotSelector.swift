import Foundation

struct RecentScreenshotReference: Equatable {
    let path: String
    let title: String
}

enum RecentScreenshotSelector {
    static func select(
        from entries: [ClipboardEntry],
        limit: Int = 10,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> [RecentScreenshotReference] {
        guard limit > 0 else { return [] }

        var seen = Set<String>()
        var result: [RecentScreenshotReference] = []

        for entry in entries
        where entry.kind == .image && entry.sourceBundleID == "com.apple.screencapture" {
            guard let rawPath = entry.imagePath else { continue }
            let path = URL(fileURLWithPath: rawPath)
                .standardizedFileURL
                .resolvingSymlinksInPath()
                .path
            guard fileExists(path), seen.insert(path).inserted else { continue }

            result.append(RecentScreenshotReference(path: path, title: entry.maskedPreview))
            if result.count == limit { break }
        }

        return result
    }
}
