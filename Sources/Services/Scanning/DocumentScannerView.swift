import SwiftUI
import VisionKit

/// Envoltorio de `VNDocumentCameraViewController` (VisionKit). Reutiliza la
/// detección de bordes y recorte nativos: NO reimplementamos nada de eso.
/// Devuelve las páginas en orden, a resolución completa y SIN filtro aplicado
/// (el filtro se elige después, §5.2).
struct DocumentScannerView: UIViewControllerRepresentable {
    var onFinish: ([UIImage]) -> Void
    var onCancel: () -> Void
    var onError: (Error) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish, onCancel: onCancel, onError: onError)
    }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {
        // Sin estado que actualizar: el controlador es efímero.
    }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        private let onFinish: ([UIImage]) -> Void
        private let onCancel: () -> Void
        private let onError: (Error) -> Void

        init(onFinish: @escaping ([UIImage]) -> Void,
             onCancel: @escaping () -> Void,
             onError: @escaping (Error) -> Void) {
            self.onFinish = onFinish
            self.onCancel = onCancel
            self.onError = onError
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            // Extraemos cada página en orden. imageOfPage(at:) ya viene recortada.
            var paginas: [UIImage] = []
            paginas.reserveCapacity(scan.pageCount)
            for i in 0..<scan.pageCount {
                paginas.append(scan.imageOfPage(at: i))
            }
            onFinish(paginas)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onCancel()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFailWithError error: Error) {
            onError(error)
        }
    }
}
