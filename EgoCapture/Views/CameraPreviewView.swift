import SwiftUI
import AVFoundation

/// Hardware-composited camera preview using AVCaptureVideoPreviewLayer.
/// Zero CPU/GPU cost on the capture pipeline — the display compositor handles it.
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        if view.previewLayer.connection?.isVideoRotationAngleSupported(0) == true {
            view.previewLayer.connection?.videoRotationAngle = 0
        }
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        uiView.previewLayer.session = session
    }

    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
