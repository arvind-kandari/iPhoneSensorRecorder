import Foundation

final class TimeSynchronizer {

    private var startTime: TimeInterval?
    private var pausedAt: TimeInterval?
    private var pausedDuration: TimeInterval = 0

    func start() {

        startTime =
            ProcessInfo.processInfo.systemUptime
        pausedAt = nil
        pausedDuration = 0
    }

    func reset() {

        startTime = nil
        pausedAt = nil
        pausedDuration = 0
    }

    func pause() {
        pausedAt = ProcessInfo.processInfo.systemUptime
    }

    func resume() {
        guard let pausedAt else { return }
        pausedDuration += ProcessInfo.processInfo.systemUptime - pausedAt
        self.pausedAt = nil
    }

    func timestamp() -> TimeInterval {

        guard let startTime = startTime else {
            return 0
        }

        let now = pausedAt ?? ProcessInfo.processInfo.systemUptime
        return now - startTime - pausedDuration
    }
}
