import AVFoundation
import Combine
import Speech

final class VoiceCommands: ObservableObject {
    @Published private(set) var status = "Off"
    var onCommand: (@MainActor (VoiceCommand) -> Void)?

    private let queue = DispatchQueue(label: "CapturE.VoiceCommands")
    private var enabled = false
    private var generation = 0
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var renewal: DispatchWorkItem?
    private var boundary = VoiceUtteranceBoundary()
    private var awaitingFinal = false
    private var latestTranscript = ""
    private var completionFallback: DispatchWorkItem?
    private var audioBuffersReceived = 0
    private var loggedUnsupportedAudio = false
    private var audioInterrupted = false
    private var audioObservers: [NSObjectProtocol] = []

    init() {
        for name in [AVAudioSession.interruptionNotification, AVAudioSession.routeChangeNotification] {
            audioObservers.append(NotificationCenter.default.addObserver(
                forName: name, object: AVAudioSession.sharedInstance(), queue: nil
            ) { [weak self] notification in
                let value = (notification.userInfo?[name == AVAudioSession.interruptionNotification
                    ? AVAudioSessionInterruptionTypeKey : AVAudioSessionRouteChangeReasonKey] as? NSNumber)?.uintValue
                self?.queue.async { [weak self] in
                    self?.handleAudioEvent(name: name, value: value)
                }
            })
        }
    }

    private func handleAudioEvent(name: Notification.Name, value: UInt?) {
        if name == AVAudioSession.interruptionNotification {
            VoiceCommandDebug.log("Audio interruption: type=\(String(describing: value)), listening=\(enabled)")
            guard let value, let type = AVAudioSession.InterruptionType(rawValue: value) else { return }
            audioInterrupted = type == .began
            if audioInterrupted {
                if request != nil { stopRequest() }
                if enabled { report("Speech recognition interrupted.") }
            } else if enabled, recognizer != nil {
                scheduleRestart(after: 0.3)
            }
        } else {
            let session = AVAudioSession.sharedInstance()
            VoiceCommandDebug.log("Audio route change: reason=\(String(describing: value)), inputs=\(session.currentRoute.inputs.map { $0.portType.rawValue }), listening=\(enabled)")
            // The capture session still owns the microphone and its audio configuration.
            if request != nil { stopRequest() }
            if enabled, !audioInterrupted, recognizer != nil { scheduleRestart(after: 0.3) }
        }
    }

