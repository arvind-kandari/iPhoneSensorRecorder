import AVFoundation
import Combine
import Foundation

final class RecordingSession: ObservableObject {
    let captureSession: AVCaptureSession

    @Published private(set) var state: RecordingState = .idle
    @Published private(set) var elapsedTime: TimeInterval = 0
    @Published private(set) var formatOptions: [CameraFormatOption] = []
    @Published private(set) var selectedFormat: CameraFormatOption?
    @Published private(set) var isFrontCamera = false
    @Published private(set) var hasTorch = false
    @Published private(set) var torchIsOn = false

    private let timeSynchronizer = TimeSynchronizer()
    private lazy var sensorManager = SensorManager(timeSynchronizer: timeSynchronizer)
    private let cameraRecorder = CameraRecorder()
    private let csvWriter = CSVWriter()
    private let videoWriter = VideoWriter()
    private let metadataWriter = MetadataWriter()
    private var cameraWidth: Int?
    private var cameraHeight: Int?
    private var recordingFiles: RecordingFiles?
    private var timer: Timer?

    var onSensorReading: ((SensorReading) -> Void)?

    init() {
        captureSession = cameraRecorder.captureSession
        sensorManager.onReading = { [weak self] reading in
            guard let self else { return }
            if self.state == .recording { self.csvWriter.write(reading) }
            self.onSensorReading?(reading)
        }
        cameraRecorder.onFrame = { [weak self] sampleBuffer, _ in
            self?.videoWriter.append(sampleBuffer)
        }
        cameraRecorder.onConfigured = { [weak self] width, height in
            self?.publish {
                self?.cameraWidth = width
                self?.cameraHeight = height
                self?.setState(.ready)
            }
        }
        cameraRecorder.onConfigurationFailed = { [weak self] message in
            self?.publish {
                self?.cameraWidth = nil
                self?.cameraHeight = nil
                self?.setState(.error(message))
            }
        }
        cameraRecorder.onFormatsChanged = { [weak self] options, selected in
            DispatchQueue.main.async {
                self?.formatOptions = options
                self?.selectedFormat = selected
            }
        }
        cameraRecorder.onCameraChanged = { [weak self] isFront, hasTorch, torchIsOn in
            DispatchQueue.main.async {
                self?.isFrontCamera = isFront
                self?.hasTorch = hasTorch
                self?.torchIsOn = torchIsOn
            }
        }
    }

    func configure() {
        guard state == .idle else { return }
        setState(.configuring)
        cameraRecorder.configure()
    }

    func selectVideoFormat(_ option: CameraFormatOption) {
        guard state == .ready else { return }
        cameraRecorder.selectFormat(option)
    }

    func switchCamera() {
        guard state == .ready else { return }
        cameraRecorder.switchCamera()
    }

    func toggleTorch() {
        guard state == .ready, hasTorch else { return }
        cameraRecorder.toggleTorch()
    }

    func start() {
        guard state == .ready, let width = cameraWidth, let height = cameraHeight, let selectedFormat else { return }
        do {
            let files = try RecordingFiles()
            recordingFiles = files
            try csvWriter.startRecording(at: files.sensorCSVURL)
            try videoWriter.start(
                at: files.videoURL,
                width: width,
                height: height,
                transform: cameraRecorder.recordingTransform()
            )
            try metadataWriter.write(metadata: RecordingMetadata(
                appVersion: AppInfo.version,
                recordingID: files.folderURL.lastPathComponent,
                sensorFrequencyHz: 100,
                videoFile: "video.mov",
                sensorFile: "sensors.csv",
                createdAt: Date(),
                videoWidth: width,
                videoHeight: height,
                videoResolution: selectedFormat.resolutionLabel,
                videoFPS: selectedFormat.fps
            ), to: files.metadataURL)
            timeSynchronizer.start()
            sensorManager.start()
            cameraRecorder.start()
            startTimer()
            setState(.recording)
        } catch {
            setState(.error("Recording error: \(error.localizedDescription)"))
        }
    }

    func pause() {
        guard state == .recording else { return }
        timeSynchronizer.pause()
        sensorManager.stop()
        videoWriter.pause()
        stopTimer()
        setState(.paused)
    }

    func resume() {
        guard state == .paused else { return }
        timeSynchronizer.resume()
        videoWriter.resume()
        sensorManager.start()
        startTimer()
        setState(.recording)
    }

    func stop(completion: @escaping () -> Void = {}) {
        guard state == .recording || state == .paused else { completion(); return }
        setState(.finishing)
        stopTimer()
        sensorManager.stop()
        cameraRecorder.stop { [weak self] in
            guard let self else { completion(); return }
            self.csvWriter.stopRecording()
            self.videoWriter.finish { [weak self] _ in
                guard let self else { completion(); return }
                self.recordingFiles = nil
                self.publish {
                    self.setElapsedTime(0)
                    self.setState(.ready)
                    completion()
                }
            }
        }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.setElapsedTime(self.timeSynchronizer.timestamp())
        }
    }

    private func stopTimer() {
        setElapsedTime(timeSynchronizer.timestamp())
        timer?.invalidate()
        timer = nil
    }

    private func setState(_ newState: RecordingState) {
        if Thread.isMainThread {
            state = newState
        } else {
            DispatchQueue.main.async { [weak self] in self?.state = newState }
        }
    }

    private func publish(_ action: @escaping () -> Void) {
        if Thread.isMainThread {
            action()
        } else {
            DispatchQueue.main.async(execute: action)
        }
    }

    private func setElapsedTime(_ value: TimeInterval) {
        publish { [weak self] in self?.elapsedTime = value }
    }
}
