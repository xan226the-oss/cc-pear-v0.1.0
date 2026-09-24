import Foundation

@main
enum RecentScreenshotSelectorTests {
    static func main() throws {
        try selectsNewestTenValidSystemScreenshots()
        print("RecentScreenshotSelectorTests passed")
    }

    private static func selectsNewestTenValidSystemScreenshots() throws {
        let screenshots = (0..<12).map { index in
            entry(
                path: "/shot-\(index).png",
                sourceBundleID: "com.apple.screencapture",
                title: "Shot \(index)"
            )
        }
        let entries = [
            screenshots[0],
            entry(path: "/copied.png", sourceBundleID: "com.apple.Safari", title: "Copied"),
            entry(path: "/missing.png", sourceBundleID: "com.apple.screencapture", title: "Missing"),
            entry(path: "/shot-0.png", sourceBundleID: "com.apple.screencapture", title: "Duplicate")
        ] + Array(screenshots.dropFirst())

        let result = RecentScreenshotSelector.select(
            from: entries,
            limit: 10,
            fileExists: { $0 != "/missing.png" }
        )
        let expectedNewestPaths = (0..<10).map { "/shot-\($0).png" }

        try expect(result.count == 10, "selector did not enforce the ten-item limit")
        try expect(result.map(\.path) == expectedNewestPaths, "selector changed newest-first order")
        try expect(!result.contains { $0.path == "/copied.png" }, "selector included a non-screenshot image")
        try expect(!result.contains { $0.path == "/missing.png" }, "selector included a missing file")
        try expect(result.filter { $0.path == "/shot-0.png" }.count == 1, "selector did not deduplicate paths")
    }

    private static func entry(path: String, sourceBundleID: String, title: String) -> ClipboardEntry {
        ClipboardEntry(
            id: UUID(),
            createdAt: Date(),
            kind: .image,
            preview: title,
            maskedPreview: title,
            fullText: nil,
            imagePath: path,
            filePaths: [],
            sourceAppName: "Test",
            sourceBundleID: sourceBundleID,
            sourceColorHex: "#000000",
            checksum: UUID().uuidString
        )
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw TestFailure(message: message) }
    }
}

private struct TestFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}
