import Foundation

struct ScreenshotWindowVisibility: Equatable {
    var panel = false
    var editor = false
    var settings = false
    var onboarding = false
}

enum ScreenshotCompletionOutcome {
    case captured
    case cancelled
}

enum ScreenshotRestorePolicy {
    static func visibility(
        after outcome: ScreenshotCompletionOutcome,
        before visibility: ScreenshotWindowVisibility
    ) -> ScreenshotWindowVisibility {
        switch outcome {
        case .captured:
            ScreenshotWindowVisibility()
        case .cancelled:
            visibility
        }
    }
}
