import UIKit

/// Redimensiona y comprime imágenes a JPEG ligero según el preajuste de calidad.
enum ImageCompressor {

    /// Redimensiona para que el lado largo ≤ `preajuste.ladoLargo` (NUNCA aumenta
    /// el tamaño original) y devuelve JPEG a `preajuste.calidadJPEG`.
    ///
    /// Si `escalaGrises` es true, se descarta el color antes del JPEG: un documento
    /// en grises pesa ~40% menos (§6).
    static func comprimir(_ imagen: UIImage,
                          preajuste: PreajusteCalidad,
                          escalaGrises: Bool = false) -> Data? {
        // Trabajamos en píxeles reales (size * scale), no en puntos.
        let anchoPx = imagen.size.width * imagen.scale
        let altoPx = imagen.size.height * imagen.scale
        let ladoLargoActual = max(anchoPx, altoPx)

        // Factor de escala: solo reducimos (nunca > 1).
        let factor = min(1.0, preajuste.ladoLargo / max(ladoLargoActual, 1))
        let nuevoTamano = CGSize(width: floor(anchoPx * factor),
                                 height: floor(altoPx * factor))

        // Renderizamos a escala 1 para controlar el tamaño exacto en píxeles.
        let formato = UIGraphicsImageRendererFormat.default()
        formato.scale = 1
        formato.opaque = escalaGrises   // opaco si vamos a grises (sin alfa)
        let renderer = UIGraphicsImageRenderer(size: nuevoTamano, format: formato)
        let redimensionada = renderer.image { _ in
            imagen.draw(in: CGRect(origin: .zero, size: nuevoTamano))
        }

        let salida = escalaGrises ? aGrises(redimensionada) ?? redimensionada : redimensionada
        return salida.jpegData(compressionQuality: preajuste.calidadJPEG)
    }

    /// Redibuja en un contexto de escala de grises de 8 bits (1 canal) para
    /// eliminar el color de verdad antes de codificar a JPEG.
    private static func aGrises(_ imagen: UIImage) -> UIImage? {
        guard let cg = imagen.cgImage else { return nil }
        let ancho = cg.width, alto = cg.height
        let espacio = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(data: nil,
                                  width: ancho,
                                  height: alto,
                                  bitsPerComponent: 8,
                                  bytesPerRow: 0,
                                  space: espacio,
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
            return nil
        }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: ancho, height: alto))
        guard let grisCG = ctx.makeImage() else { return nil }
        return UIImage(cgImage: grisCG, scale: 1, orientation: .up)
    }
}
