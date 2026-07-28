import Foundation

// Extrae pautas de medicación del texto OCR de una receta (español/Ecuador).
// Soporta dos formatos:
//  A) todo en un renglón: "Amoxicilina 500mg 1 cápsula cada 8 horas por 7 días"
//  B) bloque de cantidades + bloque de pauta:
//        10 Paracetamol            1 paracetamol cada 4h
//        5 Dolgenal        →       1 dolgenal cada día
//        20 Buscapina              1 buscapina cada 8h
//     Sin días, pero con la cantidad se calcula cuántas tomas y cuándo termina.

struct PautaDetectada: Identifiable {
    let id = UUID()
    var nombre: String
    var dosis: String
    var cadaHoras: Int
    var duracionDias: Int   // 0 = indefinido / no detectado
    var dosisTotales: Int   // nº de tomas si vino por cantidad; 0 si no

    /// Renglón vacío para llenar a mano cuando el OCR no detecta nada.
    static var enBlanco: PautaDetectada {
        PautaDetectada(nombre: "", dosis: "1 pastilla", cadaHoras: 8, duracionDias: 0, dosisTotales: 0)
    }
}

enum RecetaParser {

    private static let formas = ["tableta", "tabletas", "comprimido", "comprimidos",
        "cápsula", "capsula", "cápsulas", "capsulas", "pastilla", "pastillas",
        "gota", "gotas", "ml", "cucharada", "cucharadas", "cucharadita", "sobre",
        "sobres", "inhalación", "inhalaciones", "aplicación", "unidad", "unidades"]

    static func parse(_ texto: String) -> [PautaDetectada] {
        let lineas = texto
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // Pasada 1: líneas de "cantidad + nombre" (sin frecuencia ni forma/unidad).
        var cantidades: [(clave: String, qty: Int)] = []
        for linea in lineas {
            guard frecuencia(linea) == nil else { continue }
            if let (qty, nombre) = lineaCantidad(linea) {
                cantidades.append((clave(nombre), qty))
            }
        }

        // Pasada 2: líneas de pauta (con frecuencia).
        var out: [PautaDetectada] = []
        for (i, linea) in lineas.enumerated() {
            guard let cada = frecuencia(linea) else { continue }

            let dur = duracion(linea)
            let porToma = dosisPorToma(linea)
            let dosisTxt = dosis(linea) ?? "\(porToma) \(porToma == 1 ? "pastilla" : "pastillas")"
            var nombre = nombreDeLinea(linea)
            // Si quedó vacío o es solo una forma ("cápsula"), usar la línea anterior.
            if (nombre.count < 3 || esFormaSola(nombre)), i > 0 { nombre = limpiar(lineas[i - 1]) }
            if nombre.count < 3 || esFormaSola(nombre) { nombre = "Medicamento" }

            // Buscar cantidad total por nombre (formato B).
            var dosisTotales = 0
            if dur == 0, let qty = matchCantidad(nombre, en: cantidades) {
                dosisTotales = max(1, qty / max(1, porToma))
            }

            out.append(PautaDetectada(nombre: nombre, dosis: dosisTxt, cadaHoras: cada,
                                      duracionDias: dur, dosisTotales: dosisTotales))
            if out.count >= 10 { break }
        }
        return out
    }

    // "10 Paracetamol" → (10, "Paracetamol"). Rechaza si la palabra es forma/unidad
    // (p.ej. "10 ml") o si hay palabras de frecuencia/duración.
    private static func lineaCantidad(_ s: String) -> (Int, String)? {
        let t = s.lowercased()
        if t.contains("cada") || t.contains("c/") || t.contains("dia") || t.contains("día")
            || t.contains("hora") || t.contains(" vez") || t.contains("veces") { return nil }
        guard let re = try? NSRegularExpression(pattern: "^(\\d{1,3})\\s+([a-záéíóúñ][\\wáéíóúñ/.-]{2,}.*)$", options: [.caseInsensitive]) else { return nil }
        let rango = NSRange(s.startIndex..., in: s)
        guard let m = re.firstMatch(in: s, range: rango),
              let rq = Range(m.range(at: 1), in: s), let rn = Range(m.range(at: 2), in: s),
              let qty = Int(s[rq]) else { return nil }
        let nombre = String(s[rn]).trimmingCharacters(in: .whitespaces)
        let primera = nombre.lowercased().components(separatedBy: " ").first ?? ""
        if formas.contains(primera) { return nil }   // "10 ml" no es cantidad de un fármaco
        return (qty, nombre)
    }

    private static func dosisPorToma(_ s: String) -> Int {
        // Primer entero del renglón (la "1" en "1 paracetamol cada 4h").
        if let n = capturaInt(s, patron: "^\\s*(\\d{1,2})\\b") { return max(1, n) }
        if let n = capturaInt(s.lowercased(), patron: "(\\d{1,2})\\s*(?:\(formas.joined(separator: "|")))") { return max(1, n) }
        return 1
    }

