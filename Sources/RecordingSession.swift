```swift
import Foundation
import AVFoundation

final class RecordingSession {

    private let timeSynchronizer =
        TimeSynchronizer()

    private lazy var sensorManager =
        SensorManager(
            timeSynchronizer: timeSynchronizer
        )

    private let cameraRecorder =
        CameraRecorder()

    private let csvWriter =
        CSVWriter()

    private let videoWriter =
        VideoWriter()

    private let metadataWriter =
        MetadataWriter()

    private(set) var state:
        RecordingState = .idle

    private var cameraIsConfigured = false
    private var cameraWidth: Int?
    private var cameraHeight: Int?

    private var recordingFiles:
        RecordingFiles?

    var onStateChanged:
        ((RecordingState) -> Void)?

    var onSensorReading:
        ((SensorReading) -> Void)?

    init() {

        sensorManager.onReading = {
            [weak self] reading in

            guard let self = self else {
                return
            }

            self.csvWriter.write(reading)

            self.onSensorReading?(reading)
        }

        cameraRecorder.onFrame = {
            [weak self] sampleBuffer, cameraTimestamp in

            guard let self = self else {
                return
            }

            self.videoWriter.append(
                sampleBuffer
            )

            print(
                "Camera timestamp: \(cameraTimestamp)"
            )
        }

        cameraRecorder.onConfigured = {
            [weak self] width, height in

            guard let self = self else {
                return
            }

            self.cameraWidth = width
            self.cameraHeight = height

            self.cameraIsConfigured = true

            print(
                "Camera ready: \(width)x\(height)"
            )

            self.setState(.ready)
        }
    }

    func configure() {

        guard state == .idle else {
            return
        }

        setState(.configuring)

        cameraRecorder.configure()
    }

    func start() {

        guard state == .ready else {

            print(
                "Cannot start. Current state: \(state)"
            )

            return
        }

        guard cameraIsConfigured else {

            print(
                "Camera is not ready"
            )

            return
        }

        guard let width = cameraWidth,
              let height = cameraHeight else {

            print(
                "Camera dimensions are unavailable"
            )

            return
        }

        do {

            let files =
                try RecordingFiles()

            recordingFiles = files

            try csvWriter.startRecording(
                at: files.sensorCSVURL
            )

            try videoWriter.start(
                at: files.videoURL,
                width: width,
                height: height
            )

            let metadata =
                RecordingMetadata(
                    appVersion:
                        AppInfo.version,

                    recordingID:
                        files.folderURL.lastPathComponent,

                    sensorFrequencyHz:
                        100.0,

                    videoFile:
                        "video.mov",

                    sensorFile:
                        "sensors.csv",

                    createdAt:
                        Date()
                )

            try metadataWriter.write(
                metadata: metadata,
                to: files.metadataURL
            )

            timeSynchronizer.start()

            sensorManager.start()

            cameraRecorder.start()

            setState(.recording)

            print(
                "Recording started"
            )

            print(
                "Recording folder:"
            )

            print(
                files.folderURL.path
            )

        } catch {

            setState(
                .error(
                    "Recording error: " +
                    error.localizedDescription
                )
            )
        }
    }

    func stop(
        completion: @escaping () -> Void
    ) {

        guard state == .recording else {

            completion()

            return
        }

        setState(.finishing)

        sensorManager.stop()

        cameraRecorder.stop()

        csvWriter.stopRecording()

        videoWriter.finish {
            [weak self] url in

            guard let self = self else {

                completion()

                return
            }

            if let url = url {

                print(
                    "Video saved:"
                )

                print(
                    url.path
                )
            }

            if let files =
                self.recordingFiles {

                print(
                    "Recording folder:"
                )

                print(
                    files.folderURL.path
                )
            }

            self.recordingFiles = nil

            self.setState(.ready)

            completion()
        }
    }

    private func setState(
        _ newState: RecordingState
    ) {

        state = newState

        onStateChanged?(
            newState
        )

        print(
            "State: \(newState)"
        )
    }
}
```
