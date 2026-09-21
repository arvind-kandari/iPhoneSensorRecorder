import AVFoundation
import Foundation
import UIKit

struct CameraFormatOption: Identifiable, Hashable {
    let format: AVCaptureDevice.Format
    let width: Int
    let height: Int
    let fps: Double

    var id: String {
        "\(width)x\(height)-\(fps)"
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    var resolutionLabel: String {
        switch max(width, height) {
        case 3840...:
            return "4K"
        case 2560...:
            return "2K / 1440p"
        case 1920...:
            return "1080p"
        case 1280...:
            return "720p"
        default:
            return "480p"
        }
    }
}

final class CameraRecorder: NSObject {

    let captureSession = AVCaptureSession()

    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()

    private let sessionQueue =
        DispatchQueue(label: "CameraRecorder.SessionQueue")

    private let videoQueue =
        DispatchQueue(label: "CameraRecorder.VideoQueue")

    private let audioQueue =
        DispatchQueue(label: "CameraRecorder.AudioQueue")

    private let deliveryLock = NSLock()

    private var camera: AVCaptureDevice?
    private var cameraInput: AVCaptureDeviceInput?

    private var microphoneInput: AVCaptureDeviceInput?

    private var cameraPosition: AVCaptureDevice.Position = .back

    private var torchIsOn = false
    private var isConfigured = false
    private var deliversFrames = false

    private(set) var formatOptions: [CameraFormatOption] = []
    private(set) var selectedFormat: CameraFormatOption?

    var onFrame: ((CMSampleBuffer, TimeInterval) -> Void)?
    var onAudioFrame: ((CMSampleBuffer) -> Void)?

    var onConfigured: ((Int, Int) -> Void)?
    var onConfigurationFailed: ((String) -> Void)?

    var onFormatsChanged:
        (([CameraFormatOption], CameraFormatOption?) -> Void)?

    var onCameraChanged:
        ((Bool, Bool, Bool) -> Void)?

    // MARK: - Configuration

    func configure() {

        sessionQueue.async { [weak self] in

            guard let self, !self.isConfigured else {
                return
            }

            self.captureSession.beginConfiguration()
            self.captureSession.sessionPreset = .inputPriority

            // MARK: Camera

            guard let camera = self.camera(for: .back) else {
                self.captureSession.commitConfiguration()
                self.fail("Back camera is not available")
                return
            }

            self.camera = camera

            do {
                let input = try AVCaptureDeviceInput(device: camera)

                guard self.captureSession.canAddInput(input) else {
                    self.captureSession.commitConfiguration()
                    self.fail("Cannot add the back camera input")
                    return
                }

                self.captureSession.addInput(input)
                self.cameraInput = input

            } catch {
                self.captureSession.commitConfiguration()
                self.fail(
                    "Camera input error: \(error.localizedDescription)"
                )
                return
            }

            // MARK: Microphone

            guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
                self.captureSession.commitConfiguration()
                self.requestMicrophonePermissionAndContinue()
                return
            }

            guard let microphone =
                AVCaptureDevice.default(
                    for: .audio
                ) else {
                self.captureSession.commitConfiguration()
                self.fail("Microphone is not available")
                return
            }

            do {
                let audioInput =
                    try AVCaptureDeviceInput(device: microphone)

                guard self.captureSession.canAddInput(audioInput) else {
                    self.captureSession.commitConfiguration()
                    self.fail("Cannot add the microphone input")
                    return
                }

                self.captureSession.addInput(audioInput)
                self.microphoneInput = audioInput

            } catch {
                self.captureSession.commitConfiguration()
                self.fail(
                    "Microphone input error: \(error.localizedDescription)"
                )
                return
            }

            // MARK: Video Output

            self.videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String:
                    kCVPixelFormatType_32BGRA
            ]

            self.videoOutput.alwaysDiscardsLateVideoFrames = false

            self.videoOutput.setSampleBufferDelegate(
                self,
                queue: self.videoQueue
            )

            guard self.captureSession.canAddOutput(
                self.videoOutput
            ) else {
                self.captureSession.commitConfiguration()
                self.fail("Cannot add the camera video output")
                return
            }

            self.captureSession.addOutput(self.videoOutput)

            // MARK: Audio Output

            self.audioOutput.setSampleBufferDelegate(
                self,
                queue: self.audioQueue
            )

            guard self.captureSession.canAddOutput(
                self.audioOutput
            ) else {
                self.captureSession.commitConfiguration()
                self.fail("Cannot add the microphone audio output")
                return
            }

            self.captureSession.addOutput(self.audioOutput)

            // MARK: Formats

            self.formatOptions =
                self.supportedOptions(camera)

            self.selectedFormat =
                self.formatOptions.first(
                    where: {
                        $0.width == 1920 &&
                        $0.height == 1080 &&
                        $0.fps == 30
                    }
                )
                ?? self.formatOptions.first

