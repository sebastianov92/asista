import Foundation

/// Genera nombres de archivo para los PDFs de documentos.
///
/// REGLA CLAVE (§6.3, §8.2 regla 5): el nombre resultante DEBE ser ASCII puro
/// (sin tildes ni espacios), porque viaja como adjunto de correo y algunos
/// clientes destrozan nombres con caracteres no ASCII.
enum FileNamer {

    /// Construye el nombre a partir de un patrón con tokens.
    ///
    /// Tokens soportados:
    ///   {fecha}       reclamo.fechaEvento en yyyy-MM-dd
    ///   {paciente}    nombre del paciente en PascalCase ASCII
    ///   {orden}       documento.orden a 2 dígitos
    ///   {tipo}        TipoDocumento.slug (ya ASCII)
    ///   {aseguradora} nombre de la aseguradora (ASCII)
    ///   {poliza}      número/nombre visible de la póliza (ASCII)
    ///   {reclamo}     reclamo.numero
    ///
    /// Siempre agrega ".pdf". El resultado se pasa por `asciiSeguro` como red de
    /// seguridad final.
    static func nombre(documento: Documento,
                       patron: String = "{fecha}_{paciente}_{orden}-{tipo}") -> String {
        let reclamo = documento.reclamo
        let cobertura = reclamo?.cobertura
        let paciente = cobertura?.paciente
        let poliza = cobertura?.poliza
        let aseguradora = poliza?.aseguradora

        var resultado = patron

        // {fecha}
        let fecha: String
        if let evento = reclamo?.fechaEvento {
            fecha = Self.formatoFecha.string(from: evento)
        } else {
            fecha = "sin-fecha"
        }
        resultado = resultado.replacingOccurrences(of: "{fecha}", with: fecha)

        // {paciente}
        let nombrePaciente = pacientePascal(paciente?.nombreCompleto ?? "Paciente")
        resultado = resultado.replacingOccurrences(of: "{paciente}", with: nombrePaciente)

        // {orden} -> 2 dígitos
        let orden = String(format: "%02d", documento.orden)
        resultado = resultado.replacingOccurrences(of: "{orden}", with: orden)

        // {tipo} -> slug (ya ASCII, pero lo saneamos por si es .otro personalizado)
        let slug = asciiSeguro(documento.tipo.slug)
        resultado = resultado.replacingOccurrences(of: "{tipo}", with: slug)

        // {aseguradora}
        resultado = resultado.replacingOccurrences(
            of: "{aseguradora}",
            with: asciiSeguro(aseguradora?.nombre ?? ""))

        // {poliza}
        let etiquetaPoliza = poliza?.nombreVisible.isEmpty == false
            ? poliza!.nombreVisible
            : (poliza?.numero ?? "")
        resultado = resultado.replacingOccurrences(
            of: "{poliza}",
            with: asciiSeguro(etiquetaPoliza))

        // {reclamo}
        let numeroReclamo = reclamo.map { String($0.numero) } ?? "0"
        resultado = resultado.replacingOccurrences(of: "{reclamo}", with: numeroReclamo)

        // Red de seguridad: sanea TODO menos separadores permitidos, y agrega extensión.
        let base = asciiSeguro(resultado)
        return base.isEmpty ? "Documento.pdf" : base + ".pdf"
    }

    /// Normaliza cualquier cadena a ASCII: quita diacríticos (é→e), elimina
    /// espacios y conserva solo [A-Za-z0-9-_].
    static func asciiSeguro(_ s: String) -> String {
        // 1) Plegado insensible a diacríticos con locale POSIX (é→e, ñ→n).
        let sinTildes = s.folding(options: .diacriticInsensitive,
                                  locale: Locale(identifier: "en_US_POSIX"))
        // 2) Filtramos a los caracteres permitidos; el resto se descarta.
        let permitidos = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        let filtrada = String(sinTildes.unicodeScalars.filter { permitidos.contains($0) })
        return filtrada
    }

    /// Convierte el nombre del paciente a PascalCase ASCII sin espacios
    /// (Juan Pérez → JuanPerez).
    static func pacientePascal(_ nombre: String) -> String {
        let sinTildes = nombre.folding(options: .diacriticInsensitive,
                                       locale: Locale(identifier: "en_US_POSIX"))
        // Separamos por cualquier cosa que no sea alfanumérico y capitalizamos.
        let partes = sinTildes.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        let pascal = partes.map { parte -> String in
            let primera = parte.prefix(1).uppercased()
            let resto = parte.dropFirst()
            return primera + resto
        }.joined()
        // Descartamos cualquier residuo no ASCII por seguridad.
        return asciiSeguro(pascal)
    }

    // Formateador fijo yyyy-MM-dd con locale POSIX (independiente de la región).
    private static let formatoFecha: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        return f
    }()
}
