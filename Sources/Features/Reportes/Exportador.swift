import Foundation

// Exportación de datos (§15.3): CSV de reclamos y ZIP de PDFs de un reclamo.
// Sin dependencias externas. El ZIP se genera con NSFileCoordinator.

enum Exportador {

    enum ExportadorError: Error {
        case sinDocumentos
        case zipFallido
    }

    // MARK: - CSV

    /// CSV de reclamos: fecha,paciente,poliza,prestador,diagnostico,
    /// montoReclamado,montoReembolsado,estado.
    /// Escribe un .csv temporal (UTF-8 con BOM para Excel) y devuelve su URL.
    static func csvReclamos(_ reclamos: [Reclamo]) throws -> URL {
        let encabezado = [
            "fecha", "paciente", "poliza", "prestador",
            "diagnostico", "montoReclamado", "montoReembolsado", "estado"
        ]

        var lineas: [String] = [fila(encabezado)]

        let fmtFecha = DateFormatter()
        fmtFecha.locale = Locale(identifier: "en_US_POSIX")
        fmtFecha.dateFormat = "yyyy-MM-dd"

        for r in reclamos {
            let paciente = r.cobertura?.paciente?.nombreCompleto ?? ""
            let poliza = r.cobertura?.poliza?.nombreVisible ?? ""
            // Monto crudo con punto decimal (no separador de miles) para Excel.
            let reclamado = "\(r.montoReclamado)"
            let reembolsado = r.montoReembolsado.map { "\($0)" } ?? ""
            let campos = [
                fmtFecha.string(from: r.fechaEvento),
                paciente,
                poliza,
                r.prestador,
                r.diagnostico,
                reclamado,
                reembolsado,
                r.estado.etiqueta
            ]
            lineas.append(fila(campos))
        }

        let contenido = lineas.joined(separator: "\r\n")
        var datos = Data([0xEF, 0xBB, 0xBF])   // BOM UTF-8
        datos.append(Data(contenido.utf8))

        let nombre = "Reclamos-\(Int(Date().timeIntervalSince1970)).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(nombre)
        try datos.write(to: url, options: .atomic)
        return url
    }

    /// Une campos de una fila con comas, entrecomillando cuando es necesario.
    private static func fila(_ campos: [String]) -> String {
        campos.map(escapar).joined(separator: ",")
    }

    /// Entrecomilla si el campo tiene coma, comilla o salto de línea (RFC 4180).
    private static func escapar(_ campo: String) -> String {
        if campo.contains(",") || campo.contains("\"")
            || campo.contains("\n") || campo.contains("\r") {
            let interno = campo.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(interno)\""
        }
        return campo
    }

    // MARK: - ZIP

    /// ZIP con todos los PDFs de un reclamo. Copia los PDFs a una carpeta
    /// temporal y la comprime vía NSFileCoordinator (.forUploading).
    /// Devuelve la URL del .zip.
    static func zipReclamo(_ reclamo: Reclamo) throws -> URL {
        let fm = FileManager.default

        // Carpeta temporal única que contendrá los PDFs.
        let base = fm.temporaryDirectory
            .appendingPathComponent("export-\(UUID().uuidString)", isDirectory: true)
        let carpeta = base.appendingPathComponent("Reclamo-\(reclamo.numero)", isDirectory: true)
        try fm.createDirectory(at: carpeta, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base) }

        // Copiar cada PDF existente (ordenados), evitando nombres duplicados.
        var copiados = 0
        let docs = reclamo.documentos.sorted { $0.orden < $1.orden }
        for (indice, doc) in docs.enumerated() {
            guard !doc.rutaPDF.isEmpty else { continue }
            let origen = FileStore.urlPDF(nombre: doc.rutaPDF)
            guard fm.fileExists(atPath: origen.path) else { continue }

            let nombre = nombreArchivo(indice: indice, doc: doc, ruta: doc.rutaPDF)
            let destino = carpeta.appendingPathComponent(nombre, isDirectory: false)
            try? fm.removeItem(at: destino)
            try fm.copyItem(at: origen, to: destino)
            copiados += 1
        }

        guard copiados > 0 else { throw ExportadorError.sinDocumentos }

        // Comprimir la CARPETA vía NSFileCoordinator.
        var zipTemporal: URL?
        var coordError: NSError?
        NSFileCoordinator().coordinate(
            readingItemAt: carpeta,
            options: [.forUploading],
            error: &coordError
        ) { tmp in
            // `tmp` es una copia comprimida efímera; la movemos a un destino estable.
            let destino = fm.temporaryDirectory
                .appendingPathComponent("Reclamo-\(reclamo.numero).zip")
            try? fm.removeItem(at: destino)
            do {
                try fm.copyItem(at: tmp, to: destino)
                zipTemporal = destino
            } catch {
                zipTemporal = nil
            }
        }

        if let coordError { throw coordError }
        guard let zipURL = zipTemporal else { throw ExportadorError.zipFallido }
        return zipURL
    }

    /// Nombre ASCII limpio para el PDF dentro del ZIP.
    private static func nombreArchivo(indice: Int, doc: Documento, ruta: String) -> String {
        let prefijo = String(format: "%02d", indice + 1)
        let etiqueta = doc.etiqueta
            .folding(options: .diacriticInsensitive, locale: .current)
            .replacingOccurrences(of: " ", with: "_")
        let limpio = etiqueta.filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
        let base = limpio.isEmpty ? "documento" : limpio
        return "\(prefijo)-\(base).pdf"
    }
}
