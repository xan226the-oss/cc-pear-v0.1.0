import Foundation

@MainActor
final class CommandSignalMonitor {
    private let action: () -> Void
    private var timer: Timer?
    private var lastSeenDate: Date?

    init(action: @escaping () -> Void) {
        self.action = action
        lastSeenDate = Self.signalDate()
    }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard let date = Self.signalDate() else { return }
        if lastSeenDate == nil || date > (lastSeenDate ?? .distantPast) {
            lastSeenDate = date
            action()
        }
    }

    static func signalURL() -> URL? {
        try? AppPaths.supportDirectory().appendingPathComponent("show.request")
    }

    private static func signalDate() -> Date? {
        guard let url = signalURL(),
              let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]) else {
            return nil
        }
        return values.contentModificationDate
    }
}
