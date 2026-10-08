import AVFoundation
import SwiftUI

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let isRecording: Bool
    var onFocusTap: ((CGPoint, CGPoint) -> Void)?

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: PreviewView,
        context: Context
    ) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height else {
            return nil
        }
        return CGSize(width: width, height: height)
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()

        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.onFocusTap = onFocusTap
        view.isRecording = isRecording

        rotate(view.previewLayer.connection)
        view.logPreviewState("[PREVIEW DEBUG] NEW PREVIEW LAYER")
        if !isRecording {
            view.logPreviewState("[PREVIEW DEBUG] BEFORE RECORD")
        }

        return view
    }

    func updateUIView(
        _ view: PreviewView,
        context: Context
    ) {
        let wasRecording = view.isRecording
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.onFocusTap = onFocusTap
        view.isRecording = isRecording

        rotate(view.previewLayer.connection)
        view.logPreviewState("[PREVIEW DEBUG] UPDATE UIView")

        if wasRecording != isRecording {
            view.logPreviewState(
                isRecording
                    ? "[PREVIEW DEBUG] AFTER isRecording=true"
                    : "[PREVIEW DEBUG] BEFORE RECORD"
            )
        }
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

    let previewLayer = AVCaptureVideoPreviewLayer()
    var onFocusTap: ((CGPoint, CGPoint) -> Void)?
    var isRecording = false
    private var lastConnectionIdentifier: ObjectIdentifier?

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.addSublayer(previewLayer)
        clipsToBounds = true
        addFocusTapGesture()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        layer.addSublayer(previewLayer)
        clipsToBounds = true
        addFocusTapGesture()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        // Size the video sublayer without moving SwiftUI's UIView backing layer.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer.frame = bounds
        previewLayer.videoGravity = .resizeAspectFill
        CATransaction.commit()
        logPreviewState("[PREVIEW DEBUG] LAYOUT SUBVIEWS")
    }

    func logPreviewState(_ label: String) {
        let connection = previewLayer.connection
        let connectionIdentifier = connection.map { ObjectIdentifier($0) }

        if connectionIdentifier != lastConnectionIdentifier {
            lastConnectionIdentifier = connectionIdentifier
            writePreviewState("[PREVIEW DEBUG] CONNECTION CHANGED")
        }

        writePreviewState(label)
    }

    private func writePreviewState(_ label: String) {
        let connection = previewLayer.connection
        let lines = [
            label,
            "isRecording: \(isRecording)",
            "view identity: \(ObjectIdentifier(self))",
            "preview layer identity: \(ObjectIdentifier(previewLayer))",
            "view bounds: \(String(describing: bounds))",
            "view frame: \(String(describing: frame))",
            "window bounds: \(window.map { String(describing: $0.bounds) } ?? "none")",
            "view frame in window: \(window.map { String(describing: convert(bounds, to: $0)) } ?? "none")",
            "preview bounds: \(String(describing: previewLayer.bounds))",
            "preview frame: \(String(describing: previewLayer.frame))",
            "videoGravity: \(previewLayer.videoGravity.rawValue)",
            "connection identity: \(connection.map { String(describing: ObjectIdentifier($0)) } ?? "none")",
            "connection orientation: \(connection?.videoOrientation.rawValue.description ?? "none")",
            "connection rotation: \(connection?.videoRotationAngle.description ?? "none")",
            "connection enabled: \(connection?.isEnabled.description ?? "none")"
        ]

        lines.forEach { print($0) }
        PreviewDebugLog.append(lines)
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

private enum PreviewDebugLog {
    static func append(_ lines: [String]) {
        guard let documentsURL = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else {
            print("[PREVIEW DEBUG] Documents directory unavailable")
            return
        }

        let timestamp = ISO8601DateFormatter().string(from: Date())
        let text = lines
            .map { "\(timestamp) \($0)" }
            .joined(separator: "\n") + "\n"
        let fileURL = documentsURL.appendingPathComponent("preview_debug.log")

        do {
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                try Data(text.utf8).write(to: fileURL, options: .atomic)
                return
            }

            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(text.utf8))
            try handle.synchronize()
        } catch {
            print("[PREVIEW DEBUG] File write failed:", error.localizedDescription)
        }
    }
}
