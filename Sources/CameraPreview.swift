import AVFoundation
import SwiftUI

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()

        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill

        rotate(view.previewLayer.connection)

        return view
    }

    func updateUIView(
        _ view: PreviewView,
        context: Context
    ) {
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill

        rotate(view.previewLayer.connection)
    }

    private func rotate(
        _ connection: AVCaptureConnection?
    ) {
        guard
            let connection,
            connection.isVideoRotationAngleSupported(90)
        else {
            return
        }

        connection.videoRotationAngle = 90
    }
}

final class PreviewView: UIView {

    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        previewLayer.frame = bounds
        previewLayer.videoGravity = .resizeAspectFill
    }
}