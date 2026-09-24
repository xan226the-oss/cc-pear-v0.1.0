import AppKit
import SwiftUI

@MainActor
@main
enum ImageEditorViewCompileTests {
    static func main() {
        let store = ImageEditorStore(output: NoopOutput())
        let view = ImageEditorView(store: store)
        _ = view.body
        print("ImageEditorViewCompileTests passed")
    }
}

@MainActor
private final class NoopOutput: ImageEditorOutput {
    func saveEditedImage(_ image: NSImage, title: String) -> Bool { true }
}
