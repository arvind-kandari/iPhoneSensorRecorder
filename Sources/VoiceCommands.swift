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

    func setListening(_ listening: Bool) {
        queue.async { [weak self] in
            guard let self, self.enabled != listening else { return }
            self.enabled = listening
            self.stopRequest()
            let activation = self.generation
            guard listening else {
                self.report("Off")
                return
            }
            self.report("Requesting permission…")
            SFSpeechRecognizer.requestAuthorization { [weak self] authorization in
                guard let self else { return }
                self.queue.async {
                    guard self.enabled, self.generation == activation else { return }
                    guard authorization == .authorized else {
                        self.report("Speech permission denied. Enable it in iPhone Settings.")
                        return
                    }
                    AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                        guard let self else { return }
                        self.queue.async {
                            guard self.enabled, self.generation == activation else { return }
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
            request.appendAudioSampleBuffer(sampleBuffer)
            if let level = self.audioLevel(sampleBuffer),
               self.boundary.shouldEnd(level: level, time: ProcessInfo.processInfo.systemUptime) {
                self.awaitingFinal = true
                request.endAudio()
            }
        }
    }

    @MainActor
    func suspend() {
        queue.sync {
            enabled = false
            stopRequest()
            report("Suspended during countdown")
        }
    }

    private func audioLevel(_ buffer: CMSampleBuffer) -> Double? {
        guard let description = CMSampleBufferGetFormatDescription(buffer),
              let format = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee,
              format.mFormatID == kAudioFormatLinearPCM,
              format.mFormatFlags & kAudioFormatFlagIsBigEndian == 0,
              let dataBuffer = CMSampleBufferGetDataBuffer(buffer) else { return nil }
        let isFloat = format.mFormatFlags & kAudioFormatFlagIsFloat != 0
        let isSigned = format.mFormatFlags & kAudioFormatFlagIsSignedInteger != 0
        guard (isFloat && (format.mBitsPerChannel == 32 || format.mBitsPerChannel == 64)) ||
              (isSigned && (format.mBitsPerChannel == 16 || format.mBitsPerChannel == 32)) else { return nil }
        let length = CMBlockBufferGetDataLength(dataBuffer)
        let stride = Int(format.mBitsPerChannel / 8)
        guard length >= stride else { return nil }
        var data = Data(count: length)
        let copied = data.withUnsafeMutableBytes { (bytes: UnsafeMutableRawBufferPointer) -> OSStatus in
            guard let destination = bytes.baseAddress else { return -1 }
            return CMBlockBufferCopyDataBytes(dataBuffer, atOffset: 0, dataLength: length, destination: destination)
        }
        guard copied == kCMBlockBufferNoErr else { return nil }
        return data.withUnsafeBytes { bytes in
            var sum = 0.0
            for offset in Swift.stride(from: 0, through: length - stride, by: stride) {
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
            }
            return sqrt(sum / Double(length / stride))
        }
    }

    private func startRequest() {
        stopRequest()
        guard enabled, let recognizer else { return }
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
                guard self.enabled, self.generation == currentGeneration else { return }
                if let result, result.isFinal {
                    let command = VoiceCommand.recognized(
                        result.bestTranscription.formattedString,
                        isFinal: result.isFinal
                    )
                    if case .start(let seconds)? = command, seconds > 0 {
                        self.enabled = false
                        self.stopRequest()
                    } else {
                        self.startRequest()
                    }
                    let deliveryGeneration = self.generation
                    if let command {
                        DispatchQueue.main.async { [weak self] in
                            guard let self,
                                  self.queue.sync(execute: { self.generation == deliveryGeneration }) else { return }
                            self.onCommand?(command)
                        }
                    }
                } else if let error {
                    self.stopRequest()
                    self.report("Speech recognition interrupted: \(error.localizedDescription)")
                    self.scheduleRestart(after: 5)
                }
            }
        }
        report("Listening for the six recording commands (English, on-device).")
        scheduleRestart(after: 50)
    }

    private func scheduleRestart(after seconds: Double) {
        renewal?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.enabled else { return }
            self.startRequest()
        }
        renewal = work
        queue.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func stopRequest() {
        generation += 1
        renewal?.cancel()
        renewal = nil
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        boundary = VoiceUtteranceBoundary()
        awaitingFinal = false
    }

    private func report(_ message: String) {
        DispatchQueue.main.async { [weak self] in self?.status = message }
    }

    deinit {
        renewal?.cancel()
        request?.endAudio()
        task?.cancel()
    }
}
