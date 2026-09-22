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
    @State private var showRecordings = false
    @State private var showSensorOverlay = false
    @State private var focusPoint: CGPoint?
    @State private var showsFocusIndicator = false
    @State private var exposureDragStartBias: Double?
    @State private var focusDismissWorkItem: DispatchWorkItem?

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
        ZStack {
            recordView
                .ignoresSafeArea()

            VStack {
                Spacer()

                bottomControls
                    .padding(.horizontal, 24)
                    .padding(.bottom, 22)
            }
            .ignoresSafeArea(.keyboard)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
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
            SettingsView(
                session: recordingSession,
                licenseManager: licenseManager
            )
        }
        .sheet(isPresented: $showRecordings) {
            RecordingsView()
        }
    }



    // MARK: - Record View

    private var recordView: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black
                    .ignoresSafeArea()

                CameraPreview(
                    session: recordingSession.captureSession,
                    isRecording: recordingSession.isRecording,
                    onFocusTap: handleFocusTap
                )
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )
                .clipped()
                .ignoresSafeArea()

                LinearGradient(
                    colors: [
                        .black.opacity(0.25),
                        .clear,
                        .black.opacity(0.55)
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

                    zoomControls
                        .padding(.top, 18)
                        .padding(.bottom, 118)
                        .zIndex(1)
                }
                .frame(
                    width: proxy.size.width,
                    height: proxy.size.height
                )
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .zIndex(3)

                if let focusPoint {
                    focusSquare(at: focusPoint)
                        .opacity(showsFocusIndicator ? 1 : 0)
                        .allowsHitTesting(false)

                    focusExposureControl(
                        at: focusPoint,
                        in: proxy.size
                    )
                    .opacity(showsFocusIndicator ? 1 : 0)
                    .allowsHitTesting(showsFocusIndicator)
                    .zIndex(2)
                }
            }
            .frame(
                width: proxy.size.width,
                height: proxy.size.height
            )
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
    }
    // MARK: - Top Controls

    private var topControls: some View {
        HStack {
            if recordingSession.hasTorch {
                Button(action: recordingSession.toggleTorch) {
                    Image(
                        systemName: recordingSession.torchIsOn
                            ? "bolt.fill"
                            : "bolt.slash.fill"
                    )
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(recordingSession.state != .ready)
            }

            Spacer()

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(
                recordingSession.state == .recording ||
                recordingSession.state == .paused
            )
        }
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

    private var zoomControls: some View {
        HStack(spacing: 18) {
            zoomButton(0.5, title: "0.5x")
            zoomButton(1.0, title: "1x")
            zoomButton(2.0, title: "2x")
        }
        .disabled(
            recordingSession.state != .ready ||
            recordingSession.isFrontCamera
        )
        .opacity(
            recordingSession.state == .ready &&
            !recordingSession.isFrontCamera
                ? 1
                : 0.55
        )
    }

    private func focusSquare(at point: CGPoint) -> some View {
        Rectangle()
            .stroke(.yellow, lineWidth: 2)
            .frame(width: 62, height: 62)
            .overlay {
                Image(systemName: "plus")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.yellow)
            }
            .position(point)
    }

    private func focusExposureControl(
        at focusPoint: CGPoint,
        in size: CGSize
    ) -> some View {
        let lineHeight: CGFloat = 120
        let controlPoint = CGPoint(
            x: min(max(focusPoint.x + 52, 22), size.width - 22),
            y: min(max(focusPoint.y, lineHeight / 2), size.height - lineHeight / 2)
        )
        let normalizedBias = min(
            max((recordingSession.exposureBias + 2) / 4, 0),
            1
        )
        let sunOffset = (0.5 - normalizedBias) * (lineHeight - 28)

        return ZStack {
            Capsule()
                .fill(.yellow)
                .frame(width: 2, height: lineHeight)

            Image(systemName: "sun.max.fill")
                .font(.title3)
                .foregroundStyle(.yellow)
                .offset(y: sunOffset)
        }
        .frame(width: 44, height: lineHeight)
        .contentShape(Rectangle())
        .position(controlPoint)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    focusDismissWorkItem?.cancel()
                    showsFocusIndicator = true

                    if exposureDragStartBias == nil {
                        exposureDragStartBias = recordingSession.exposureBias
                    }

                    recordingSession.setExposureBias(
                        (exposureDragStartBias ?? 0) -
                            Double(value.translation.height) / 60
                    )
                }
                .onEnded { _ in
                    exposureDragStartBias = nil
                    scheduleFocusDismissal()
                }
        )
        .disabled(recordingSession.state != .ready)
    }

    private func handleFocusTap(
        _ displayPoint: CGPoint,
        _ normalizedPoint: CGPoint
    ) {
        focusDismissWorkItem?.cancel()
        focusPoint = displayPoint

        withAnimation(.easeOut(duration: 0.15)) {
            showsFocusIndicator = true
        }

        recordingSession.focus(at: normalizedPoint)
        scheduleFocusDismissal()
    }

    private func scheduleFocusDismissal() {
        focusDismissWorkItem?.cancel()

        let item = DispatchWorkItem {
            withAnimation(.easeOut(duration: 0.2)) {
                showsFocusIndicator = false
            }
        }

        focusDismissWorkItem = item
        DispatchQueue.main.asyncAfter(
            deadline: .now() + 1,
            execute: item
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

    @ViewBuilder
    private var cameraControls: some View {
        switch recordingSession.state {

        case .recording:
            HStack(spacing: 28) {

                // PAUSE
                Button {
                    DispatchQueue.main.async {
                        recordingSession.pause()
                    }
                } label: {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 64, height: 64)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)

                // STOP
                Button {
                    DispatchQueue.main.async {
                        recordingSession.stop()
                    }
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.red)
                        .frame(width: 64, height: 64)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }

        case .paused:
            HStack(spacing: 28) {

                // RESUME
                Button {
                    DispatchQueue.main.async {
                        recordingSession.resume()
                    }
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 64, height: 64)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)

                // STOP
                Button {
                    DispatchQueue.main.async {
                        recordingSession.stop()
                    }
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.red)
                        .frame(width: 64, height: 64)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }

        default:
            Button {
                DispatchQueue.main.async {
                    recordingSession.start()
                }
            } label: {
                Circle()
                    .stroke(.white, lineWidth: 4)
                    .frame(width: 64, height: 64)
                    .overlay {
                        Circle()
                            .fill(.red)
                            .padding(5)
                    }
                    .contentShape(Circle())
            }
            .frame(width: 64, height: 64)
            .contentShape(Circle())
            .buttonStyle(.plain)
            .disabled(recordingSession.state != .ready)
            .opacity(
                recordingSession.state == .ready
                    ? 1
                    : 0.55
            )
        }
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        HStack(alignment: .center) {
            Button {
                // Already on the recording screen.
            } label: {
                VStack(spacing: 5) {
                    Image(systemName: "record.circle")
                        .font(.system(size: 26, weight: .medium))

                    Text("Record")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.red)
                .frame(width: 82)
            }
            .buttonStyle(.plain)

            Spacer()

            cameraControls

            Spacer()

            Button {
                showRecordings = true
            } label: {
                VStack(spacing: 5) {
                    Image(systemName: "folder")
                        .font(.system(size: 26, weight: .medium))

                    Text("Recordings")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(width: 100)
            }
            .buttonStyle(.plain)
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

    private func zoomButton(
        _ zoom: Double,
        title: String
    ) -> some View {
        Button {
            recordingSession.setZoom(zoom)
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(minWidth: 44, minHeight: 44)
                .background(
                    .white.opacity(
                        abs(recordingSession.currentZoom - zoom) < 0.15
                            ? 0.3
                            : 0
                    ),
                    in: Capsule()
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

// MARK: - Settings

private struct SettingsView: View {
    @ObservedObject var session: RecordingSession
    @ObservedObject var licenseManager: LicenseManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Recording") {
                    NavigationLink {
                        VideoSettingsView(session: session)
                    } label: {
                        Label(
                            "Video Settings",
                            systemImage: "video"
                        )
                    }
                }

                Section("Information") {
                    NavigationLink {
                        AboutView(licenseManager: licenseManager)
                    } label: {
                        Label(
                            "About",
                            systemImage: "info.circle"
                        )
                    }
                }
            }
            .navigationTitle("Settings")
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

                        Text("CapturE")
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
