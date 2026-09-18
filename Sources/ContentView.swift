import SwiftUI

struct ContentView: View {
    @StateObject private var recordingSession = RecordingSession()
    @State private var sensorReading = SensorReading(recordingTime: 0, sensorTimestamp: 0, accelerationX: 0, accelerationY: 0, accelerationZ: 0, rotationRateX: 0, rotationRateY: 0, rotationRateZ: 0, magneticFieldX: 0, magneticFieldY: 0, magneticFieldZ: 0, roll: 0, pitch: 0, yaw: 0)
    @State private var showSettings = false

    var body: some View {
        TabView {
            recordView
                .tabItem { Label("Record", systemImage: "record.circle") }
            RecordingsView()
                .tabItem { Label("Recordings", systemImage: "folder") }
            AboutView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .tint(.red)
        .preferredColorScheme(.dark)
        .onAppear {
            recordingSession.onSensorReading = { reading in
                DispatchQueue.main.async { sensorReading = reading }
            }
            recordingSession.configure()
        }
        .sheet(isPresented: $showSettings) {
            VideoSettingsView(session: recordingSession)
        }
    }

    private var recordView: some View {
        VStack(spacing: 16) {
            HStack {
                Text(AppInfo.name).font(.title2.bold())
                Spacer()
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
                    .disabled(recordingSession.state == .recording || recordingSession.state == .paused)
            }
            .padding(.horizontal)

            ZStack(alignment: .topLeading) {
                CameraPreview(session: recordingSession.captureSession)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                Text(statusText).font(.caption.bold()).padding(8).background(.black.opacity(0.65)).clipShape(Capsule()).padding()
            }
            .aspectRatio(9 / 16, contentMode: .fit)
            .padding(.horizontal)

            Button { showSettings = true } label: {
                Text(formatText + "  ›").font(.subheadline.weight(.semibold))
            }
            .disabled(recordingSession.state == .recording || recordingSession.state == .paused)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Sensors").font(.headline)
                    sensorSection("Accelerometer", sensorReading.accelerationX, sensorReading.accelerationY, sensorReading.accelerationZ, "X", "Y", "Z")
                    sensorSection("Gyroscope", sensorReading.rotationRateX, sensorReading.rotationRateY, sensorReading.rotationRateZ, "X", "Y", "Z")
                    sensorSection("Magnetometer", sensorReading.magneticFieldX, sensorReading.magneticFieldY, sensorReading.magneticFieldZ, "X", "Y", "Z")
                    sensorSection("Orientation", sensorReading.roll, sensorReading.pitch, sensorReading.yaw, "Roll", "Pitch", "Yaw")
                }
                .padding(.horizontal)
            }
            controls
                .padding(.horizontal)
                .padding(.bottom, 8)
        }
    }

    private var controls: some View {
        VStack(spacing: 8) {
            Text(timerText).font(.system(.headline, design: .monospaced)).foregroundStyle(recordingSession.state == .recording ? .red : .primary)
            switch recordingSession.state {
            case .recording:
                HStack { Button("Pause", action: recordingSession.pause); Button("Stop", action: { recordingSession.stop() }) }.buttonStyle(.borderedProminent)
            case .paused:
                HStack { Button("Resume", action: recordingSession.resume); Button("Stop", action: { recordingSession.stop() }) }.buttonStyle(.borderedProminent)
            default:
                Button("Start Recording", action: recordingSession.start).buttonStyle(.borderedProminent).disabled(recordingSession.state != .ready)
            }
        }
    }

    private var statusText: String {
        switch recordingSession.state {
        case .recording: return "REC"
        case .paused: return "PAUSED"
        case .ready: return "CAMERA READY"
        case .configuring: return "CONFIGURING"
        case .finishing: return "SAVING"
        case .idle: return "CAMERA"
        case .error(let message): return message
        }
    }

    private var formatText: String {
        guard let format = recordingSession.selectedFormat else { return "Video Settings" }
        return "\(format.resolutionLabel) • \(Int(format.fps)) FPS"
    }

    private var timerText: String {
        let seconds = Int(recordingSession.elapsedTime)
        return String(format: "%@ %02d:%02d:%02d", recordingSession.state == .paused ? "PAUSED" : "REC", seconds / 3600, seconds / 60 % 60, seconds % 60)
    }

    private func sensorSection(_ title: String, _ x: Double, _ y: Double, _ z: Double, _ xLabel: String, _ yLabel: String, _ zLabel: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.semibold))
            HStack { sensorValue(xLabel, x); sensorValue(yLabel, y); sensorValue(zLabel, z) }
        }
    }

    private func sensorValue(_ label: String, _ value: Double) -> some View {
        VStack { Text(label).font(.caption); Text(value, format: .number.precision(.fractionLength(3))).font(.system(.body, design: .monospaced)) }.frame(maxWidth: .infinity)
    }
}

private struct VideoSettingsView: View {
    @ObservedObject var session: RecordingSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(session.formatOptions) { option in
                Button { session.selectVideoFormat(option); dismiss() } label: {
                    HStack { Text(option.resolutionLabel); Spacer(); Text("\(Int(option.fps)) FPS").foregroundStyle(.secondary); if option == session.selectedFormat { Image(systemName: "checkmark") } }
                }
            }
            .navigationTitle("Video Settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
    }
}

private struct AboutView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text(AppInfo.name).font(.title.bold())
            Text("Version \(AppInfo.version)")
            Text("Video + Accelerometer + Gyroscope + Magnetometer + Orientation").multilineTextAlignment(.center).foregroundStyle(.secondary)
            Spacer()
            Text("Made with ❤️ by\nArvind Kandari").multilineTextAlignment(.center).font(.footnote)
        }
        .padding()
    }
}

private struct RecordingsView: View {
    @State private var recordings: [URL] = []
    var body: some View {
        NavigationStack {
            List(recordings, id: \.self) { Text($0.lastPathComponent) }
                .navigationTitle("Recordings")
                .onAppear { recordings = Self.load() }
        }
    }
    private static func load() -> [URL] {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return (try? FileManager.default.contentsOfDirectory(at: documents.appendingPathComponent("Recordings"), includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles))?.sorted { $0.lastPathComponent > $1.lastPathComponent } ?? []
    }
}
