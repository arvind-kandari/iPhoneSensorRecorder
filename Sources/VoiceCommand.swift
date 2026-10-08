import Foundation

enum VoiceCommand: Equatable {
    case start(Int)
    case stop
    case pause
    case resume

    static func recognized(_ text: String, isFinal: Bool, utteranceEnded: Bool = false) -> VoiceCommand? {
        (isFinal || utteranceEnded) ? parse(text) : nil
    }

    static func parse(_ text: String) -> VoiceCommand? {
        let words = text.lowercased().split { !$0.isLetter && !$0.isNumber }
        switch words.joined(separator: " ") {
        case "start recording": return .start(0)
        case "start recording in 5 seconds", "start recording in five seconds": return .start(5)
        case "start recording in 10 seconds", "start recording in ten seconds": return .start(10)
        case "stop recording": return .stop
        case "pause recording": return .pause
        case "resume recording": return .resume
        default: return nil
        }
    }
}

struct VoiceUtteranceBoundary {
    private var lastSpeechTime: TimeInterval?
    private var noiseFloor: Double?

    mutating func heardTranscript(at time: TimeInterval) {
        lastSpeechTime = time
    }

    mutating func shouldEnd(level: Double, time: TimeInterval) -> Bool {
        guard level.isFinite else { return false }
        noiseFloor = min(noiseFloor ?? level, level)
        let threshold = max(0.008, (noiseFloor ?? 0) * 2.5)
        if level > threshold {
            lastSpeechTime = time
            return false
        }
        guard let lastSpeechTime else { return false }
        return time - lastSpeechTime >= 1.0
    }
}
