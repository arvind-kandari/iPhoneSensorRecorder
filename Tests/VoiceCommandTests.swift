// Run: swiftc Sources/VoiceCommand.swift Sources/RecordingState.swift Tests/VoiceCommandTests.swift -o /tmp/voice-command-tests && /tmp/voice-command-tests
@main
enum VoiceCommandTests {
    static func main() {
        let valid: [(String, VoiceCommand)] = [
            ("Start recording", .start(0)),
            (" START  RECORDING! ", .start(0)),
            ("Start recording in 5 seconds", .start(5)),
            ("start recording in five seconds.", .start(5)),
            ("Start recording in 10 seconds", .start(10)),
            ("start recording in TEN seconds", .start(10)),
            ("Stop recording", .stop),
            ("Pause recording", .pause),
            ("Resume recording", .resume)
        ]
        for (text, expected) in valid {
            precondition(VoiceCommand.parse(text) == expected, "Rejected command: \(text)")
        }
        for text in ["", "start", "start recording in", "start recording in 3 seconds",
                     "start recording in 15 seconds", "don't start recording", "please stop recording",
                     "Hey Sensor start recording", "start recording and stop recording", "take a photo"] {
            precondition(VoiceCommand.parse(text) == nil, "Accepted unsupported command: \(text)")
        }
        for seconds in [5, 10] {
            precondition(VoiceCommand.recognized("Start recording", isFinal: false) == nil)
            precondition(VoiceCommand.recognized("Start recording in", isFinal: false) == nil)
            precondition(VoiceCommand.recognized("Start recording in \(seconds) seconds", isFinal: false) == nil)
            precondition(VoiceCommand.recognized("Start recording in \(seconds) seconds", isFinal: true) == .start(seconds))
        }
        precondition(VoiceCommand.recognized("Start recording", isFinal: true) == .start(0))
        for (text, expected) in valid {
            precondition(VoiceCommand.recognized(text, isFinal: false, utteranceEnded: false) == nil)
            precondition(VoiceCommand.recognized(text, isFinal: false, utteranceEnded: true) == expected)
        }
        precondition(VoiceCommand.recognized("Start recording in", isFinal: false, utteranceEnded: true) == nil)

        for seconds in [5, 10] {
            let partials = ["Start", "Start recording", "Start recording in",
                            "Start recording in \(seconds)", "Start recording in \(seconds) seconds"]
            for text in partials {
                precondition(VoiceCommand.recognized(text, isFinal: false) == nil)
            }
            let complete = partials.last!
            precondition(VoiceCommand.recognized(complete, isFinal: false, utteranceEnded: true) == .start(seconds))
            precondition(VoiceCommand.recognized(complete, isFinal: true) != .start(0))
        }

        var changingNoise = VoiceUtteranceBoundary()
        precondition(!changingNoise.shouldEnd(level: 0, time: 0))
        // Startup silence must expire even when the later background never returns to zero.
        for tick in 1...200 {
            _ = changingNoise.shouldEnd(level: 0.025, time: Double(tick) / 10)
        }
        changingNoise.heardTranscript(at: 20)
        precondition(!changingNoise.shouldEnd(level: 0.12, time: 20.1))
        precondition(!changingNoise.shouldEnd(level: 0.025, time: 20.5))
        precondition(changingNoise.shouldEnd(level: 0.025, time: 21.2))

        var continuingSpeech = VoiceUtteranceBoundary()
        precondition(!continuingSpeech.shouldEnd(level: 0.002, time: 0))
        for tick in 1...40 {
            precondition(!continuingSpeech.shouldEnd(level: 0.12, time: Double(tick) / 10))
        }
        precondition(!continuingSpeech.shouldEnd(level: .nan, time: 4.1))
        precondition(!continuingSpeech.shouldEnd(level: -1, time: 4.2))

        var noisyBoundary = VoiceUtteranceBoundary()
        precondition(!noisyBoundary.shouldEnd(level: 0.025, time: 0))
        noisyBoundary.heardTranscript(at: 1)
        precondition(!noisyBoundary.shouldEnd(level: 0.12, time: 1.2))
        precondition(!noisyBoundary.shouldEnd(level: 0.025, time: 1.8))
        precondition(noisyBoundary.shouldEnd(level: 0.025, time: 2.3))

        var quietBoundary = VoiceUtteranceBoundary()
        precondition(!quietBoundary.shouldEnd(level: 0.002, time: 0))
        quietBoundary.heardTranscript(at: 1)
        precondition(!quietBoundary.shouldEnd(level: 0.002, time: 1.5))
        precondition(quietBoundary.shouldEnd(level: 0.002, time: 2.1))

        var boundary = VoiceUtteranceBoundary()
        precondition(!boundary.shouldEnd(level: 0, time: 0))
        precondition(!boundary.shouldEnd(level: 0.1, time: 1))
        precondition(!boundary.shouldEnd(level: 0.1, time: 3))
        precondition(!boundary.shouldEnd(level: 0, time: 3.4))
        precondition(boundary.shouldEnd(level: 0, time: 4))

        for initial in [RecordingState.recording, .paused] {
            var state = initial
            var stops = 0
            for _ in 0..<2 {
                if state.canStop {
                    stops += 1
                    state = .finishing
                }
            }
            precondition(stops == 1)
            precondition(!state.canStop && !state.canPause && !state.canResume && !state.canStart)
            state = .ready
            precondition(state.canStart)
        }
        precondition(RecordingState.recording.canPause)
        precondition(RecordingState.paused.canResume)
        print("Passed parser, final-result, utterance-boundary, and finalization-guard tests.")
    }
}
