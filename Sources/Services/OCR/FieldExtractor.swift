import Foundation

/// Extractor de campos estructurados sobre el texto OCR de facturas del SRI.
/// Las facturas del SRI (Ecuador) tienen estructura regular (§7.1), así que
/// usamos regex + heurísticas por línea. Todo es defensivo: nunca crashea.
///
/// Regla de oro del monto (§7.1/§7.2):
///   - gana la línea etiquetada TOTAL;
///   - se ignoran SUBTOTAL / IVA / DESCUENTO;
///   - ante empate, gana el valor MÁS GRANDE (el total nunca es menor que sus componentes);
///   - si la confianza es baja, `monto = nil` (pero `montoConfianza` sí se reporta).
enum FieldExtractor {

    static func extraer(de texto: String) -> CamposDetectados {
        var campos = CamposDetectados()
        campos.textoCompleto = texto

        let lineas = texto
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        let textoMayus = texto.uppercased()

        campos.ruc = extraerRUC(texto)
        campos.numeroFactura = primeraCoincidencia(#"\b\d{3}-\d{3}-\d{9}\b"#, en: texto) ?? ""
        campos.fecha = extraerFecha(lineas: lineas, texto: texto)
        campos.autorizacionSRI = primeraCoincidencia(#"\b\d{49}\b|\b\d{37}\b|\b\d{10}\b"#, en: texto) ?? ""
        campos.emisor = extraerEmisor(lineas: lineas, ruc: campos.ruc)

        let (monto, confianza) = extraerMonto(lineas: lineas, textoCompleto: texto)
        campos.montoConfianza = confianza
        // §7.2: por debajo de ~0.4 no autocompletamos el número.
        campos.monto = confianza >= 0.4 ? monto : nil

        campos.tipoSugerido = sugerirTipo(textoMayus: textoMayus, ruc: campos.ruc, tieneTotal: monto != nil)
        campos.medicoSugerido = extraerMedico(lineas: lineas)

        return campos
    }

    // MARK: - RUC

    /// RUC ecuatoriano: 13 dígitos que terminan en 001. Tomamos la primera coincidencia.
    private static func extraerRUC(_ texto: String) -> String {
        let candidatos = todasLasCoincidencias(#"\b\d{13}\b"#, en: texto)
        return candidatos.first(where: { $0.hasSuffix("001") }) ?? ""
    }

    // MARK: - Fecha

    /// Preferimos una fecha en/junto a una línea con "FECHA" o "EMISIÓN/EMISION".
    /// Si no hay, tomamos la primera fecha del texto. Formato dd/MM/yyyy (o dd-MM-yyyy).
    private static func extraerFecha(lineas: [String], texto: String) -> Date? {
        let patron = #"\d{2}[/-]\d{2}[/-]\d{4}"#
        let claves = ["FECHA", "EMISIÓN", "EMISION"]

        // 1) Buscamos en líneas etiquetadas.
        for (i, linea) in lineas.enumerated() {
            let mayus = linea.uppercased()
            guard claves.contains(where: { mayus.contains($0) }) else { continue }
            if let m = primeraCoincidencia(patron, en: linea) {
                if let f = parsearFecha(m) { return f }
            }
            // La fecha puede estar en la línea siguiente al rótulo.
            if i + 1 < lineas.count, let m = primeraCoincidencia(patron, en: lineas[i + 1]) {
                if let f = parsearFecha(m) { return f }
            }
        }

        // 2) Fallback: primera fecha en todo el texto.
        if let m = primeraCoincidencia(patron, en: texto) {
            return parsearFecha(m)
        }
        return nil
    }

    /// Normaliza separadores a "/" y parsea con locale es_EC, formato dd/MM/yyyy.
    private static func parsearFecha(_ crudo: String) -> Date? {
        let normal = crudo.replacingOccurrences(of: "-", with: "/")
        let df = DateFormatter()
        df.locale = Locale(identifier: "es_EC")
        df.dateFormat = "dd/MM/yyyy"
        df.isLenient = false
        return df.date(from: normal)
    }

    // MARK: - Emisor

    /// Emisor: la línea inmediatamente anterior al RUC si existe; si no,
    /// la primera línea no vacía del bloque superior. Corto, una sola línea.
    private static func extraerEmisor(lineas: [String], ruc: String) -> String {
        if !ruc.isEmpty {
            if let idx = lineas.firstIndex(where: { $0.contains(ruc) }) {
                // Buscamos hacia arriba la primera línea con contenido alfabético.
                var j = idx - 1
                while j >= 0 {
                    let l = lineas[j].trimmingCharacters(in: .whitespaces)
                    if pareceNombreEmisor(l) { return acortar(l) }
                    j -= 1
                }
            }
        }
        // Fallback: primeras líneas no vacías del bloque superior.
        if let primera = lineas.first(where: { pareceNombreEmisor($0) }) {
            return acortar(primera)
        }
        return ""
    }

    private static func pareceNombreEmisor(_ linea: String) -> Bool {
        let l = linea.trimmingCharacters(in: .whitespaces)
        guard l.count >= 3 else { return false }
        // Debe tener letras y no ser puramente numérica/etiqueta de rótulo.
        let tieneLetras = l.rangeOfCharacter(from: .letters) != nil
        let esRotulo = ["RUC", "FACTURA", "R.U.C"].contains { l.uppercased().hasPrefix($0) }
        return tieneLetras && !esRotulo
    }

    private static func acortar(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.count > 80 ? String(t.prefix(80)) : t
    }

    // MARK: - Monto

    /// Rótulos que identifican el total. Excluimos explícitamente SUBTOTAL/IVA/DESCUENTO.
    private static let rotulosTotal = ["VALOR TOTAL", "IMPORTE TOTAL", "TOTAL A PAGAR", "TOTAL"]
    private static let rotulosExcluir = ["SUBTOTAL", "SUB TOTAL", "IVA", "DESCUENTO"]

    /// Devuelve (monto, confianza).
    ///   - Alta (~0.9): una línea etiquetada TOTAL dio un número limpio.
    ///   - Media (~0.5): fallback al mayor decimal presente en el texto.
    private static func extraerMonto(lineas: [String], textoCompleto: String) -> (Decimal?, Double) {
        var candidatosTotal: [Decimal] = []

        for linea in lineas {
            let mayus = linea.uppercased()
            // Ignoramos líneas de componentes (subtotal, IVA, descuento).
            if rotulosExcluir.contains(where: { mayus.contains($0) }) { continue }
            // ¿La línea está etiquetada como total?
            guard rotulosTotal.contains(where: { mayus.contains($0) }) else { continue }

            let numeros = numerosEnLinea(linea)
            // Tomamos el ÚLTIMO número de la línea (el valor suele ir al final).
            if let ultimo = numeros.last {
                candidatosTotal.append(ultimo)
            }
        }

        if !candidatosTotal.isEmpty {
            // Ante varios rótulos TOTAL, el total real es el MÁS GRANDE (§7.1).
            let mayor = candidatosTotal.max()!
            return (mayor, 0.9)
        }

        // Fallback: el mayor decimal en todo el texto. Confianza media.
        let todos = numerosEnLinea(textoCompleto)
        if let mayor = todos.max() {
            return (mayor, 0.5)
        }

        // Nada reconocido.
        return (nil, 0.0)
    }

    /// Extrae todos los números decimales de un texto y los parsea a Decimal.
    /// Acepta grupos de miles y decimales en ambos estilos (1.234,56 / 1,234.56 / 120.00).
    private static func numerosEnLinea(_ texto: String) -> [Decimal] {
        // Secuencia de dígitos con separadores de miles/decimales opcionales.
        let patron = #"\d{1,3}(?:[.,]\d{3})*(?:[.,]\d{1,2})?|\d+[.,]\d{1,2}|\d+"#
        return todasLasCoincidencias(patron, en: texto).compactMap { parsearDecimal($0) }
    }

    // MARK: - Tipo sugerido

    /// §7.2: heurística de tipo de documento por palabras clave.
    private static func sugerirTipo(textoMayus: String, ruc: String, tieneTotal: Bool) -> TipoDocumento? {
        if textoMayus.contains("RECETA") { return .receta }
        if textoMayus.contains("ORDEN DE EX") { return .ordenExamenes }
        if textoMayus.contains("RESULTADO") { return .resultadoExamenes }
        if textoMayus.contains("INFORME") { return .informeMedico }
        // Si parece factura (tiene RUC + un TOTAL), la clasificamos como factura médica.
        if !ruc.isEmpty && tieneTotal { return .facturaMedico }
        return nil
    }

    // MARK: - Médico sugerido

    /// Busca un nombre plausible cerca de rótulos DR/DRA/MÉDICO/DOCTOR. Best-effort.
    private static func extraerMedico(lineas: [String]) -> String {
        let claves = ["DR.", "DRA.", "DR ", "DRA ", "MÉDICO", "MEDICO", "DOCTOR", "DOCTORA"]
        for linea in lineas {
            let mayus = linea.uppercased()
            guard claves.contains(where: { mayus.contains($0) }) else { continue }
            if let nombre = capturarNombre(de: linea) { return nombre }
        }
        return ""
    }

    /// Captura una secuencia de palabras alfabéticas (nombre) de la línea, en Title Case.
    private static func capturarNombre(de linea: String) -> String? {
        // Quitamos rótulos comunes antes de capturar.
        var l = linea
        for rotulo in ["DRA.", "DR.", "DRA", "DR", "MÉDICO:", "MEDICO:", "MÉDICO", "MEDICO",
                       "DOCTORA", "DOCTOR", ":"] {
            l = l.replacingOccurrences(of: rotulo, with: " ", options: [.caseInsensitive])
        }
        // Palabras de solo letras (incluye acentos), de 2+ caracteres.
        let palabras = l
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { $0.count >= 2 && $0.rangeOfCharacter(from: .decimalDigits) == nil }
        guard !palabras.isEmpty else { return nil }
        // Tomamos hasta 4 palabras y las pasamos a Title Case.
        let nombre = palabras.prefix(4)
            .map { $0.lowercased().capitalized }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return nombre.isEmpty ? nil : nombre
    }

    // MARK: - Parseo de decimales localizados

    /// Convierte un string numérico localizado a Decimal, manejando ambos estilos
    /// de agrupación (.  y ,). Defensivo: devuelve nil si no puede.
    private static func parsearDecimal(_ crudo: String) -> Decimal? {
        var s = crudo.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }

        let tienePunto = s.contains(".")
        let tieneComa  = s.contains(",")

        if tienePunto && tieneComa {
            // El separador decimal es el que aparece MÁS a la derecha.
            let ultPunto = s.lastIndex(of: ".")!
            let ultComa  = s.lastIndex(of: ",")!
            if ultComa > ultPunto {
                // Estilo europeo/EC: 1.234,56 → miles ".", decimal ",".
                s = s.replacingOccurrences(of: ".", with: "")
                s = s.replacingOccurrences(of: ",", with: ".")
            } else {
                // Estilo US: 1,234.56 → miles ",", decimal ".".
                s = s.replacingOccurrences(of: ",", with: "")
            }
        } else if tieneComa {
            // Solo coma. Si separa exactamente 3 dígitos finales, es miles; si no, decimal.
            let partes = s.components(separatedBy: ",")
            if partes.count == 2 && partes[1].count == 3 && partes[0].count <= 3 {
                // Ambiguo (p.ej. "1,234"): lo tratamos como miles → entero.
                s = s.replacingOccurrences(of: ",", with: "")
            } else {
                s = s.replacingOccurrences(of: ",", with: ".")
            }
        } else if tienePunto {
            // Solo punto. Si separa exactamente 3 dígitos finales y hay más adelante,
            // podría ser miles; pero "120.00" es decimal. Heurística conservadora:
            let partes = s.components(separatedBy: ".")
            if partes.count > 2 {
                // Varios puntos: son separadores de miles → los quitamos todos.
                s = s.replacingOccurrences(of: ".", with: "")
            } else if partes.count == 2 && partes[1].count == 3 && partes[0].count <= 3 {
                // Ambiguo "1.234": lo tratamos como miles → entero.
                s = s.replacingOccurrences(of: ".", with: "")
            }
            // "120.00" o "1234.5" quedan tal cual (decimal válido).
        }

        // Usamos Locale POSIX (punto decimal) para un parseo predecible.
        return Decimal(string: s, locale: Locale(identifier: "en_US_POSIX"))
    }

    // MARK: - Utilidades NSRegularExpression

    private static func primeraCoincidencia(_ patron: String, en texto: String) -> String? {
        return todasLasCoincidencias(patron, en: texto).first
    }

    private static func todasLasCoincidencias(_ patron: String, en texto: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: patron, options: []) else { return [] }
        let rango = NSRange(texto.startIndex..<texto.endIndex, in: texto)
        let matches = regex.matches(in: texto, options: [], range: rango)
        return matches.compactMap { match in
            guard let r = Range(match.range, in: texto) else { return nil }
            return String(texto[r])
        }
    }
}
