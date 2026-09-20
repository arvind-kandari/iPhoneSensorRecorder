import Foundation

final class RecorderTest {

    private let session = RecordingSession()

    func configure() {
        session.configure()
    }

    func start() {
        session.start()
    }

    func stop() {
        session.stop()
        print("Recording test finished")
    }
}