import Foundation

struct RecordingMetadata: Codable {

    let appVersion: String

    let recordingID: String

    let sensorFrequencyHz: Double

    let videoFile: String

    let sensorFile: String

    let createdAt: Date
}

final class MetadataWriter {

    func write(
        metadata: RecordingMetadata,
        to url: URL
    ) throws {

        let encoder = JSONEncoder()

        encoder.outputFormatting = [
            .prettyPrinted,
            .sortedKeys
        ]

        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(metadata)

        try data.write(
            to: url,
            options: .atomic
        )
    }
}