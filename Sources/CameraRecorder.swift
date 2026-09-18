import AVFoundation
import Foundation

struct CameraFormatOption: Identifiable, Hashable {
    let format: AVCaptureDevice.Format
    let width: Int
    let height: Int
    let fps: Double

    var id: String { "\(width)x\(height)-\(fps)" }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var resolutionLabel: String {
        switch max(width, height) {
        case 3840...: return "4K"
        case 2560...: return "2K / 1440p"
        case 1920...: return "1080p"
        case 1280...: return "720p"
        default: return "480p"
        }
    }
}

final class CameraRecorder: NSObject {
    let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "CameraRecorder.SessionQueue")
    private let videoQueue = DispatchQueue(label: "CameraRecorder.VideoQueue")
    private let deliveryLock = NSLock()
    private var camera: AVCaptureDevice?
    private var isConfigured = false
    private var deliversFrames = false

    private(set) var formatOptions: [CameraFormatOption] = []
    private(set) var selectedFormat: CameraFormatOption?
    var onFrame: ((CMSampleBuffer, TimeInterval) -> Void)?
    var onConfigured: ((Int, Int) -> Void)?
    var onConfigurationFailed: ((String) -> Void)?
    var onFormatsChanged: (([CameraFormatOption], CameraFormatOption?) -> Void)?

    func configure() {
        sessionQueue.async { [weak self] in
            guard let self, !self.isConfigured else { return }
            self.captureSession.beginConfiguration()
            self.captureSession.sessionPreset = .inputPriority
            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
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
            } catch {
                self.captureSession.commitConfiguration()
                self.fail("Camera input error: \(error.localizedDescription)")
                return
            }
            self.videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            self.videoOutput.alwaysDiscardsLateVideoFrames = false
            self.videoOutput.setSampleBufferDelegate(self, queue: self.videoQueue)
            guard self.captureSession.canAddOutput(self.videoOutput) else {
                self.captureSession.commitConfiguration()
                self.fail("Cannot add the camera video output")
                return
            }
            self.captureSession.addOutput(self.videoOutput)
            if let connection = self.videoOutput.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
            self.formatOptions = self.supportedOptions(camera)
            self.selectedFormat = self.formatOptions.first(where: { $0.width == 1920 && $0.height == 1080 && $0.fps == 30 }) ?? self.formatOptions.first
            guard let selected = self.selectedFormat else {
                self.captureSession.commitConfiguration()
                self.fail("No supported camera resolution and frame-rate combination is available")
                return
            }
            if let error = self.apply(selected, camera: camera) {
                self.selectedFormat = nil
                self.captureSession.commitConfiguration()
                self.fail(error)
                return
            }
            self.captureSession.commitConfiguration()
            self.isConfigured = true
            self.captureSession.startRunning()
            self.reportConfiguration()
        }
    }

    func selectFormat(_ option: CameraFormatOption) {
        sessionQueue.async { [weak self] in
            guard let self, self.isConfigured, let camera = self.camera, self.formatOptions.contains(option) else { return }
            self.captureSession.beginConfiguration()
            if let error = self.apply(option, camera: camera) {
                self.captureSession.commitConfiguration()
                self.fail(error)
                return
            }
            self.captureSession.commitConfiguration()
            self.selectedFormat = option
            self.reportConfiguration()
        }
    }

    func start() {
        deliveryLock.lock()
        deliversFrames = true
        deliveryLock.unlock()
    }

    func stop(completion: @escaping () -> Void) {
        deliveryLock.lock()
        deliversFrames = false
        deliveryLock.unlock()
        videoQueue.async { completion() }
    }

    private func supportedOptions(_ camera: AVCaptureDevice) -> [CameraFormatOption] {
        let targets: [(Int, Int)] = [(640, 480), (1280, 720), (1920, 1080), (2560, 1440), (3840, 2160)]
        let frameRates: [Double] = [24, 30, 60]
        let options = camera.formats.flatMap { format in
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let width = Int(dimensions.width), height = Int(dimensions.height)
            guard targets.contains(where: { $0.0 == width && $0.1 == height }) else { return [] }
            return frameRates.compactMap { fps in
                guard format.videoSupportedFrameRateRanges.contains(where: { $0.minFrameRate <= fps && fps <= $0.maxFrameRate }) else { return nil }
                return CameraFormatOption(format: format, width: width, height: height, fps: fps)
            }
        }
        var seen = Set<String>()
        return options.filter { seen.insert($0.id).inserted }
            .sorted {
                if $0.width != $1.width { return $0.width < $1.width }
                if $0.height != $1.height { return $0.height < $1.height }
                return $0.fps < $1.fps
            }
    }

    private func apply(_ option: CameraFormatOption, camera: AVCaptureDevice) -> String? {
        do {
            try camera.lockForConfiguration()
            defer { camera.unlockForConfiguration() }
            camera.activeFormat = option.format
            let duration = CMTime(value: 1, timescale: CMTimeScale(option.fps))
            camera.activeVideoMinFrameDuration = duration
            camera.activeVideoMaxFrameDuration = duration
            guard CMFormatDescriptionEqual(camera.activeFormat.formatDescription, option.format.formatDescription),
                  CMTimeCompare(camera.activeVideoMinFrameDuration, duration) == 0,
                  CMTimeCompare(camera.activeVideoMaxFrameDuration, duration) == 0 else {
                return "Camera could not apply \(option.resolutionLabel) at \(Int(option.fps)) FPS"
            }
            return nil
        } catch {
            return "Camera format error: \(error.localizedDescription)"
        }
    }

    private func fail(_ message: String) {
        onConfigurationFailed?(message)
    }

    private func reportConfiguration() {
        guard let selectedFormat else { return }
        onFormatsChanged?(formatOptions, selectedFormat)
        onConfigured?(selectedFormat.width, selectedFormat.height)
    }
}

extension CameraRecorder: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        deliveryLock.lock()
        let shouldDeliver = deliversFrames
        deliveryLock.unlock()
        guard shouldDeliver else { return }
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }
        onFrame?(sampleBuffer, CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer)))
    }
}