    func setListening(_ listening: Bool) {
        queue.async { [weak self] in
            guard let self, self.enabled != listening else { return }
            self.enabled = listening
            VoiceCommandDebug.log("Listening requested: \(listening)")
            self.stopRequest()
            let activation = self.generation
            guard listening else {
                self.report("Off")
                return
            }
            self.recognizer = nil
            self.report("Requesting permission…")
            SFSpeechRecognizer.requestAuthorization { [weak self] authorization in
                guard let self else { return }
                self.queue.async {
                    guard self.enabled, self.generation == activation else { return }
                    VoiceCommandDebug.log("Speech permission: \(authorization.rawValue)")
                    guard authorization == .authorized else {
                        self.report("Speech permission denied. Enable it in iPhone Settings.")
                        return
                    }
                    AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                        guard let self else { return }
                        self.queue.async {
                            guard self.enabled, self.generation == activation else { return }
                            VoiceCommandDebug.log("Microphone permission granted: \(granted)")
                            guard granted else {
                                self.report("Microphone permission denied. Enable it in iPhone Settings.")
                                return
                            }
                            self.recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
                            self.startRequest()
                        }
                    }
                }
            }
        }
    }

    func append(_ sampleBuffer: CMSampleBuffer) {
        queue.async { [weak self] in
            guard let self, self.enabled, !self.awaitingFinal,
                  let request = self.request else { return }
            self.audioBuffersReceived += 1
            if self.audioBuffersReceived == 1 {
                VoiceCommandDebug.log("Audio input received; forwarding to SFSpeechRecognizer. Samples=\(CMSampleBufferGetNumSamples(sampleBuffer))")
            }
            request.appendAudioSampleBuffer(sampleBuffer)
            let level = self.audioLevel(sampleBuffer)
            if self.audioBuffersReceived % 200 == 0 {
                VoiceCommandDebug.log("Audio input heartbeat: buffers=\(self.audioBuffersReceived), RMS=\(String(describing: level))")
            }
            if level == nil && !self.loggedUnsupportedAudio {
                self.loggedUnsupportedAudio = true
                VoiceCommandDebug.log("Audio level unavailable: \(String(describing: CMSampleBufferGetFormatDescription(sampleBuffer)))")
            }
            if let level,
               self.boundary.shouldEnd(level: level, time: ProcessInfo.processInfo.systemUptime) {
                self.awaitingFinal = true
                VoiceCommandDebug.log("Microphone-confirmed end of utterance; ending recognition audio")
                request.endAudio()
                let currentGeneration = self.generation
                let fallback = DispatchWorkItem { [weak self] in
                    guard let self, self.enabled, self.awaitingFinal,
                          self.generation == currentGeneration else { return }
                    self.completeUtterance(isFinal: false)
                }
                self.completionFallback = fallback
                self.queue.asyncAfter(deadline: .now() + 0.5, execute: fallback)
            }
        }
    }

    func suspend(reason: String = "countdown") {
        queue.sync {
            enabled = false
            VoiceCommandDebug.log("Recognition suspended: \(reason)")
            stopRequest()
            report("Suspended during \(reason)")
        }
    }

    private func audioLevel(_ buffer: CMSampleBuffer) -> Double? {
        guard let description = CMSampleBufferGetFormatDescription(buffer),
              let format = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee,
              format.mFormatID == kAudioFormatLinearPCM,
              format.mFormatFlags & kAudioFormatFlagIsBigEndian == 0 else { return nil }
        let isFloat = format.mFormatFlags & kAudioFormatFlagIsFloat != 0
        let isSigned = format.mFormatFlags & kAudioFormatFlagIsSignedInteger != 0
        guard (isFloat && (format.mBitsPerChannel == 32 || format.mBitsPerChannel == 64)) ||
              (isSigned && (format.mBitsPerChannel == 16 || format.mBitsPerChannel == 32)) else { return nil }
        let stride = Int(format.mBitsPerChannel / 8)
        var listSize = 0
        CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            buffer, bufferListSizeNeededOut: &listSize, bufferListOut: nil, bufferListSize: 0,
            blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: 0, blockBufferOut: nil
        )
        guard listSize >= MemoryLayout<AudioBufferList>.size else { return nil }
        let storage = UnsafeMutableRawPointer.allocate(byteCount: listSize, alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { storage.deallocate() }
        let list = storage.bindMemory(to: AudioBufferList.self, capacity: 1)
        var retainedBlock: CMBlockBuffer?
        let result = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            buffer, bufferListSizeNeededOut: nil, bufferListOut: list, bufferListSize: listSize,
            blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: 0, blockBufferOut: &retainedBlock
        )
        guard result == noErr else { return nil }
        return withExtendedLifetime(retainedBlock) {
            var sum = 0.0
            var count = 0
            for audioBuffer in UnsafeMutableAudioBufferListPointer(list) {
                guard let data = audioBuffer.mData, Int(audioBuffer.mDataByteSize) >= stride else { continue }
                let bytes = UnsafeRawBufferPointer(start: data, count: Int(audioBuffer.mDataByteSize))
                for offset in Swift.stride(from: 0, through: bytes.count - stride, by: stride) {
                    let value: Double
                    if isFloat {
                        value = stride == 4
                            ? Double(bytes.loadUnaligned(fromByteOffset: offset, as: Float.self))
                            : bytes.loadUnaligned(fromByteOffset: offset, as: Double.self)
                    } else {
                        value = stride == 2
                            ? Double(bytes.loadUnaligned(fromByteOffset: offset, as: Int16.self)) / 32768
                            : Double(bytes.loadUnaligned(fromByteOffset: offset, as: Int32.self)) / 2147483648
                    }
                    sum += value * value
                    count += 1
                }
            }
            return count > 0 ? sqrt(sum / Double(count)) : nil
        }
    }

    private func startRequest() {
        guard enabled, !audioInterrupted, let recognizer else { return }
        stopRequest()
        VoiceCommandDebug.log("Recognizer availability: available=\(recognizer.isAvailable), onDevice=\(recognizer.supportsOnDeviceRecognition)")
        guard recognizer.supportsOnDeviceRecognition else {
            report("On-device English speech recognition is unavailable on this iPhone.")
            return
        }
        guard recognizer.isAvailable else {
            report("Speech recognition is unavailable. Retrying…")
            scheduleRestart(after: 5)
            return
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.contextualStrings = [
            "Start recording", "Start recording in 5 seconds", "Start recording in 10 seconds",
            "Stop recording", "Pause recording", "Resume recording"
        ]
        self.request = request
        let currentGeneration = generation
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            self.queue.async {
                guard self.enabled, self.generation == currentGeneration else {
                    VoiceCommandDebug.log("Recognition callback ignored: disabled or stale request")
                    return
                }
                if let result {
                    let text = result.bestTranscription.formattedString
                    VoiceCommandDebug.log("\(result.isFinal ? "Final" : "Partial") transcript: \(text)")
                    if text != self.latestTranscript && !self.awaitingFinal {
                        self.boundary.heardTranscript(at: ProcessInfo.processInfo.systemUptime)
                    }
                    self.latestTranscript = text
                    if result.isFinal {
                        self.completeUtterance(isFinal: true)
                        return
                    }
                }
                if let error {
                    VoiceCommandDebug.log("Recognition error: \(error.localizedDescription)")
                    if self.awaitingFinal {
                        self.completeUtterance(isFinal: false)
                        return
                    }
                    self.stopRequest()
                    self.report("Speech recognition interrupted: \(error.localizedDescription)")
                    self.scheduleRestart(after: 5)
                }
            }
        }
        report("Listening for the six recording commands (English, on-device).")
        let audioSession = AVAudioSession.sharedInstance()
        VoiceCommandDebug.log("Recognizer started: generation=\(generation), category=\(audioSession.category.rawValue), mode=\(audioSession.mode.rawValue), rate=\(audioSession.sampleRate), inputs=\(audioSession.currentRoute.inputs.map { $0.portType.rawValue })")
        queue.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, self.enabled, self.generation == currentGeneration,
                  self.audioBuffersReceived == 0 else { return }
            VoiceCommandDebug.log("WARNING: recognizer started but no microphone audio received")
        }
        scheduleRestart(after: 50)
    }

    private func scheduleRestart(after seconds: Double) {
        renewal?.cancel()
        let restartGeneration = generation
        VoiceCommandDebug.log("Recognition restart scheduled in \(seconds)s; generation=\(restartGeneration)")
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.enabled, !self.audioInterrupted,
                  self.generation == restartGeneration else { return }
            VoiceCommandDebug.log("Recognition restarting; generation=\(restartGeneration)")
            self.startRequest()
        }
        renewal = work
        queue.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func completeUtterance(isFinal: Bool) {
        let command = VoiceCommand.recognized(latestTranscript, isFinal: isFinal, utteranceEnded: awaitingFinal)
        VoiceCommandDebug.log("Parsed VoiceCommand: \(String(describing: command)); final=\(isFinal), microphoneEnded=\(awaitingFinal)")
        if command == nil { VoiceCommandDebug.log("Command ignored: utterance does not match one of the six commands") }
        if case .start(let seconds)? = command, seconds > 0 {
            enabled = false
            stopRequest()
        } else {
            startRequest()
        }
        let deliveryGeneration = generation
        guard let command else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard self.queue.sync(execute: { self.generation == deliveryGeneration }) else {
                VoiceCommandDebug.log("Command ignored: request invalidated before main-thread delivery")
                return
            }
            guard let onCommand = self.onCommand else {
                VoiceCommandDebug.log("Command ignored: no ContentView action handler")
                return
            }
            VoiceCommandDebug.log("Delivering command to ContentView: \(command)")
            onCommand(command)
        }
    }

    private func stopRequest() {
        generation += 1
        renewal?.cancel()
        renewal = nil
        completionFallback?.cancel()
        completionFallback = nil
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        boundary = VoiceUtteranceBoundary()
        awaitingFinal = false
        latestTranscript = ""
        audioBuffersReceived = 0
        loggedUnsupportedAudio = false
    }

    private func report(_ message: String) {
        DispatchQueue.main.async { [weak self] in self?.status = message }
    }

    deinit {
        for observer in audioObservers { NotificationCenter.default.removeObserver(observer) }
        completionFallback?.cancel()
        renewal?.cancel()
        request?.endAudio()
        task?.cancel()
    }
}
