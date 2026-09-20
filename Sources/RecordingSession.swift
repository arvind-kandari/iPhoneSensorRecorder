import Foundation
import AVFoundation
import Combine

final class RecordingSession: ObservableObject {

    @Published var isRecording = false
    @Published var isPaused = false
    @Published var elapsedTime: TimeInterval = 0
    @Published var audioEnabled = true

    let cameraRecorder = CameraRecorder()
    let timeSynchronizer = TimeSynchronizer()
    let sensorManager: SensorManager

    let csvWriter = CSVWriter()
    let videoWriter = VideoWriter()
    let metadataWriter = MetadataWriter()

   // MARK: - Compatibility API used by ContentView

    var captureSession: AVCaptureSession {
        cameraRecorder.captureSession
    }

    var hasTorch: Bool {
        true
    }

    var torchIsOn = false

    func toggleTorch() {
        cameraRecorder.toggleTorch()
        torchIsOn.toggle()
    }

    var selectedFormat: CameraFormatOption? {
        cameraRecorder.selectedFormat
    }

    var formatOptions: [CameraFormatOption] {
        cameraRecorder.formatOptions
    }

    var state: RecordingState {
        if isRecording {
            return isPaused ? .paused : .recording
        }

        return .idle
    }

    var onSensorReading: ((SensorReading) -> Void)?

    private var recordingFiles: RecordingFiles?
    private var timer: Timer?

    init() {

        sensorManager = SensorManager(
            timeSynchronizer: timeSynchronizer
        )

        cameraRecorder.onFrame = { [weak self] sampleBuffer, _ in
            self?.videoWriter.append(sampleBuffer)
        }

        cameraRecorder.onAudioFrame = { [weak self] sampleBuffer in
            guard let self else {
                return
            }

            guard self.audioEnabled else {
                return
            }

            self.videoWriter.appendAudio(sampleBuffer)
        }

        sensorManager.onReading = { [weak self] reading in
            guard let self else {
                return
            }

            self.handleSensorReading(reading)
        }
    }

    // MARK: - Camera

    func configure() {
        cameraRecorder.configure()
    }

    func selectVideoFormat(_ option: CameraFormatOption) {
        cameraRecorder.selectFormat(option)
    }

    // MARK: - Audio

    func setAudioEnabled(_ enabled: Bool) {
        guard !isRecording else {
            return
        }

        audioEnabled = enabled
    }

    // MARK: - Recording

    func start() {

        guard !isRecording else {
            return
        }

        do {

            let files = try RecordingFiles()
            recordingFiles = files

            guard let format = cameraRecorder.selectedFormat else {
                print("Recording start failed: Camera format is not ready.")
                return
            }

            try csvWriter.startRecording(
                at: files.sensorCSVURL
            )

            try videoWriter.start(
                url: files.videoURL,
                width: format.width,
                height: format.height,
                fps: format.fps,
                audioEnabled: audioEnabled
            )

            let metadata = RecordingMetadata(
                appVersion: AppInfo.version,
                recordingID: files.folderURL.lastPathComponent,
                sensorFrequencyHz: 100,
                videoFile: files.videoURL.lastPathComponent,
                sensorFile: files.sensorCSVURL.lastPathComponent,
                createdAt: Date(),
                videoWidth: format.width,
                videoHeight: format.height,
                videoResolution: "\(format.width)x\(format.height)",
                videoFPS: format.fps
            )

            try metadataWriter.write(
                metadata: metadata,
                to: files.metadataURL
            )

            timeSynchronizer.start()

            sensorManager.start()

            cameraRecorder.start()

            isRecording = true
            isPaused = false
            elapsedTime = 0

            startTimer()

        } catch {

            print(
                "Recording start failed:",
                error
            )
        }
    }

    func pause() {

        guard isRecording, !isPaused else {
            return
        }

        sensorManager.stop()
        videoWriter.pause()
        timeSynchronizer.pause()

        isPaused = true
    }

    func resume() {

        guard isRecording, isPaused else {
            return
        }

        timeSynchronizer.resume()
        sensorManager.start()
        videoWriter.resume()

        isPaused = false
    }

    func stop() {

        guard isRecording else {
            return
        }

        sensorManager.stop()

        timer?.invalidate()
        timer = nil

        cameraRecorder.stop { [weak self] in

            guard let self else {
                return
            }

            csvWriter.stopRecording()

            videoWriter.finish { [weak self] _ in

                guard let self else {
                    return
                }

                timeSynchronizer.reset()

                DispatchQueue.main.async {

                    self.isRecording = false
                    self.isPaused = false
                    self.elapsedTime = 0
                    self.recordingFiles = nil
                }
            }
        }
    }

    // MARK: - Sensor Callback

    private func handleSensorReading(
        _ reading: SensorReading
    ) {

        guard isRecording else {
            return
        }

        onSensorReading?(reading)

        csvWriter.write(reading)
    }

    // MARK: - Timer

    private func startTimer() {

        timer?.invalidate()

        timer = Timer.scheduledTimer(
            withTimeInterval: 0.1,
            repeats: true
        ) { [weak self] _ in

            guard let self else {
                return
            }

            guard self.isRecording,
                  !self.isPaused
            else {
                return
            }

            self.elapsedTime += 0.1
        }
    }
}