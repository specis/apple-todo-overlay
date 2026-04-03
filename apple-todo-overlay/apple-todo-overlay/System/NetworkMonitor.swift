import Network

final class NetworkMonitor {
    static let shared = NetworkMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.apple-todo-overlay.network")

    private(set) var isConnected = false
    var onConnected: (() -> Void)?

    private init() {}

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let wasConnected = self.isConnected
            let nowConnected = path.status == .satisfied
            self.isConnected = nowConnected
            if !wasConnected && nowConnected {
                self.onConnected?()
            }
        }
        monitor.start(queue: queue)
    }

    func stop() {
        monitor.cancel()
    }
}
