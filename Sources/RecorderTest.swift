import Foundation

final class RecorderTest {

    private let session = RecordingSession()

    func configure() {

        session.onSensorReading = { reading in

            print("""
            Sensor:
              Recording Time: \(reading.recordingTime)
              Sensor Timestamp: \(reading.sensorTimestamp)

              Acceleration:
                X: \(reading.accelerationX)
                Y: \(reading.accelerationY)
                Z: \(reading.accelerationZ)

              Gyroscope:
                X: \(reading.rotationRateX)
                Y: \(reading.rotationRateY)
                Z: \(reading.rotationRateZ)

              Magnetometer:
                X: \(reading.magneticFieldX)
                Y: \(reading.magneticFieldY)
                Z: \(reading.magneticFieldZ)

              Attitude:
                Roll: \(reading.roll)
                Pitch: \(reading.pitch)
                Yaw: \(reading.yaw)
            """)
        }

        session.configure()
    }

    func start() {
        session.start()
    }

    func stop() {
        session.stop {
            print("Recording test finished")
        }
    }
}