    // "cada 8 horas", "c/8", "3 veces al día", "cada día", "una vez al día".
    private static func frecuencia(_ s: String) -> Int? {
        let t = s.lowercased()
        if let h = capturaInt(t, patron: "cada\\s*(\\d{1,2})\\s*(h|hora|horas)"), h > 0, h <= 24 { return h }
        if let h = capturaInt(t, patron: "c/\\s*(\\d{1,2})"), h > 0, h <= 24 { return h }
        if let veces = capturaInt(t, patron: "(\\d{1,2})\\s*veces\\s*al\\s*d[ií]a"), veces > 0 {
            return max(1, 24 / veces)
        }
        if t.range(of: "cada\\s*(el\\s*)?d[ií]a", options: .regularExpression) != nil { return 24 }
        if t.contains("una vez al d") || t.contains("1 vez al d") || t.contains("cada 24") { return 24 }
        return nil
    }

    private static func duracion(_ s: String) -> Int {
        let t = s.lowercased()
        if let d = capturaInt(t, patron: "(?:por|durante|x)\\s*(\\d{1,3})\\s*d[ií]?a?s?") { return d }
        if let d = capturaInt(t, patron: "(\\d{1,3})\\s*d[ií]as") { return d }
        return 0
    }

    private static func dosis(_ s: String) -> String? {
        let t = s.lowercased()
        let unidades = formas.joined(separator: "|")
        if let m = captura(t, patron: "(\\d+(?:[.,]\\d+)?)\\s*(\(unidades))") {
            return m.trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private static func nombreDeLinea(_ s: String) -> String {
        let cortes = ["cada", "c/", "tomar", "administrar", "una vez", "1 vez", " vez", "veces", "-", "–", ":"]
        let lower = s.lowercased()
        var idxMin = s.endIndex
        for token in cortes {
            if let r = lower.range(of: token), r.lowerBound < idxMin { idxMin = r.lowerBound }
        }
        // Cortar también en la dosis ("1 tableta", "2 cápsulas").
        if let re = try? NSRegularExpression(pattern: "\\d+\\s*(?:\(formas.joined(separator: "|")))", options: [.caseInsensitive]),
           let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
           let r = Range(m.range, in: s), r.lowerBound < idxMin {
            idxMin = r.lowerBound
        }
        let corte = idxMin < s.endIndex ? String(s[s.startIndex..<idxMin]) : s
        return limpiar(corte)
    }

    private static func esFormaSola(_ nombre: String) -> Bool {
        let k = nombre.folding(options: .diacriticInsensitive, locale: .init(identifier: "es")).lowercased()
            .trimmingCharacters(in: .whitespaces)
        let formasNorm = Set(formas.map { $0.folding(options: .diacriticInsensitive, locale: .init(identifier: "es")) })
        return formasNorm.contains(k)
    }

    private static func limpiar(_ s: String) -> String {
        s.trimmingCharacters(in: CharacterSet(charactersIn: " -–•*.:0123456789)("))
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Match de nombres (tolerante a typos del OCR)

    private static func clave(_ nombre: String) -> String {
        let sin = nombre.folding(options: .diacriticInsensitive, locale: .init(identifier: "es"))
            .lowercased()
        let primera = sin.components(separatedBy: CharacterSet(charactersIn: " /-")).first ?? sin
        return primera.filter { $0.isLetter }
    }

    private static func matchCantidad(_ nombre: String, en cantidades: [(clave: String, qty: Int)]) -> Int? {
        let k = clave(nombre)
        guard k.count >= 3 else { return nil }
        for c in cantidades {
            if c.clave == k || c.clave.hasPrefix(k) || k.hasPrefix(c.clave) { return c.qty }
            // Prefijo común de 5+ letras cubre typos ("paracetamo" vs "paracetamol").
            let n = min(k.count, c.clave.count, 6)
            if n >= 5 && k.prefix(n) == c.clave.prefix(n) { return c.qty }
        }
        return nil
    }

    // MARK: - Regex helpers

    private static func captura(_ s: String, patron: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: patron, options: [.caseInsensitive]) else { return nil }
        let rango = NSRange(s.startIndex..., in: s)
        guard let m = re.firstMatch(in: s, range: rango), m.numberOfRanges > 0,
              let r = Range(m.range, in: s) else { return nil }
        return String(s[r])
    }

    private static func capturaInt(_ s: String, patron: String) -> Int? {
        guard let re = try? NSRegularExpression(pattern: patron, options: [.caseInsensitive]) else { return nil }
        let rango = NSRange(s.startIndex..., in: s)
        guard let m = re.firstMatch(in: s, range: rango), m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: s) else { return nil }
        return Int(s[r])
    }
}
