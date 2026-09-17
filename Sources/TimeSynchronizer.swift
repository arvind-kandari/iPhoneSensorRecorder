import Foundation

final class TimeSynchronizer {

    private var startTime: TimeInterval?

    func start() {

        startTime =
            ProcessInfo.processInfo.systemUptime
    }

    func reset() {

        startTime = nil
    }

    func timestamp() -> TimeInterval {

        guard let startTime = startTime else {
            return 0
        }

        return ProcessInfo.processInfo.systemUptime
            - startTime
    }
}