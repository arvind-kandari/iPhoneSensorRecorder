import Foundation
import AVFoundation
import Combine

final class RecordingSession: ObservableObject {

    @Published var isRecording = false
    @Published var isPaused = false
    @Published var elapsedTime: TimeInterval = 0

    @Published var audioEnabled = true

    let cameraRecorder = CameraRecorder()
    let sensorManager = SensorManager()
    let csvWriter = CSVWriter()
    let videoWriter = VideoWriter()
    let metadataWriter = MetadataWriter()

    let timeSynchronizer = TimeSynchronizer()

    private var recordingFiles: RecordingFiles?
    private var timer: Timer?

    init() {

        cameraRecorder.onFrame = { [weak self] sampleBuffer in
            self?.videoWriter.append(sampleBuffer)
        }

        cameraRecorder.onAudioFrame = { [weak self] sampleBuffer in
            self?.videoWriter.appendAudio(sampleBuffer)
        }
    }

    func configure() {

        cameraRecorder.configure()
    }

    func setAudioEnabled(_ enabled: Bool) {

        guard !isRecording else {
            return
        }

        audioEnabled = enabled
    }

    func start() {

        guard !isRecording else {
            return
        }

        do {

            let files = try RecordingFiles()
            recordingFiles = files

            try csvWriter.start(url: files.sensorURL)

            let format = cameraRecorder.currentVideoFormat

            try videoWriter.start(
                url: files.videoURL,
                width: format.width,
                height: format.height,
                fps: format.fps,
                audioEnabled: audioEnabled
            )

            let metadata = RecordingMetadata(
                appVersion: AppInfo.version,
                recordingID: files.folder.lastPathComponent,
                sensorFrequencyHz: 100,
                videoFile: files.videoURL.lastPathComponent,
                sensorFile: files.sensorURL.lastPathComponent,
                createdAt: Date(),
                videoWidth: format.width,
                videoHeight: format.height,
                videoResolution: "\(format.width)x\(format.height)",
                videoFPS: format.fps
            )

            try metadataWriter.write(
                metadata,
                to: files.metadataURL
            )

            timeSynchronizer.start()

            sensorManager.start { [weak self] sample in

                guard let self else {
                    return
                }

                let timestamp = self.timeSynchronizer.elapsedTime(
                    for: sample.timestamp
                )

                self.csvWriter.append(
                    sample: sample,
                    timestamp: timestamp
                )
            }

            cameraRecorder.start()

            isRecording = true
            isPaused = false
            elapsedTime = 0

            startTimer()

        } catch {

            print("Recording start failed:", error)
        }
    }

    func pause() {

        guard isRecording, !isPaused else {
            return
        }

        sensorManager.pause()
        videoWriter.pause()
        timeSynchronizer.pause()

        isPaused = true
    }

    func resume() {

        guard isRecording, isPaused else {
            return
        }

        timeSynchronizer.resume()
        sensorManager.resume()
        videoWriter.resume()

        isPaused = false
    }

    func stop() {

        guard isRecording else {
            return
        }

        sensorManager.stop()
        cameraRecorder.stop()

        timer?.invalidate()
        timer = nil

        csvWriter.finish()

        videoWriter.finish { [weak self] _ in

            guard let self else {
                return
            }

            DispatchQueue.main.async {

                self.isRecording = false
                self.isPaused = false
                self.elapsedTime = 0
            }
        }

        recordingFiles = nil
    }

    private func startTimer() {

        timer?.invalidate()

        timer = Timer.scheduledTimer(
            withTimeInterval: 0.1,
            repeats: true
        ) { [weak self] _ in

            guard let self else {
                return
            }

            guard self.isRecording, !self.isPaused else {
                return
            }

            self.elapsedTime += 0.1
        }
    }
}