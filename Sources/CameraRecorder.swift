import Foundation
import AVFoundation

final class CameraRecorder: NSObject {

    let captureSession = AVCaptureSession()

    private let videoOutput =
        AVCaptureVideoDataOutput()

    private let sessionQueue =
        DispatchQueue(
            label: "CameraRecorder.SessionQueue"
        )

    private var isConfigured = false

    var onFrame:
        ((CMSampleBuffer, TimeInterval) -> Void)?

    var onConfigured:
        ((Int, Int) -> Void)?

    func configure() {

        sessionQueue.async { [weak self] in

            guard let self = self else {
                return
            }

            guard !self.isConfigured else {
                return
            }

            self.captureSession.beginConfiguration()

            self.captureSession.sessionPreset = .high

            guard let camera =
                    AVCaptureDevice.default(
                        .builtInWideAngleCamera,
                        for: .video,
                        position: .back
                    ) else {

                print(
                    "Back camera not available"
                )

                self.captureSession.commitConfiguration()

                return
            }

            do {

                let input =
                    try AVCaptureDeviceInput(
                        device: camera
                    )

                guard self.captureSession.canAddInput(
                    input
                ) else {

                    print(
                        "Cannot add camera input"
                    )

                    self.captureSession.commitConfiguration()

                    return
                }

                self.captureSession.addInput(input)

            } catch {

                print(
                    "Camera input error: " +
                    error.localizedDescription
                )

                self.captureSession.commitConfiguration()

                return
            }

            self.videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String:
                    kCVPixelFormatType_32BGRA
            ]

            self.videoOutput.alwaysDiscardsLateVideoFrames =
                false

            self.videoOutput.setSampleBufferDelegate(
                self,
                queue:
                    DispatchQueue(
                        label:
                            "CameraRecorder.VideoQueue"
                    )
            )

            guard self.captureSession.canAddOutput(
                self.videoOutput
            ) else {

                print(
                    "Cannot add video output"
                )

                self.captureSession.commitConfiguration()

                return
            }

            self.captureSession.addOutput(
                self.videoOutput
            )

            if let connection =
                    self.videoOutput.connection(
                        with: .video
                    ) {

                if connection.isVideoRotationAngleSupported(
                    90
                ) {

                    connection.videoRotationAngle = 90
                }
            }

            let dimensions =
                CMVideoFormatDescriptionGetDimensions(
                    camera.activeFormat.formatDescription
                )

            let width =
                Int(dimensions.width)

            let height =
                Int(dimensions.height)

            self.captureSession.commitConfiguration()

            self.isConfigured = true

            self.onConfigured?(
                width,
                height
            )

            print(
                "Camera configured: " +
                "\(width)x\(height)"
            )
        }
    }

    func start() {

        sessionQueue.async { [weak self] in

            guard let self = self else {
                return
            }

            guard self.isConfigured else {

                print(
                    "Camera is not configured"
                )

                return
            }

            guard !self.captureSession.isRunning else {
                return
            }

            self.captureSession.startRunning()

            print(
                "Camera started"
            )
        }
    }

    func stop(
        completion: @escaping () -> Void
    ) {

        sessionQueue.async { [weak self] in

            guard let self = self else {

                completion()

                return
            }

            if self.captureSession.isRunning {

                self.captureSession.stopRunning()

                print(
                    "Camera stopped"
                )
            }

            completion()
        }
    }
}

extension CameraRecorder:
    AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {

        guard CMSampleBufferDataIsReady(
            sampleBuffer
        ) else {
            return
        }

        let timestamp =
            CMSampleBufferGetPresentationTimeStamp(
                sampleBuffer
            )

        let seconds =
            CMTimeGetSeconds(timestamp)

        onFrame?(
            sampleBuffer,
            seconds
        )
    }
}