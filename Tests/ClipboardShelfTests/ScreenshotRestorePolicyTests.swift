import Foundation

@main
enum ScreenshotRestorePolicyTests {
    static func main() throws {
        let visible = ScreenshotWindowVisibility(panel: true, editor: true, settings: true, onboarding: true)
        let afterCapture = ScreenshotRestorePolicy.visibility(after: .captured, before: visible)
        let afterCancellation = ScreenshotRestorePolicy.visibility(after: .cancelled, before: visible)

        try expect(afterCapture == ScreenshotWindowVisibility(), "successful capture must not reopen cc-pear windows")
        try expect(afterCancellation == visible, "cancelled capture must restore previously visible windows")
        print("ScreenshotRestorePolicyTests passed")
    }

    private static func expect(_ condition: Bool, _ message: String) throws {
        guard condition else { throw TestFailure(message: message) }
    }
}

private struct TestFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}
