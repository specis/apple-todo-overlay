import Foundation

final class BackgroundScheduler {
    static let shared = BackgroundScheduler()
    private var timer: Timer?
    private init() {}

    /// Starts a repeating timer that fires `action` every `interval` seconds.
    /// Calling `start` again replaces any existing timer.
    func start(interval: TimeInterval = 15 * 60, action: @escaping () async -> Void) {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            Task { await action() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
