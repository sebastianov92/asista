import Foundation
import UIKit
import Vision

/// Servicio de reconocimiento de texto (OCR) sobre imágenes de páginas.
/// Motor puro, sin UI. Corre trabajo pesado fuera del hilo principal y
/// nunca lanza excepciones: ante cualquier fallo devuelve "" o struct vacío.
enum OCRService {

    /// Reconoce texto de varias páginas y devuelve el texto concatenado.
    static func reconocerTexto(_ imagenes: [UIImage]) async -> String {
        var paginas: [String] = []
        for imagen in imagenes {
            let texto = await reconocerPagina(imagen)
            if !texto.isEmpty { paginas.append(texto) }
        }
        // Concatenamos todas las páginas en orden.
        return paginas.joined(separator: "\n")
    }

    /// Reconoce + extrae campos. Corre en background.
    static func procesar(_ imagenes: [UIImage]) async -> CamposDetectados {
        let texto = await reconocerTexto(imagenes)
        guard !texto.isEmpty else { return CamposDetectados() }
        return FieldExtractor.extraer(de: texto)
    }

    // MARK: - Interno

    /// Ejecuta Vision sobre una sola imagen. Devuelve el texto reconocido
    /// (candidato principal por línea, unido por saltos de línea) o "".
    private static func reconocerPagina(_ imagen: UIImage) async -> String {
        // Convertimos UIImage → CGImage honrando la orientación.
        guard let cgImage = imagen.cgImage else { return "" }
        let orientation = cgOrientation(from: imagen.imageOrientation)

        return await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
            let request = VNRecognizeTextRequest { req, _ in
                guard let observaciones = req.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: "")
                    return
                }
                // Vision entrega las observaciones aprox. de arriba hacia abajo,
                // que es el orden de lectura que necesitamos.
                let lineas = observaciones.compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lineas.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["es-EC", "es-ES", "en-US"]
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
            do {
                try handler.perform([request])
            } catch {
                // Nunca lanzamos: devolvemos "" ante cualquier fallo.
                continuation.resume(returning: "")
            }
        }
    }

    /// Mapea la orientación de UIImage a CGImagePropertyOrientation.
    private static func cgOrientation(from orientation: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch orientation {
        case .up:            return .up
        case .down:          return .down
        case .left:          return .left
        case .right:         return .right
        case .upMirrored:    return .upMirrored
        case .downMirrored:  return .downMirrored
        case .leftMirrored:  return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default:    return .up
        }
    }
}
