import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var recordingSession = RecordingSession()
    @StateObject private var licenseManager = LicenseManager()

    @State private var sensorReading = SensorReading(
        recordingTime: 0,
        sensorTimestamp: 0,
        accelerationX: 0,
        accelerationY: 0,
        accelerationZ: 0,
        rotationRateX: 0,
        rotationRateY: 0,
        rotationRateZ: 0,
        magneticFieldX: 0,
        magneticFieldY: 0,
        magneticFieldZ: 0,
        roll: 0,
        pitch: 0,
        yaw: 0
    )

    @State private var showSettings = false
    @State private var showSensorOverlay = false

    var body: some View {
        Group {
            if licenseManager.isActivated {
                activatedContent
            } else {
                ActivationView(licenseManager: licenseManager)
            }
        }
    }

    private var activatedContent: some View {
        TabView {
            recordView
                .tabItem {
                    Label("Record", systemImage: "record.circle")
                }

            RecordingsView()
                .tabItem {
                    Label("Recordings", systemImage: "folder")
                }

            AboutView(licenseManager: licenseManager)
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .tint(.red)
        .preferredColorScheme(.dark)
        .onAppear {
            recordingSession.onSensorReading = { reading in
                DispatchQueue.main.async {
                    sensorReading = reading
                }
            }

            recordingSession.configure()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIApplication.willEnterForegroundNotification
            )
        ) { _ in
            licenseManager.refreshValidity()
        }
        .sheet(isPresented: $showSettings) {
            VideoSettingsView(session: recordingSession)
        }
    }



    // MARK: - Record View

    private var recordView: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black
                    .ignoresSafeArea()

                CameraPreview(
                    session: recordingSession.captureSession
                )
                .frame(
                    width: proxy.size.width,
                    height: proxy.size.height
                )
                .clipped()
                .ignoresSafeArea()

                LinearGradient(
                    colors: [
                        .black.opacity(0.55),
                        .clear,
                        .black.opacity(0.75)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(
                    width: proxy.size.width,
                    height: proxy.size.height
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)

                VStack(spacing: 0) {
                    topControls

                    Spacer()

                    if showSensorOverlay {
                        sensorOverlay
                    }

                    Spacer()

                    if recordingSession.state == .recording ||
                        recordingSession.state == .paused {
                        recordingBadge
                    }

                    cameraControls
                        .padding(.top, 18)
                        .padding(.bottom, 24)
                }
                .frame(
                    width: proxy.size.width,
                    height: proxy.size.height
                )
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }
            .frame(
                width: proxy.size.width,
                height: proxy.size.height
            )
            .ignoresSafeArea()
        }
    }
    // MARK: - Top Controls

    private var topControls: some View {
        HStack(spacing: 14) {
            if recordingSession.hasTorch {
                Button(action: recordingSession.toggleTorch) {
                    Image(
                        systemName: recordingSession.torchIsOn
                            ? "bolt.fill"
                            : "bolt.slash.fill"
                    )
                }
                .disabled(recordingSession.state != .ready)
            }

            Spacer()

            Button {
                showSettings = true
            } label: {
                Text(formatText)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        .black.opacity(0.55),
                        in: Capsule()
                    )
            }
            .disabled(
                recordingSession.state == .recording ||
                recordingSession.state == .paused
            )

            Button {
                showSensorOverlay.toggle()
            } label: {
                Image(
                    systemName: showSensorOverlay
                        ? "waveform.path.ecg"
                        : "waveform.path.ecg.rectangle"
                )
            }

            Button(action: recordingSession.switchCamera) {
                Image(systemName: "camera.rotate")
            }
            .disabled(recordingSession.state != .ready)

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .disabled(
                recordingSession.state == .recording ||
                recordingSession.state == .paused
            )
        }
        .font(.title3)
        .foregroundStyle(.white)
        .padding(.top, 8)
    }

    // MARK: - Recording Badge

    private var recordingBadge: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(
                    recordingSession.state == .recording
                        ? .red
                        : .yellow
                )
                .frame(width: 9, height: 9)

            Text(timerText)
        }
        .font(
            .system(
                .subheadline,
                design: .monospaced
            )
            .weight(.bold)
        )
        .foregroundStyle(.white)
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .background(
            .black.opacity(0.6),
            in: Capsule()
        )
    }

    // MARK: - Sensor Overlay

    private var sensorOverlay: some View {
        VStack(alignment: .leading, spacing: 4) {
            sensorLine(
                "ACC",
                sensorReading.accelerationX,
                sensorReading.accelerationY,
                sensorReading.accelerationZ
            )

            sensorLine(
                "GYR",
                sensorReading.rotationRateX,
                sensorReading.rotationRateY,
                sensorReading.rotationRateZ
            )

            sensorLine(
                "MAG",
                sensorReading.magneticFieldX,
                sensorReading.magneticFieldY,
                sensorReading.magneticFieldZ
            )

            sensorLine(
                "ATT",
                sensorReading.roll,
                sensorReading.pitch,
                sensorReading.yaw
            )
        }
        .font(
            .system(
                .caption2,
                design: .monospaced
            )
        )
        .foregroundStyle(.white)
        .padding(10)
        .background(
            .black.opacity(0.55),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
    }

    // MARK: - Camera Controls

    @ViewBuilder
    private var cameraControls: some View {
        switch recordingSession.state {

        case .recording:
            HStack(spacing: 56) {
                cameraControl(
                    symbol: "pause.fill",
                    title: "Pause",
                    action: recordingSession.pause
                )

                cameraControl(
                    symbol: "stop.fill",
                    title: "Stop",
                    tint: .red
                ) {
                    recordingSession.stop()
                }
            }

        case .paused:
            HStack(spacing: 56) {
                cameraControl(
                    symbol: "play.fill",
                    title: "Resume",
                    action: recordingSession.resume
                )

                cameraControl(
                    symbol: "stop.fill",
                    title: "Stop",
                    tint: .red
                ) {
                    recordingSession.stop()
                }
            }

        default:
            Button(action: recordingSession.start) {
                Circle()
                    .stroke(.white, lineWidth: 5)
                    .frame(
                        width: 76,
                        height: 76
                    )
                    .overlay(
                        Circle()
                            .fill(.red)
                            .padding(7)
                    )
            }
            .buttonStyle(.plain)
            .disabled(recordingSession.state != .ready)
            .opacity(
                recordingSession.state == .ready
                    ? 1
                    : 0.55
            )
        }
    }

    // MARK: - Format

    private var formatText: String {
        guard let format = recordingSession.selectedFormat else {
            return "Video Settings"
        }

        return "\(format.resolutionLabel) • \(Int(format.fps)) FPS"
    }

    // MARK: - Timer

    private var timerText: String {
        let seconds = Int(recordingSession.elapsedTime)

        return String(
            format: "%@ %02d:%02d:%02d",
            recordingSession.state == .paused
                ? "PAUSED"
                : "REC",
            seconds / 3600,
            seconds / 60 % 60,
            seconds % 60
        )
    }

    // MARK: - Camera Button

    private func cameraControl(
        symbol: String,
        title: String,
        tint: Color = .white,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.title3.weight(.bold))
                    .frame(
                        width: 54,
                        height: 54
                    )
                    .background(
                        .black.opacity(0.55),
                        in: Circle()
                    )

                Text(title)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Sensor Line

    private func sensorLine(
        _ label: String,
        _ x: Double,
        _ y: Double,
        _ z: Double
    ) -> some View {
        let xText = String(format: "%.3f", x)
        let yText = String(format: "%.3f", y)
        let zText = String(format: "%.3f", z)

        return Text(
            "\(label)  X \(xText)  Y \(yText)  Z \(zText)"
        )
    }
}

