import SwiftUI
import UIKit
import AVFoundation

struct ContentView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var recordingSession = RecordingSession()
    @StateObject private var licenseManager = LicenseManager()
    @StateObject private var countdownSpeaker = CountdownSpeaker()

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
    @State private var countdownSeconds = 0
    @State private var countdownRemaining: Int?
    @State private var countdownTask: Task<Void, Never>?

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
        GeometryReader { safeAreaProxy in
            recordView(safeAreaInsets: safeAreaProxy.safeAreaInsets)
            .ignoresSafeArea()
            .overlay {
                if let countdownRemaining {
                    Text("\(countdownRemaining)")
                        .font(.system(size: 96, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(radius: 8)
                        .accessibilityLabel("Recording starts in \(countdownRemaining) seconds")
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .bottom) {
                bottomControls
                    .padding(.horizontal, 24)
                    .padding(.bottom, safeAreaProxy.safeAreaInsets.bottom + 12)
                    .ignoresSafeArea(.keyboard)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
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
                    for: UIApplication.willResignActiveNotification
                )
            ) { _ in
                cancelCountdown()
            }
            .onDisappear {
                cancelCountdown()
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

    private func recordView(safeAreaInsets: EdgeInsets) -> some View {
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
                        .padding(.top, 10)
                        .zIndex(1)
                }
                .padding(.horizontal, 20)
                .padding(.top, safeAreaInsets.top + 8)
                .padding(.bottom, safeAreaInsets.bottom + 110)
                .frame(
                    width: proxy.size.width,
                    height: proxy.size.height
                )
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
        HStack(spacing: 8) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.black.opacity(0.4), in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
            .disabled(recordingSession.state != .ready || countdownRemaining != nil)

            if recordingSession.hasTorch {
                Button(action: recordingSession.toggleTorch) {
                    Image(
                        systemName: recordingSession.torchIsOn
                            ? "bolt.fill"
                            : "bolt.slash.fill"
                    )
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.black.opacity(0.4), in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(recordingSession.state != .ready)
            }

            Spacer()

            Menu {
                Picker("Countdown Timer", selection: $countdownSeconds) {
                    ForEach([0, 3, 5, 10], id: \.self) { seconds in
                        Text("\(seconds) seconds").tag(seconds)
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "timer")
                    Text("\(countdownSeconds)s")
                        .monospacedDigit()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 82, height: 34)
                .background(.black.opacity(0.4), in: Capsule())
                .frame(height: 44)
            }
            .accessibilityLabel("Countdown Timer: \(countdownSeconds) seconds")
            .disabled(recordingSession.state != .ready || countdownRemaining != nil)

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.black.opacity(0.4), in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(
                recordingSession.state == .recording ||
                recordingSession.state == .paused ||
                countdownRemaining != nil
            )
        }
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
        HStack(spacing: 6) {
            zoomButton(0.5, title: "0.5x")
            zoomButton(1.0, title: "1x")
            zoomButton(2.0, title: "2x")
        }
        .padding(.horizontal, 12)
        .background(.black.opacity(0.4), in: Capsule())
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
            HStack(spacing: 12) {

                // PAUSE
                Button {
                    DispatchQueue.main.async {
                        recordingSession.pause()
                    }
                } label: {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
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
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(.red)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }

        case .paused:
            HStack(spacing: 12) {

                // RESUME
                Button {
                    DispatchQueue.main.async {
                        recordingSession.resume()
                    }
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
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
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(.red)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }

        default:
            Button {
                DispatchQueue.main.async {
                    startWithCountdown()
                }
            } label: {
                VStack(spacing: 3) {
                    Circle()
                        .stroke(.white, lineWidth: 3)
                        .frame(width: 56, height: 56)
                        .overlay {
                            Circle()
                                .fill(.red)
                                .padding(5)
                        }
                        .frame(width: 64, height: 64)

                    Text("RECORD")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .contentShape(Rectangle())
            .buttonStyle(.plain)
            .disabled(recordingSession.state != .ready || countdownRemaining != nil)
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
                showRecordings = true
            } label: {
                VStack(spacing: 3) {
                    Image(systemName: "folder")
                        .font(.system(size: 20, weight: .medium))
                        .frame(width: 38, height: 38)

                    Text("Recordings")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(.white)
                .frame(width: 72, height: 64)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            Button {
                recordingSession.switchCamera()
            } label: {
                Image(systemName: "camera.rotate")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(.black.opacity(0.4), in: Circle())
                    .frame(width: 72, height: 64)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Switch camera")
            .disabled(recordingSession.state != .ready)
        }
        .frame(height: 84)
        .overlay {
            cameraControls
        }
        .disabled(countdownRemaining != nil)
    }

    @MainActor
    private func startWithCountdown() {
        guard recordingSession.state == .ready, countdownRemaining == nil else {
            return
        }

        guard countdownSeconds > 0 else {
            recordingSession.start()
            return
        }

        countdownRemaining = countdownSeconds
        countdownTask = Task { @MainActor in
            do {
                for remaining in stride(from: countdownSeconds, through: 0, by: -1) {
                    try Task.checkCancellation()
                    countdownRemaining = remaining
                    let startedAt = Date()
                    let phrase = remaining == countdownSeconds
                        ? "Recording starts in \(remaining)"
                        : "\(remaining)"
                    guard await countdownSpeaker.speak(phrase) else {
                        if !Task.isCancelled {
                            cancelCountdown()
                        }
                        return
                    }
                    try Task.checkCancellation()

                    if remaining > 0 {
                        let delay = max(0, 1 - Date().timeIntervalSince(startedAt))
                        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    }
                }
            } catch {
                return
            }

            countdownRemaining = nil
            countdownTask = nil
            recordingSession.start()
        }
    }

    @MainActor
    private func cancelCountdown() {
        countdownTask?.cancel()
        countdownSpeaker.cancel()
        countdownTask = nil
        countdownRemaining = nil
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
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 32)
                .background(
                    .white.opacity(
                        abs(recordingSession.currentZoom - zoom) < 0.15
                            ? 0.3
                            : 0
                    ),
                    in: Capsule()
                )
                .frame(height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Spoken Countdown

private final class CountdownSpeaker: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var currentUtterance: AVSpeechUtterance?
    private var completion: CheckedContinuation<Bool, Never>?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    @MainActor
    func speak(_ text: String) async -> Bool {
        cancel()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        currentUtterance = utterance
        return await withCheckedContinuation { continuation in
            completion = continuation
            synthesizer.speak(utterance)
        }
    }

    @MainActor
    func cancel() {
        let pending = completion
        completion = nil
        currentUtterance = nil
        synthesizer.stopSpeaking(at: .immediate)
        pending?.resume(returning: false)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            finish(utterance, completed: true)
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            finish(utterance, completed: false)
        }
    }

    @MainActor
    private func finish(_ utterance: AVSpeechUtterance, completed: Bool) {
        guard utterance === currentUtterance else {
            return
        }
        let pending = completion
        completion = nil
        currentUtterance = nil
        pending?.resume(returning: completed)
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
