import AVFoundation
import SwiftUI

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    var onFocusTap: ((CGPoint, CGPoint) -> Void)?

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()

        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.onFocusTap = onFocusTap

        rotate(view.previewLayer.connection)

        return view
    }

    func updateUIView(
        _ view: PreviewView,
        context: Context
    ) {
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.onFocusTap = onFocusTap

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

    var onFocusTap: ((CGPoint, CGPoint) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        addFocusTapGesture()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        addFocusTapGesture()
    }

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

    private func addFocusTapGesture() {
        let tap = UITapGestureRecognizer(
            target: self,
            action: #selector(handleFocusTap)
        )
        tap.cancelsTouchesInView = false
        addGestureRecognizer(tap)
    }

    @objc private func handleFocusTap(
        _ gesture: UITapGestureRecognizer
    ) {
        let layerPoint = gesture.location(in: self)
        let devicePoint = previewLayer.captureDevicePointConverted(
            fromLayerPoint: layerPoint
        )
        onFocusTap?(layerPoint, devicePoint)
    }
}
