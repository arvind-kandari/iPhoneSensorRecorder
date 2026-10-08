import Foundation

enum RecordingState: Equatable {

    case idle

    case configuring

    case ready

    case recording

    case paused

    case finishing

    case error(String)

    var canStart: Bool { self == .ready }
    var canPause: Bool { self == .recording }
    var canResume: Bool { self == .paused }
    var canStop: Bool { self == .recording || self == .paused }
}
