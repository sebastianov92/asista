import UIKit
import PDFKit
import UniformTypeIdentifiers

enum PDFBuilderError: Error, LocalizedError {
    case sinPaginas
    case imagenInvalida(indice: Int)
    case escrituraFallida(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .sinPaginas: return "No hay páginas para generar el PDF."
        case .imagenInvalida(let i): return "La página \(i + 1) no se pudo convertir en PDF."
        case .escrituraFallida(let e): return "No se pudo escribir el PDF: \(e.localizedDescription)"
        }
    }
}

/// Genera un PDF por documento (§6.1). Cada imagen ya procesada (filtrada +
/// comprimida a JPEG) se convierte en una página del PDF.
enum PDFBuilder {

    /// Construye el PDF a partir de páginas JPEG ya comprimidas.
    ///
    /// PRIVACIDAD (§6.1): la metadata NO lleva datos del paciente. El PDF viaja
    /// por correo; solo fijamos `title` (genérico) y `creator = "Asista"`.
    static func construir(paginasJPEG: [Data], titulo: String, destino url: URL) throws {
        guard !paginasJPEG.isEmpty else { throw PDFBuilderError.sinPaginas }

        let pdf = PDFDocument()
        for (i, jpeg) in paginasJPEG.enumerated() {
            guard let imagen = UIImage(data: jpeg),
                  let pagina = PDFPage(image: imagen) else {
                throw PDFBuilderError.imagenInvalida(indice: i)
            }
            pdf.insert(pagina, at: i)
        }

        // Metadata mínima y sin PII.
        pdf.documentAttributes = [
            PDFDocumentAttribute.titleAttribute: titulo,
            PDFDocumentAttribute.creatorAttribute: "Asista"
        ]

        guard let data = pdf.dataRepresentation() else {
            throw PDFBuilderError.escrituraFallida(
                underlying: NSError(domain: "PDFBuilder", code: -1,
                                    userInfo: [NSLocalizedDescriptionKey: "dataRepresentation nil"]))
        }

        do {
            // Creamos el directorio padre y escribimos con protección completa.
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic, .completeFileProtection])
        } catch {
            throw PDFBuilderError.escrituraFallida(underlying: error)
        }
    }

    /// Conveniencia: aplica compresión a cada UIImage y luego construye el PDF.
    static func construir(imagenes: [UIImage],
                          preajuste: PreajusteCalidad,
                          escalaGrises: Bool,
                          titulo: String,
                          destino url: URL) throws {
        guard !imagenes.isEmpty else { throw PDFBuilderError.sinPaginas }

        var paginasJPEG: [Data] = []
        paginasJPEG.reserveCapacity(imagenes.count)
        for (i, img) in imagenes.enumerated() {
            guard let jpeg = ImageCompressor.comprimir(img,
                                                       preajuste: preajuste,
                                                       escalaGrises: escalaGrises) else {
                throw PDFBuilderError.imagenInvalida(indice: i)
            }
            paginasJPEG.append(jpeg)
        }
        try construir(paginasJPEG: paginasJPEG, titulo: titulo, destino: url)
    }
}
