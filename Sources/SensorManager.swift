import Foundation
import CoreMotion

struct SensorReading {

    let recordingTime: TimeInterval
    let sensorTimestamp: TimeInterval

    let accelerationX: Double
    let accelerationY: Double
    let accelerationZ: Double

    let rotationRateX: Double
    let rotationRateY: Double
    let rotationRateZ: Double

    let magneticFieldX: Double
    let magneticFieldY: Double
    let magneticFieldZ: Double

    let roll: Double
    let pitch: Double
    let yaw: Double
}

final class SensorManager {

    private let motionManager = CMMotionManager()
    private let operationQueue = OperationQueue()

    private let timeSynchronizer: TimeSynchronizer

    var onReading: ((SensorReading) -> Void)?

    init(
        timeSynchronizer: TimeSynchronizer
    ) {

        self.timeSynchronizer = timeSynchronizer

        operationQueue.name =
            "SensorManagerQueue"

        operationQueue.qualityOfService =
            .userInitiated
    }

    func start() {

        guard motionManager.isDeviceMotionAvailable else {

            print(
                "Device Motion is not available"
            )

            return
        }

        motionManager.deviceMotionUpdateInterval =
            1.0 / 100.0

        motionManager.startDeviceMotionUpdates(
            using: .xArbitraryCorrectedZVertical,
            to: operationQueue
        ) { [weak self] motion, error in

            guard let self = self,
                  let motion = motion,
                  error == nil else {
                return
            }

            let reading =
                SensorReading(

                    recordingTime:
                        self.timeSynchronizer.timestamp(),

                    sensorTimestamp:
                        motion.timestamp,

                    accelerationX:
                        motion.userAcceleration.x,

                    accelerationY:
                        motion.userAcceleration.y,

                    accelerationZ:
                        motion.userAcceleration.z,

                    rotationRateX:
                        motion.rotationRate.x,

                    rotationRateY:
                        motion.rotationRate.y,

                    rotationRateZ:
                        motion.rotationRate.z,

                    magneticFieldX:
                        motion.magneticField.field.x,

                    magneticFieldY:
                        motion.magneticField.field.y,

                    magneticFieldZ:
                        motion.magneticField.field.z,

                    roll:
                        motion.attitude.roll,

                    pitch:
                        motion.attitude.pitch,

                    yaw:
                        motion.attitude.yaw
                )

            self.onReading?(reading)
        }
    }

    func stop() {

        motionManager.stopDeviceMotionUpdates()
    }
}