import SwiftUI

struct ContentView: View {

    @State private var recordingState:
        RecordingState = .idle

    @State private var accelerationX = 0.0
    @State private var accelerationY = 0.0
    @State private var accelerationZ = 0.0

    @State private var gyroX = 0.0
    @State private var gyroY = 0.0
    @State private var gyroZ = 0.0

    @State private var magneticX = 0.0
    @State private var magneticY = 0.0
    @State private var magneticZ = 0.0

    private let recordingSession =
        RecordingSession()

    var body: some View {

        ScrollView {

            VStack(
                alignment: .leading,
                spacing: 20
            ) {

                Text(
                    "iPhone Sensor Recorder"
                )
                .font(.largeTitle)
                .fontWeight(.bold)

                statusSection

                sensorSection(
                    title: "Accelerometer",
                    x: accelerationX,
                    y: accelerationY,
                    z: accelerationZ
                )

                sensorSection(
                    title: "Gyroscope",
                    x: gyroX,
                    y: gyroY,
                    z: gyroZ
                )

                sensorSection(
                    title: "Magnetometer",
                    x: magneticX,
                    y: magneticY,
                    z: magneticZ
                )

                recordingButton
            }
            .padding()
        }
        .onAppear {
            setupRecordingSession()
        }
    }

    private var statusSection: some View {

        VStack(
            alignment: .leading,
            spacing: 8
        ) {

            Text(
                "Status"
            )
            .font(.headline)

            HStack {

                Text("Camera")

                Spacer()

                Text(cameraStatus)
                    .fontWeight(.semibold)
            }

            HStack {

                Text("Sensors")

                Spacer()

                Text(sensorStatus)
                    .fontWeight(.semibold)
            }
        }
    }

    private var cameraStatus: String {

        switch recordingState {

        case .idle:
            return "NOT READY"

        case .configuring:
            return "CONFIGURING"

        case .ready:
            return "READY"

        case .recording:
            return "RECORDING"

        case .finishing:
            return "STOPPING"

        case .error:
            return "ERROR"
        }
    }

    private var sensorStatus: String {

        switch recordingState {

        case .idle:
            return "NOT READY"

        case .configuring:
            return "WAITING"

        case .ready:
            return "READY"

        case .recording:
            return "RECORDING"

        case .finishing:
            return "STOPPING"

        case .error:
            return "ERROR"
        }
    }

    private func sensorSection(
        title: String,
        x: Double,
        y: Double,
        z: Double
    ) -> some View {

        VStack(
            alignment: .leading,
            spacing: 6
        ) {

            Text(title)
                .font(.headline)

            HStack {

                sensorValue(
                    label: "X",
                    value: x
                )

                sensorValue(
                    label: "Y",
                    value: y
                )

                sensorValue(
                    label: "Z",
                    value: z
                )
            }
        }
    }

    private func sensorValue(
        label: String,
        value: Double
    ) -> some View {

        VStack {

            Text(label)
                .font(.caption)

            Text(
                String(
                    format: "%.3f",
                    value
                )
            )
            .font(.system(
                .body,
                design: .monospaced
            ))
        }
        .frame(
            maxWidth: .infinity
        )
    }

    private var recordingButton: some View {

        Button {

            toggleRecording()

        } label: {

            Text(buttonTitle)
                .font(.headline)
                .frame(
                    maxWidth: .infinity
                )
                .padding()
        }
        .buttonStyle(.borderedProminent)
        .disabled(
            recordingState == .configuring ||
            recordingState == .finishing
        )
    }

    private var buttonTitle: String {

        switch recordingState {

        case .recording:
            return "STOP RECORDING"

        case .finishing:
            return "SAVING..."

        default:
            return "START RECORDING"
        }
    }

    private func setupRecordingSession() {

        recordingSession.onStateChanged = {
            newState in

            DispatchQueue.main.async {

                recordingState = newState
            }
        }

        recordingSession.onSensorReading = {
            reading in

            DispatchQueue.main.async {

                accelerationX =
                    reading.accelerationX

                accelerationY =
                    reading.accelerationY

                accelerationZ =
                    reading.accelerationZ

                gyroX =
                    reading.rotationRateX

                gyroY =
                    reading.rotationRateY

                gyroZ =
                    reading.rotationRateZ

                magneticX =
                    reading.magneticFieldX

                magneticY =
                    reading.magneticFieldY

                magneticZ =
                    reading.magneticFieldZ
            }
        }

        recordingSession.configure()
    }

    private func toggleRecording() {

        if recordingState == .recording {

            recordingSession.stop {

                print(
                    "Recording finished"
                )
            }

        } else if recordingState == .ready {

            recordingSession.start()
        }
    }
}