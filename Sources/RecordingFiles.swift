import Foundation

final class RecordingFiles {

    let folderURL: URL
    let videoURL: URL
    let sensorCSVURL: URL
    let metadataURL: URL

    init() throws {

        let fileManager = FileManager.default

        let documentsDirectory = fileManager.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0]

        let recordingsDirectory = documentsDirectory
            .appendingPathComponent("Recordings")

        try fileManager.createDirectory(
            at: recordingsDirectory,
            withIntermediateDirectories: true
        )

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"

        let recordingName =
            "Recording_\(formatter.string(from: Date()))"

        folderURL = recordingsDirectory
            .appendingPathComponent(recordingName)

        try fileManager.createDirectory(
            at: folderURL,
            withIntermediateDirectories: true
        )

        videoURL = folderURL
            .appendingPathComponent("video.mov")

        sensorCSVURL = folderURL
            .appendingPathComponent("sensors.csv")

        metadataURL = folderURL
            .appendingPathComponent("metadata.json")
    }
}