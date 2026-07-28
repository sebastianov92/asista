import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// Filtros de legibilidad para páginas escaneadas (§5.2).
///
/// GOTCHA: el `CIContext` es caro de crear. Se instancia UNA sola vez y se
/// reutiliza para todas las operaciones (thread-safe para render).
enum ImageFilters {

    /// Contexto compartido. Sin gestión de color extra para que el render sea rápido.
    private static let contexto = CIContext(options: [.useSoftwareRenderer: false])

    // MARK: - API pública

    /// Aplica `filtro` a `imagen` y opcionalmente la rota (0/90/180/270).
    /// Si algo falla, devuelve la imagen original (solo rotada) para no perder el escaneo.
    static func aplicar(_ filtro: FiltroEscaneo, a imagen: UIImage, rotacion: Int = 0) -> UIImage {
        // Normalizamos la orientación EXIF a .up antes de procesar en CoreImage,
        // porque CIImage ignora UIImage.imageOrientation y saldría torcida.
        guard let base = imagen.orientacionNormalizada().cgImage else {
            return imagen
        }
        var ci = CIImage(cgImage: base)

        // 1) Rotación solicitada por el usuario (además de la de EXIF ya aplicada).
        ci = ci.rotada(grados: rotacion)

        // 2) Pipeline de color según el filtro.
        let procesada: CIImage
        switch filtro {
        case .original:
            procesada = ci
        case .documento:
            procesada = documento(ci)
        case .escalaGrises:
            procesada = escalaGrises(ci)
        case .blancoYNegro:
            procesada = blancoYNegro(ci)
        }

        return render(procesada, escalaOriginal: imagen.scale) ?? imagen
    }

    /// Sugiere un filtro inicial mirando la saturación media (§5.2): si la imagen
    /// es casi monocroma (documento en tinta negra), proponemos escala de grises;
    /// de lo contrario, el realce de documento por defecto.
    static func sugerirFiltro(para imagen: UIImage) -> FiltroEscaneo {
        guard let cg = imagen.orientacionNormalizada().cgImage else { return .documento }
        let ci = CIImage(cgImage: cg)

        // Convertimos a HSV vía CIAreaAverage no da saturación directamente, así que
        // medimos la dispersión entre canales RGB del promedio: si R≈G≈B, saturación baja.
        let filtro = CIFilter.areaAverage()
        filtro.inputImage = ci
        filtro.extent = ci.extent
        guard let salida = filtro.outputImage else { return .documento }

        var pixel = [UInt8](repeating: 0, count: 4)
        contexto.render(salida,
                        toBitmap: &pixel,
                        rowBytes: 4,
                        bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                        format: .RGBA8,
                        colorSpace: CGColorSpaceCreateDeviceRGB())

        let r = CGFloat(pixel[0]), g = CGFloat(pixel[1]), b = CGFloat(pixel[2])
        let maxC = max(r, g, b), minC = min(r, g, b)
        // Saturación aproximada del color promedio (0…1).
        let saturacion = maxC <= 0 ? 0 : (maxC - minC) / maxC
        return saturacion < 0.12 ? .escalaGrises : .documento
    }

    // MARK: - Pipelines

    /// Realce de documento. Preferimos `CIDocumentEnhancer` (iOS 16+); si no está
    /// disponible o devuelve nil, caemos a un realce manual de contraste + nitidez.
    private static func documento(_ ci: CIImage) -> CIImage {
        if let mejorada = documentEnhancer(ci) { return mejorada }

        // Fallback manual (§5.2).
        let color = CIFilter.colorControls()
        color.inputImage = ci
        color.contrast = 1.35
        color.brightness = 0.08
        color.saturation = 0.6
        let base = color.outputImage ?? ci

        let sharpen = CIFilter.unsharpMask()
        sharpen.inputImage = base
        sharpen.radius = 1.5
        sharpen.intensity = 0.5
        return sharpen.outputImage ?? base
    }

    /// `CIDocumentEnhancer` no tiene builtin tipado estable en todas las versiones,
    /// así que lo instanciamos por nombre y comprobamos que exista.
    private static func documentEnhancer(_ ci: CIImage) -> CIImage? {
        guard let filtro = CIFilter(name: "CIDocumentEnhancer") else { return nil }
        filtro.setValue(ci, forKey: kCIInputImageKey)
        filtro.setValue(1.0, forKey: "inputAmount")
        return filtro.outputImage
    }

    private static func escalaGrises(_ ci: CIImage) -> CIImage {
        let mono = CIFilter.photoEffectMono()
        mono.inputImage = ci
        let base = mono.outputImage ?? ci

        let color = CIFilter.colorControls()
        color.inputImage = base
        color.contrast = 1.3
        return color.outputImage ?? base
    }

    /// Aproximación de umbral adaptativo: desaturamos y aplicamos un contraste muy
    /// fuerte para empujar los píxeles hacia negro/blanco (§5.2).
    private static func blancoYNegro(_ ci: CIImage) -> CIImage {
        let color = CIFilter.colorControls()
        color.inputImage = ci
        color.saturation = 0.0
        color.contrast = 3.0
        color.brightness = 0.0
        return color.outputImage ?? ci
    }

    // MARK: - Render

    private static func render(_ ci: CIImage, escalaOriginal: CGFloat) -> UIImage? {
        guard let cg = contexto.createCGImage(ci, from: ci.extent) else { return nil }
        // La imagen ya está en orientación .up; escala del dispositivo preservada.
        return UIImage(cgImage: cg, scale: escalaOriginal, orientation: .up)
    }
}

// MARK: - Helpers de orientación / rotación

private extension UIImage {
    /// Redibuja la imagen aplicando su `imageOrientation` para dejarla en `.up`.
    /// Necesario porque CoreImage ignora la orientación EXIF de UIImage.
    func orientacionNormalizada() -> UIImage {
        guard imageOrientation != .up else { return self }
        let formato = UIGraphicsImageRendererFormat.default()
        formato.scale = scale
        formato.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: formato)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

private extension CIImage {
    /// Rota `grados` (0/90/180/270) y reposiciona el origen para que el extent
    /// quede con origen positivo (evita coordenadas negativas al renderizar).
    func rotada(grados: Int) -> CIImage {
        let normal = ((grados % 360) + 360) % 360
        guard normal != 0 else { return self }
        let radianes = CGFloat(normal) * .pi / 180
        let rotada = transformed(by: CGAffineTransform(rotationAngle: radianes))
        // Reencuadramos al origen (0,0).
        return rotada.transformed(by: CGAffineTransform(translationX: -rotada.extent.origin.x,
                                                        y: -rotada.extent.origin.y))
    }
}
