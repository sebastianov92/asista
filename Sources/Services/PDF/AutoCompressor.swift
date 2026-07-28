import Foundation

/// Un cambio de preajuste propuesto para un documento.
struct AjusteCompresion {
    var documentoID: UUID
    var de: PreajusteCalidad
    var a: PreajusteCalidad
}

/// Auto-ajuste de compresión (§6.2). Si el total de los PDFs supera un umbral,
/// baja el preajuste de los documentos más pesados hasta quedar por debajo.
///
/// Esto es lógica pura: solo decide QUÉ documentos degradar. El llamador
/// re-genera los PDFs con los nuevos preajustes.
enum AutoCompressor {

    /// Tope duro de Gmail para adjuntos (referencia, §6.2).
    static let topeGmailBytes = 25 * 1024 * 1024

    struct Entrada {
        var id: UUID
        var tamanoBytes: Int
        var preajuste: PreajusteCalidad
    }

    /// Devuelve la lista de cambios a aplicar para que el total ≤ `umbralBytes`.
    ///
    /// Estrategia: mientras se supere el umbral, se degrada un paso el documento
    /// MÁS PESADO que todavía se pueda bajar (heaviest-first). Nunca baja de
    /// `.baja` salvo que `permitirDebajoDeBaja` sea true (no existe nivel inferior,
    /// así que en la práctica ese flag solo evita bucles infinitos).
    ///
    /// Como no re-generamos PDFs aquí, ESTIMAMOS el nuevo tamaño con un factor por
    /// nivel derivado de calidadJPEG · (ladoLargo²) (el área escala con el cuadrado
    /// del lado). Es una estimación conservadora suficiente para planificar.
    static func planificar(_ docs: [Entrada],
                           umbralBytes: Int = 15 * 1024 * 1024,
                           permitirDebajoDeBaja: Bool = false) -> [AjusteCompresion] {

        // Estado mutable de trabajo: preajuste actual y tamaño estimado por doc.
        struct Estado {
            let id: UUID
            let preajusteOriginal: PreajusteCalidad
            var preajuste: PreajusteCalidad
            var tamano: Double
        }
        var estados = docs.map {
            Estado(id: $0.id,
                   preajusteOriginal: $0.preajuste,
                   preajuste: $0.preajuste,
                   tamano: Double($0.tamanoBytes))
        }

        func total() -> Double { estados.reduce(0) { $0 + $1.tamano } }

        // Factor multiplicativo estimado al pasar de un nivel al siguiente inferior.
        func factorDegradacion(_ de: PreajusteCalidad, _ a: PreajusteCalidad) -> Double {
            let areaDe = de.ladoLargo * de.ladoLargo
            let areaA = a.ladoLargo * a.ladoLargo
            let f = (Double(a.calidadJPEG) * Double(areaA)) /
                    (Double(de.calidadJPEG) * Double(areaDe))
            return min(1.0, f)   // nunca "agranda"
        }

        let umbral = Double(umbralBytes)
        var guardas = estados.count * 3 + 3   // evita bucles infinitos

        while total() > umbral && guardas > 0 {
            guardas -= 1

            // Candidato: el doc más pesado que aún tenga un nivel inferior disponible.
            let candidatoIdx = estados.indices
                .filter { siguienteNivel(estados[$0].preajuste, permitirDebajoDeBaja) != nil }
                .max(by: { estados[$0].tamano < estados[$1].tamano })

            guard let idx = candidatoIdx,
                  let siguiente = siguienteNivel(estados[idx].preajuste, permitirDebajoDeBaja) else {
                break   // ya no hay nada que bajar
            }

            let factor = factorDegradacion(estados[idx].preajuste, siguiente)
            estados[idx].preajuste = siguiente
            estados[idx].tamano *= factor
        }

        // Reportamos solo los que cambiaron respecto al preajuste original.
        return estados.compactMap { e in
            guard e.preajuste != e.preajusteOriginal else { return nil }
            return AjusteCompresion(documentoID: e.id, de: e.preajusteOriginal, a: e.preajuste)
        }
    }

    /// Siguiente nivel inferior de calidad, o nil si no hay.
    private static func siguienteNivel(_ p: PreajusteCalidad,
                                       _ permitirDebajoDeBaja: Bool) -> PreajusteCalidad? {
        switch p {
        case .alta: return .media
        case .media: return .baja
        case .baja: return nil   // no existe nivel inferior; el flag no crea uno
        }
    }
}
