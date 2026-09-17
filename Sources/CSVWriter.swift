import Foundation

final class CSVWriter {

    private var fileHandle: FileHandle?

    private(set) var fileURL: URL?

    func startRecording(
        at url: URL
    ) throws {

        let fileManager =
            FileManager.default

        if fileManager.fileExists(
            atPath: url.path
        ) {

            try fileManager.removeItem(
                at: url
            )
        }

        let header = """
        recording_time,sensor_timestamp,acceleration_x,acceleration_y,acceleration_z,rotation_x,rotation_y,rotation_z,magnetic_x,magnetic_y,magnetic_z,roll,pitch,yaw
        """

        try header.write(
            to: url,
            atomically: true,
            encoding: .utf8
        )

        fileHandle =
            try FileHandle(
                forWritingTo: url
            )

        fileHandle?.seekToEndOfFile()

        fileURL = url
    }

    func write(
        _ reading: SensorReading
    ) {

        guard let fileHandle =
                fileHandle else {
            return
        }

        let line = String(
            format:
                "%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f\n",

            reading.recordingTime,

            reading.sensorTimestamp,

            reading.accelerationX,
            reading.accelerationY,
            reading.accelerationZ,

            reading.rotationRateX,
            reading.rotationRateY,
            reading.rotationRateZ,

            reading.magneticFieldX,
            reading.magneticFieldY,
            reading.magneticFieldZ,

            reading.roll,
            reading.pitch,
            reading.yaw
        )

        guard let data =
                line.data(using: .utf8) else {
            return
        }

        fileHandle.write(data)
    }

    func stopRecording() {

        try? fileHandle?.synchronize()

        try? fileHandle?.close()

        fileHandle = nil
    }
}