import Foundation
import UIKit
import PDFKit

// Corre OCR sobre una receta (imágenes escaneadas o un PDF ya importado) y
// devuelve la pauta detectada. Permite crear alarmas aunque la receta llegue
// como PDF (sin páginas escaneadas).

enum RecetaOCR {
    struct Resultado {
        var texto: String
        var pautas: [PautaDetectada]
    }

    static func desdeImagenes(_ imagenes: [UIImage]) async -> Resultado {
        let texto = await OCRService.reconocerTexto(imagenes)
        return Resultado(texto: texto, pautas: RecetaParser.parse(texto))
    }

    static func desdePDF(_ url: URL) async -> Resultado {
        let imagenes = renderPDF(url)
        return await desdeImagenes(imagenes)
    }

    /// Rinde cada página del PDF a imagen (2x) para el OCR.
    static func renderPDF(_ url: URL) -> [UIImage] {
        guard let doc = PDFDocument(url: url) else { return [] }
        var out: [UIImage] = []
        let escala: CGFloat = 2
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            let rect = page.bounds(for: .mediaBox)
            let size = CGSize(width: rect.width * escala, height: rect.height * escala)
            let img = UIGraphicsImageRenderer(size: size).image { c in
                UIColor.white.set()
                c.fill(CGRect(origin: .zero, size: size))
                c.cgContext.translateBy(x: 0, y: size.height)
                c.cgContext.scaleBy(x: escala, y: -escala)
                page.draw(with: .mediaBox, to: c.cgContext)
            }
            out.append(img)
        }
        return out
    }
}
