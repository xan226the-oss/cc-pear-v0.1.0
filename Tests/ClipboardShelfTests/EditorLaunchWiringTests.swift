import Foundation

@main
enum EditorLaunchWiringTests {
    static func main() throws {
        let source = try String(
            contentsOfFile: "Sources/ClipboardShelf/AppDelegate.swift",
            encoding: .utf8
        )
        guard source.contains("recentScreenshots: store.recentScreenshots(limit: 10)") else {
            throw WiringFailure()
        }
        print("EditorLaunchWiringTests passed")
    }
}

private struct WiringFailure: Error {}
