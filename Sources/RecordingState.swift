import Foundation

enum RecordingState: Equatable {

    case idle

    case configuring

    case ready

    case recording

    case paused

    case finishing

    case error(String)
}
