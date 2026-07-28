import Foundation

// Plantillas de correo (§9). Cascada de resolución, de mayor a menor precedencia:
// override del reclamo → póliza → aseguradora → global por defecto.
// Más el reemplazo de tokens {{...}} con datos reales del reclamo.

enum NivelPlantilla: String {
    case reclamo = "override del reclamo"
    case poliza = "de la póliza"
    case aseguradora = "de la aseguradora"
    case global = "global por defecto"
}

struct PlantillaResuelta {
    var asunto: String
    var cuerpo: String
    var nivel: NivelPlantilla
}

enum TemplateEngine {

    static let asuntoPorDefecto =
        "Reclamo médico — {{paciente}} — {{fecha_evento}} — Póliza {{poliza}}"

    static let cuerpoPorDefecto = """
    Estimados,

    Adjunto la documentación para el reclamo médico del siguiente paciente:

    Paciente: {{paciente}} (C.I. {{paciente_cedula}})
    Póliza: {{poliza}} — {{aseguradora}}
    Certificado: {{certificado}}
    Fecha de atención: {{fecha_evento}}
    Prestador: {{prestador}}
    Monto total: USD {{monto_total}}

    Documentos adjuntos ({{cantidad_documentos}}):
    {{lista_documentos}}

    Quedo atento a cualquier información adicional que requieran.

    Saludos cordiales,
    """

    /// Devuelve la plantilla base (sin tokens expandidos) según la cascada,
    /// incluyendo el nivel para que la UI lo indique.
    static func resolverBase(_ reclamo: Reclamo, plantillaGlobal: PlantillaCorreo?) -> PlantillaResuelta {
        let poliza = reclamo.cobertura?.poliza
        // Asunto y cuerpo se resuelven por separado para permitir overrides parciales.
        let base = poliza?.plantilla ?? poliza?.aseguradora?.plantilla ?? plantillaGlobal

        let nivel: NivelPlantilla
        if reclamo.asuntoOverride != nil || reclamo.cuerpoOverride != nil {
            nivel = .reclamo
        } else if poliza?.plantilla != nil {
            nivel = .poliza
        } else if poliza?.aseguradora?.plantilla != nil {
            nivel = .aseguradora
        } else {
            nivel = .global
        }

        let asunto = reclamo.asuntoOverride ?? base?.asunto.nilSiVacio ?? asuntoPorDefecto
        let cuerpo = reclamo.cuerpoOverride ?? base?.cuerpo.nilSiVacio ?? cuerpoPorDefecto
        return PlantillaResuelta(asunto: asunto, cuerpo: cuerpo, nivel: nivel)
    }

    /// Plantilla final con tokens ya reemplazados por datos del reclamo.
    static func render(_ reclamo: Reclamo, plantillaGlobal: PlantillaCorreo?) -> PlantillaResuelta {
        let base = resolverBase(reclamo, plantillaGlobal: plantillaGlobal)
        let tokens = tokens(para: reclamo)
        return PlantillaResuelta(
            asunto: expandir(base.asunto, tokens: tokens),
            cuerpo: expandir(base.cuerpo, tokens: tokens),
            nivel: base.nivel
        )
    }

    /// Expande una cadena arbitraria (para vista previa en vivo del editor).
    static func expandir(_ texto: String, tokens: [String: String]) -> String {
        var out = texto
        for (k, v) in tokens {
            out = out.replacingOccurrences(of: "{{\(k)}}", with: v)
        }
        return out
    }

    static func tokens(para reclamo: Reclamo) -> [String: String] {
        let cob = reclamo.cobertura
        let pac = cob?.paciente
        let pol = cob?.poliza
        let ase = pol?.aseguradora

        let df = DateFormatter()
        df.locale = Locale(identifier: "es_EC")
        df.dateFormat = "yyyy-MM-dd"

        let facturables = reclamo.documentos.filter { $0.tipo.esFacturable }
        _ = facturables

        return [
            "paciente": pac?.nombreCompleto ?? "",
            "paciente_cedula": pac?.cedula ?? "",
            "parentesco": pac?.parentesco.etiqueta ?? "",
            "aseguradora": ase?.nombre ?? "",
            "poliza": pol?.nombreVisible ?? "",
            "certificado": cob?.numeroCertificado ?? "",
            "fecha_evento": df.string(from: reclamo.fechaEvento),
            "fecha_hoy": df.string(from: Date()),
            "diagnostico": reclamo.diagnostico,
            "medico": reclamo.medico,
            "prestador": reclamo.prestador,
            "monto_total": Formato.monto(reclamo.montoReclamado),
            "numero_reclamo": String(reclamo.numero),
            "lista_documentos": listaDocumentos(reclamo),
            "cantidad_documentos": String(reclamo.documentos.count),
        ]
    }

    /// Lista con viñetas de adjuntos con su tipo y monto cuando aplique (§9).
    private static func listaDocumentos(_ reclamo: Reclamo) -> String {
        let ordenados = reclamo.documentos.sorted { $0.orden < $1.orden }
        return ordenados.map { doc in
            if let m = doc.monto, doc.tipo.esFacturable {
                return "• \(doc.etiqueta) — USD \(Formato.monto(m))"
            }
            return "• \(doc.etiqueta)"
        }.joined(separator: "\n")
    }

    /// Tokens disponibles, para el menú de inserción del editor.
    static let tokensDisponibles: [String] = [
        "paciente", "paciente_cedula", "parentesco", "aseguradora", "poliza",
        "certificado", "fecha_evento", "fecha_hoy", "diagnostico", "medico",
        "prestador", "monto_total", "numero_reclamo", "lista_documentos",
        "cantidad_documentos",
    ]
}

private extension String {
    var nilSiVacio: String? { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self }
}
