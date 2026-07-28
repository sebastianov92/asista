import Foundation

// Motor de búsqueda global (§11). Lógica pura, sin SwiftUI, para poder
// probarla y reutilizarla. Resuelve sobre listas ya cargadas por @Query.

/// Resultados agrupados de una búsqueda.
struct ResultadosBusqueda {
    var reclamos: [Reclamo] = []
    var pacientes: [Paciente] = []
    var eventos: [EventoMedico] = []
    var documentos: [Documento] = []   // coincidencia en OCR/emisor/ruc/numeroFactura

    var vacio: Bool {
        reclamos.isEmpty && pacientes.isEmpty && eventos.isEmpty && documentos.isEmpty
    }
}

enum BusquedaEngine {

    /// Tope por lista para mantener la interfaz responsiva (los OCR pueden ser grandes).
    private static let tope = 50

    private static let localeES = Locale(identifier: "es_EC")

    /// Normaliza un texto para comparar sin acentos ni mayúsculas.
    private static func normalizar(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: localeES)
    }

    /// Parte la consulta en palabras normalizadas y no vacías.
    private static func palabras(_ q: String) -> [String] {
        normalizar(q)
            .split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    /// ¿Aparece `termino` en alguno de los campos (ya se normaliza aquí)?
    private static func contiene(_ campos: [String], _ termino: String) -> Bool {
        campos.contains { normalizar($0).contains(termino) }
    }

    // MARK: - Coincidencias por tipo

    private static func campos(_ r: Reclamo) -> [String] {
        [
            r.cobertura?.paciente?.nombreCompleto ?? "",
            r.diagnostico, r.prestador, r.medico, r.codigoCIE10, r.notas,
            "#\(r.numero)", "\(r.numero)",
        ]
    }

    private static func campos(_ p: Paciente) -> [String] {
        [p.nombreCompleto, p.cedula]
    }

    private static func campos(_ e: EventoMedico) -> [String] {
        [e.titulo, e.descripcion, e.medico, e.especialidad, e.diagnostico]
    }

    private static func campos(_ d: Documento) -> [String] {
        [d.textoOCR, d.emisor, d.ruc, d.numeroFactura, d.tipoPersonalizado]
    }

    /// Todas las palabras deben coincidir en algún campo (semántica AND).
    private static func coincideTodo(_ campos: [String], _ terminos: [String]) -> Bool {
        terminos.allSatisfy { contiene(campos, $0) }
    }

    // MARK: - API

    static func buscar(
        _ q: String,
        reclamos: [Reclamo],
        pacientes: [Paciente],
        eventos: [EventoMedico],
        documentos: [Documento]
    ) -> ResultadosBusqueda {
        let terminos = palabras(q)
        guard !terminos.isEmpty else { return ResultadosBusqueda() }

        var res = ResultadosBusqueda()

        res.reclamos = reclamos
            .filter { coincideTodo(campos($0), terminos) }
            .sorted { $0.fechaEvento > $1.fechaEvento }
            .prefix(tope)
            .map { $0 }

        res.pacientes = pacientes
            .filter { coincideTodo(campos($0), terminos) }
            .prefix(tope)
            .map { $0 }

        res.eventos = eventos
            .filter { coincideTodo(campos($0), terminos) }
            .sorted { $0.fecha > $1.fecha }
            .prefix(tope)
            .map { $0 }

        res.documentos = documentos
            .filter { coincideTodo(campos($0), terminos) }
            .prefix(tope)
            .map { $0 }

        return res
    }

    /// Extracto de ~60 caracteres alrededor de la primera coincidencia de `termino`
    /// en `texto`, para mostrar el contexto del OCR. Devuelve "" si no hay coincidencia.
    static func extracto(de texto: String, termino: String, radio: Int = 40) -> String {
        let terminoNorm = normalizar(termino)
            .split(whereSeparator: { $0 == " " })
            .map(String.init)
            .first ?? ""
        guard !terminoNorm.isEmpty, !texto.isEmpty else { return "" }

        let textoNorm = normalizar(texto)
        guard let rangoNorm = textoNorm.range(of: terminoNorm) else { return "" }

        // El folding conserva la longitud (misma cantidad de caracteres), así que
        // podemos mapear posiciones por distancia de caracteres al texto original.
        let inicioOffset = textoNorm.distance(from: textoNorm.startIndex, to: rangoNorm.lowerBound)
        let finOffset = textoNorm.distance(from: textoNorm.startIndex, to: rangoNorm.upperBound)

        let chars = Array(texto)
        let desde = max(0, inicioOffset - radio)
        let hasta = min(chars.count, finOffset + radio)

        var fragmento = String(chars[desde..<hasta])
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)

        if desde > 0 { fragmento = "…" + fragmento }
        if hasta < chars.count { fragmento += "…" }
        return fragmento
    }
}