// MARK: - Video Settings

private struct VideoSettingsView: View {
    @ObservedObject var session: RecordingSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(session.formatOptions) { option in
                Button {
                    session.selectVideoFormat(option)
                    dismiss()
                } label: {
                    HStack {
                        Text(option.resolutionLabel)

                        Spacer()

                        Text("\(Int(option.fps)) FPS")
                            .foregroundStyle(.secondary)

                        if option == session.selectedFormat {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            .navigationTitle("Video Settings")
            .toolbar {
                ToolbarItem(
                    placement: .confirmationAction
                ) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - About

private struct AboutView: View {
    @ObservedObject var licenseManager: LicenseManager

    var body: some View {
        NavigationStack {
            List {
                // MARK: App Information

                Section {
                    VStack(spacing: 12) {
                        Image(
                            systemName:
                                "camera.metering.center.weighted"
                        )
                        .font(.system(size: 52))
                        .foregroundStyle(.red)

                        Text(AppInfo.name)
                            .font(.title2.bold())

                        Text(
                            "Camera + Motion Sensor Recorder"
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                        Text(
                            "Version \(AppInfo.version)"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }

                // MARK: License

                Section("License") {
                    HStack {
                        Text("Status")

                        Spacer()

                        Label(
                            "Active",
                            systemImage:
                                "checkmark.seal.fill"
                        )
                        .foregroundStyle(.green)
                        .fontWeight(.semibold)
                    }

                    licenseRow(
                        title: "Full Name",
                        value: licenseManager.fullName
                    )

                    licenseRow(
                        title: "Username",
                        value: licenseManager.username
                    )

                    licenseRow(
                        title: "Device ID",
                        value: licenseManager.deviceID
                    )

                    licenseRow(
                        title: "Expires",
                        value: formattedExpiration(
                            licenseManager.expiresAt
                        )
                    )

                    licenseRow(
                        title: "License ID",
                        value: licenseManager.licenseID
                    )

                    Label(
                        "Offline activation",
                        systemImage: "wifi.slash"
                    )
                    .foregroundStyle(.secondary)
                }

                // MARK: Features

                Section("Features") {
                    Label(
                        "Camera video recording",
                        systemImage: "video.fill"
                    )

                    Label(
                        "Accelerometer X / Y / Z",
                        systemImage: "waveform.path.ecg"
                    )

                    Label(
                        "Gyroscope X / Y / Z",
                        systemImage: "gyroscope"
                    )

                    Label(
                        "Magnetometer",
                        systemImage: "location.north.fill"
                    )

                    Label(
                        "Roll / Pitch / Yaw",
                        systemImage: "move.3d"
                    )

                    Label(
                        "Synchronized timestamps",
                        systemImage: "clock.fill"
                    )

                    Label(
                        "CSV + metadata export",
                        systemImage: "doc.text.fill"
                    )
                }

                // MARK: Footer

                Section {
                    VStack(spacing: 6) {
                        Text("Made with ❤️ by")
                            .font(.footnote)

                        Text("Cyber Data")
                            .font(.footnote)

                        Text("SensorSync Recorder")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("About")
        }
    }

    private func licenseRow(
        title: String,
        value: String
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 4
        ) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(
                value.isEmpty
                    ? "—"
                    : value
            )
            .font(.body)
            .textSelection(.enabled)
        }
    }

    private func formattedExpiration(
        _ value: String
    ) -> String {
        guard !value.isEmpty else {
            return "—"
        }

        let formatter = ISO8601DateFormatter()

        guard let date = formatter.date(
            from: value
        ) else {
            return value
        }

        let displayFormatter = DateFormatter()
        displayFormatter.dateStyle = .medium
        displayFormatter.timeStyle = .medium

        return displayFormatter.string(
            from: date
        )
    }
}

// MARK: - Recordings

private struct RecordingsView: View {
    @State private var recordings: [URL] = []

    var body: some View {
        NavigationStack {
            List(
                recordings,
                id: \.self
            ) {
                Text($0.lastPathComponent)
            }
            .navigationTitle("Recordings")
            .onAppear {
                recordings = Self.load()
            }
        }
    }

    private static func load() -> [URL] {
        let documents =
            FileManager.default.urls(
                for: .documentDirectory,
                in: .userDomainMask
            )[0]

        let recordingsFolder =
            documents.appendingPathComponent(
                "Recordings"
            )

        return (
            try? FileManager.default.contentsOfDirectory(
                at: recordingsFolder,
                includingPropertiesForKeys: [
                    .creationDateKey
                ],
                options: .skipsHiddenFiles
            )
        )?
        .sorted {
            $0.lastPathComponent >
            $1.lastPathComponent
        }
        ?? []
    }
}