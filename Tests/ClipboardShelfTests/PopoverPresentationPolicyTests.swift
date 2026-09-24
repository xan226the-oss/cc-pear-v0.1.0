import Foundation

@main
enum PopoverPresentationPolicyTests {
    static func main() throws {
        try expect(
            !PopoverPresentationPolicy.activatesApplication,
            "showing the clipboard panel must not take focus from the current application"
        )
        print("PopoverPresentationPolicyTests passed")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else {
            throw TestFailure(message: message)
        }
    }
}

private struct TestFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}
