import SwiftUI
import PhotosUI

/// Alternativa a la cámara (§5.4): importar imágenes ya existentes en Fotos.
/// Envoltorio fino de `PHPickerViewController` con selección múltiple.
/// Devuelve `[UIImage]` en el mismo orden en que el sistema entrega los resultados.
struct PhotoImportView: UIViewControllerRepresentable {
    var onFinish: ([UIImage]) -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 0            // 0 = sin límite (selección múltiple)
        config.preferredAssetRepresentationMode = .current
        let vc = PHPickerViewController(configuration: config)
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let onFinish: ([UIImage]) -> Void
        private let onCancel: () -> Void

        init(onFinish: @escaping ([UIImage]) -> Void, onCancel: @escaping () -> Void) {
            self.onFinish = onFinish
            self.onCancel = onCancel
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard !results.isEmpty else { onCancel(); return }

            // La carga de cada item es asíncrona; preservamos el orden usando un
            // arreglo del tamaño exacto e insertando por índice. Un grupo espera a todas.
            var imagenes = [UIImage?](repeating: nil, count: results.count)
            let grupo = DispatchGroup()

            for (indice, resultado) in results.enumerated() {
                let provider = resultado.itemProvider
                guard provider.canLoadObject(ofClass: UIImage.self) else { continue }
                grupo.enter()
                provider.loadObject(ofClass: UIImage.self) { objeto, _ in
                    if let img = objeto as? UIImage { imagenes[indice] = img }
                    grupo.leave()
                }
            }

            grupo.notify(queue: .main) { [onFinish, onCancel] in
                let ordenadas = imagenes.compactMap { $0 }
                if ordenadas.isEmpty { onCancel() } else { onFinish(ordenadas) }
            }
        }
    }
}