            guard let selected = self.selectedFormat else {
                self.captureSession.commitConfiguration()
                self.fail(
                    "No supported camera resolution and frame-rate combination is available"
                )
                return
            }

            if let error = self.apply(
                selected,
                camera: camera
            ) {
                self.selectedFormat = nil
                self.captureSession.commitConfiguration()
                self.fail(error)
                return
            }

            self.configureAudioSession()

            self.captureSession.commitConfiguration()

            self.isConfigured = true

            self.captureSession.startRunning()

            self.reportConfiguration()
            self.reportCamera()
        }
    }

    private func requestMicrophonePermissionAndContinue() {

        AVCaptureDevice.requestAccess(for: .audio) {
            [weak self] granted in

            guard let self else {
                return
            }

            self.sessionQueue.async {

                guard granted else {
                    self.fail(
                        "Microphone permission is required for audio recording."
                    )
                    return
                }

                self.configure()
            }
        }
    }

    private func configureAudioSession() {

        do {
            let audioSession =
                AVAudioSession.sharedInstance()

            try audioSession.setCategory(
                .playAndRecord,
                mode: .videoRecording,
                options: [
                    .defaultToSpeaker,
                    .allowBluetooth
                ]
            )

            try audioSession.setActive(true)

        } catch {
            print(
                "Audio session configuration warning: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Video Format

    func selectFormat(
        _ option: CameraFormatOption
    ) {

        sessionQueue.async { [weak self] in

            guard let self,
                  self.isConfigured,
                  let camera = self.camera,
                  self.formatOptions.contains(option)
            else {
                return
            }

            self.captureSession.beginConfiguration()

            if let error = self.apply(
                option,
                camera: camera
            ) {
                self.captureSession.commitConfiguration()
                self.fail(error)
                return
            }

            self.captureSession.commitConfiguration()

            self.selectedFormat = option

            self.reportConfiguration()
        }
    }

    // MARK: - Camera

    func switchCamera() {

        sessionQueue.async { [weak self] in

            guard let self,
                  self.isConfigured
            else {
                return
            }

            let newPosition:
                AVCaptureDevice.Position =
                    self.cameraPosition == .back
                    ? .front
                    : .back

            guard let newCamera =
                    self.camera(for: newPosition)
            else {
                return
            }

            do {

                let newInput =
                    try AVCaptureDeviceInput(
                        device: newCamera
                    )

                let newOptions =
                    self.supportedOptions(newCamera)

                guard let selected =
                        newOptions.first(
                            where: {
                                $0.width == 1920 &&
                                $0.height == 1080 &&
                                $0.fps == 30
                            }
                        )
                        ?? newOptions.first
                else {
                    self.fail(
                        "No supported camera resolution and frame-rate combination is available"
                    )
                    return
                }

                if let error =
                    self.apply(
                        selected,
                        camera: newCamera
                    ) {

                    self.fail(error)
                    return
                }

                let wasRunning =
                    self.captureSession.isRunning

                if wasRunning {
                    self.captureSession.stopRunning()
                }

                self.captureSession.beginConfiguration()

                if let oldCamera = self.camera {
                    self.setTorch(
                        false,
                        on: oldCamera
                    )
                }

                let oldInput = self.cameraInput

                if let oldInput {
                    self.captureSession.removeInput(oldInput)
                }

                guard self.captureSession.canAddInput(
                    newInput
                ) else {

                    if let oldInput {
                        self.captureSession.addInput(oldInput)
                    }

                    self.captureSession.commitConfiguration()

                    if wasRunning {
                        self.captureSession.startRunning()
                    }

                    self.reportCamera()
                    return
                }

                self.captureSession.addInput(newInput)

                self.camera = newCamera
                self.cameraInput = newInput
                self.cameraPosition = newPosition
                self.formatOptions = newOptions
                self.selectedFormat = selected

                self.captureSession.commitConfiguration()

                if wasRunning {
                    self.captureSession.startRunning()
                }

                self.reportConfiguration()
                self.reportCamera()

            } catch {

                self.fail(
                    "Camera switch error: \(error.localizedDescription)"
                )
            }
        }
    }

    // MARK: - Torch

    func toggleTorch() {

        sessionQueue.async { [weak self] in

            guard let self,
                  let camera = self.camera,
                  camera.hasTorch
            else {
                return
            }

            self.setTorch(
                !self.torchIsOn,
                on: camera
            )

            self.reportCamera()
        }
    }

    // MARK: - Recording

    func recordingTransform() -> CGAffineTransform {
        CGAffineTransform(rotationAngle: .pi / 2)
    }

    func start() {

        deliveryLock.lock()
        deliversFrames = true
        deliveryLock.unlock()
    }

    func stop(
        completion: @escaping () -> Void
    ) {
        deliveryLock.lock()
        deliversFrames = false
        deliveryLock.unlock()

        let group = DispatchGroup()

        group.enter()
        videoQueue.async {
            group.leave()
        }

        group.enter()
        audioQueue.async {
        group.leave()
    }

    group.notify(queue: sessionQueue) {
        completion()
    }
}

    // MARK: - Supported Formats

    private func supportedOptions(
        _ camera: AVCaptureDevice
    ) -> [CameraFormatOption] {

        let targets: [(Int, Int)] = [
            (640, 480),
            (1280, 720),
            (1920, 1080),
            (2560, 1440),
            (3840, 2160)
        ]

        let frameRates: [Double] = [
            24,
            30,
            60
        ]

        let options:
            [CameraFormatOption] =
            camera.formats.flatMap {
                format -> [CameraFormatOption] in

                let dimensions =
                    CMVideoFormatDescriptionGetDimensions(
                        format.formatDescription
                    )

                let width =
                    Int(dimensions.width)

                let height =
                    Int(dimensions.height)

                guard targets.contains(
                    where: {
                        $0.0 == width &&
                        $0.1 == height
                    }
                ) else {
                    return []
                }

                return frameRates.compactMap {
                    fps in

                    guard format.videoSupportedFrameRateRanges
                        .contains(
                            where: {
                                $0.minFrameRate <= fps &&
                                fps <= $0.maxFrameRate
                            }
                        )
                    else {
                        return nil
                    }

                    return CameraFormatOption(
                        format: format,
                        width: width,
                        height: height,
                        fps: fps
                    )
                }
            }

        var seen = Set<String>()

        return options
            .filter {
                seen.insert($0.id).inserted
            }
            .sorted {
                if $0.width != $1.width {
                    return $0.width < $1.width
                }

                if $0.height != $1.height {
                    return $0.height < $1.height
                }

                return $0.fps < $1.fps
            }
    }

    private func camera(
        for position: AVCaptureDevice.Position
    ) -> AVCaptureDevice? {

        if position == .back {

            return AVCaptureDevice.default(
                .builtInWideAngleCamera,
                for: .video,
                position: .back
            )
        }

        return AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInWideAngleCamera,
                .builtInTrueDepthCamera
            ],
            mediaType: .video,
            position: .front
        )
        .devices
        .first
    }

    private func setTorch(
        _ enabled: Bool,
        on camera: AVCaptureDevice
    ) {

        guard camera.hasTorch else {
            torchIsOn = false
            return
        }

        do {

            try camera.lockForConfiguration()

            defer {
                camera.unlockForConfiguration()
            }

            camera.torchMode =
                enabled
                ? .on
                : .off

            torchIsOn = enabled

        } catch {

            torchIsOn = false
        }
    }

    private func apply(
        _ option: CameraFormatOption,
        camera: AVCaptureDevice
    ) -> String? {

        do {

            try camera.lockForConfiguration()

            defer {
                camera.unlockForConfiguration()
            }

            camera.activeFormat =
                option.format

            let duration =
                CMTime(
                    value: 1,
                    timescale: CMTimeScale(option.fps)
                )

            camera.activeVideoMinFrameDuration =
                duration

            camera.activeVideoMaxFrameDuration =
                duration

            guard
                CMFormatDescriptionEqual(
                    camera.activeFormat.formatDescription,
                    otherFormatDescription:
                        option.format.formatDescription
                ),
                CMTimeCompare(
                    camera.activeVideoMinFrameDuration,
                    duration
                ) == 0,
                CMTimeCompare(
                    camera.activeVideoMaxFrameDuration,
                    duration
                ) == 0
            else {

                return
                    "Camera could not apply \(option.resolutionLabel) at \(Int(option.fps)) FPS"
            }

            return nil

        } catch {

            return
                "Camera format error: \(error.localizedDescription)"
        }
    }

    private func fail(
        _ message: String
    ) {
        onConfigurationFailed?(message)
    }

    private func reportConfiguration() {

        guard let selectedFormat else {
            return
        }

        onFormatsChanged?(
            formatOptions,
            selectedFormat
        )

        onConfigured?(
            selectedFormat.width,
            selectedFormat.height
        )
    }

    private func reportCamera() {

        onCameraChanged?(
            cameraPosition == .front,
            camera?.hasTorch == true,
            torchIsOn
        )
    }
}

// MARK: - Capture Output Delegate

extension CameraRecorder:
    AVCaptureVideoDataOutputSampleBufferDelegate,
    AVCaptureAudioDataOutputSampleBufferDelegate {

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {

        deliveryLock.lock()

        let shouldDeliver = deliversFrames

        deliveryLock.unlock()

        guard shouldDeliver else {
            return
        }

        guard CMSampleBufferDataIsReady(sampleBuffer) else {
            return
        }

        if output === videoOutput {

            onFrame?(
                sampleBuffer,
                CMTimeGetSeconds(
                    CMSampleBufferGetPresentationTimeStamp(
                        sampleBuffer
                    )
                )
            )

        } else if output === audioOutput {

            onAudioFrame?(sampleBuffer)
        }
    }
}
