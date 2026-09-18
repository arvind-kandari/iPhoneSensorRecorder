import SwiftUI

struct ContentView: View {
    @StateObject private var recordingSession = RecordingSession()
    @State private var sensorReading = SensorReading(recordingTime: 0, sensorTimestamp: 0, accelerationX: 0, accelerationY: 0, accelerationZ: 0, rotationRateX: 0, rotationRateY: 0, rotationRateZ: 0, magneticFieldX: 0, magneticFieldY: 0, magneticFieldZ: 0, roll: 0, pitch: 0, yaw: 0)
    @State private var showSettings = false
    @State private var showSensorOverlay = false

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
        GeometryReader { proxy in
            ZStack {
                Color.black
                CameraPreview(session: recordingSession.captureSession)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                LinearGradient(colors: [.black.opacity(0.65), .clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom)

                VStack(spacing: 0) {
                    topControls
                    Spacer()
                    if showSensorOverlay { sensorOverlay }
                    Spacer()
                    if recordingSession.state == .recording || recordingSession.state == .paused {
                        recordingBadge
                    }
                    cameraControls
                        .padding(.top, 18)
                        .padding(.bottom, 24)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }
            .ignoresSafeArea(edges: .top)
        }
    }

    private var topControls: some View {
        HStack(spacing: 14) {
            if recordingSession.hasTorch {
                Button(action: recordingSession.toggleTorch) {
                    Image(systemName: recordingSession.torchIsOn ? "bolt.fill" : "bolt.slash.fill")
                }
                .disabled(recordingSession.state != .ready)
            }
            Spacer()
            Button { showSettings = true } label: {
                Text(formatText)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.55), in: Capsule())
            }
            .disabled(recordingSession.state == .recording || recordingSession.state == .paused)
            Button { showSensorOverlay.toggle() } label: {
                Image(systemName: showSensorOverlay ? "waveform.path.ecg" : "waveform.path.ecg.rectangle")
            }
            Button(action: recordingSession.switchCamera) {
                Image(systemName: "camera.rotate")
            }
            .disabled(recordingSession.state != .ready)
            Button { showSettings = true } label: { Image(systemName: "gearshape") }
                .disabled(recordingSession.state == .recording || recordingSession.state == .paused)
        }
        .font(.title3)
        .foregroundStyle(.white)
        .padding(.top, 8)
    }

    private var recordingBadge: some View {
        HStack(spacing: 7) {
            Circle().fill(recordingSession.state == .recording ? .red : .yellow).frame(width: 9, height: 9)
            Text(timerText)
        }
        .font(.system(.subheadline, design: .monospaced).weight(.bold))
        .foregroundStyle(.white)
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .background(.black.opacity(0.6), in: Capsule())
    }

    private var sensorOverlay: some View {
        VStack(alignment: .leading, spacing: 4) {
            sensorLine("ACC", sensorReading.accelerationX, sensorReading.accelerationY, sensorReading.accelerationZ)
            sensorLine("GYR", sensorReading.rotationRateX, sensorReading.rotationRateY, sensorReading.rotationRateZ)
            sensorLine("MAG", sensorReading.magneticFieldX, sensorReading.magneticFieldY, sensorReading.magneticFieldZ)
            sensorLine("ATT", sensorReading.roll, sensorReading.pitch, sensorReading.yaw)
        }
        .font(.system(.caption2, design: .monospaced))
        .foregroundStyle(.white)
        .padding(10)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var cameraControls: some View {
        switch recordingSession.state {
        case .recording:
            HStack(spacing: 56) {
                cameraControl(symbol: "pause.fill", title: "Pause", action: recordingSession.pause)
                cameraControl(symbol: "stop.fill", title: "Stop", tint: .red) { recordingSession.stop() }
            }
        case .paused:
            HStack(spacing: 56) {
                cameraControl(symbol: "play.fill", title: "Resume", action: recordingSession.resume)
                cameraControl(symbol: "stop.fill", title: "Stop", tint: .red) { recordingSession.stop() }
            }
        default:
            Button(action: recordingSession.start) {
                Circle()
                    .stroke(.white, lineWidth: 5)
                    .frame(width: 76, height: 76)
                    .overlay(Circle().fill(.red).padding(7))
            }
            .buttonStyle(.plain)
            .disabled(recordingSession.state != .ready)
            .opacity(recordingSession.state == .ready ? 1 : 0.55)
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

    private func cameraControl(symbol: String, title: String, tint: Color = .white, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.title3.weight(.bold))
                    .frame(width: 54, height: 54)
                    .background(.black.opacity(0.55), in: Circle())
                Text(title).font(.caption.weight(.semibold))
            }
            .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
    }

    private func sensorLine(_ label: String, _ x: Double, _ y: Double, _ z: Double) -> some View {
        Text("\(label)  X \(x, format: .number.precision(.fractionLength(3)))  Y \(y, format: .number.precision(.fractionLength(3)))  Z \(z, format: .number.precision(.fractionLength(3)))")
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
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
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
