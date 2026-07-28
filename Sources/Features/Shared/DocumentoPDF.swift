import Foundation
import UIKit

// Regenera el PDF de un documento desde sus páginas originales aplicando filtro,
// rotación y un preajuste de calidad dado. Se usa al guardar y al recomprimir (§6.2).

enum DocumentoPDF {
    @discardableResult
    static func regenerar(_ doc: Documento, patron: String, preajuste: PreajusteCalidad) -> Bool {
        var jpegs: [Data] = []
        for pagina in doc.paginas.sorted(by: { $0.orden < $1.orden }) {
            let url = FileStore.urlOriginal(paginaID: pagina.id)
            guard let data = try? Data(contentsOf: url), let original = UIImage(data: data) else { continue }
            let filtrada = ImageFilters.aplicar(pagina.filtro, a: original, rotacion: pagina.rotacion)
            let grises = pagina.filtro == .escalaGrises || pagina.filtro == .blancoYNegro
            if let jpeg = ImageCompressor.comprimir(filtrada, preajuste: preajuste, escalaGrises: grises) {
                jpegs.append(jpeg)
            }
        }
        guard !jpegs.isEmpty else { return false }

        let nombre = FileNamer.nombre(documento: doc, patron: patron)
        let destino = FileStore.urlPDF(nombre: nombre)
        do {
            try PDFBuilder.construir(paginasJPEG: jpegs, titulo: doc.etiqueta, destino: destino)
            doc.rutaPDF = nombre
            doc.tamanoBytes = FileStore.tamano(destino)
            doc.preajusteCalidad = preajuste
            return true
        } catch {
            return false
        }
    }
}
