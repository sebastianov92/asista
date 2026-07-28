import Foundation

// Resolución de destinatarios (§4, crítico). Cascada:
// 1. Base: override de la Cobertura si existe, si no los de la Póliza.
// 2. Extras puntuales del reclamo → siempre en Cc.
// 3. Copia propia (Bcc) si está activada en ajustes.
// Todos los destinatarios van en UN solo mensaje. Nunca un envío por destinatario.

struct DestinatariosResueltos {
    var to: [String] = []
    var cc: [String] = []
    var bcc: [String] = []

    var vacio: Bool { to.isEmpty && cc.isEmpty && bcc.isEmpty }
    var total: Int { to.count + cc.count + bcc.count }
}

/// Origen de un chip, para mostrarlo en la UI (§4).
enum OrigenDestinatario: String {
    case poliza = "de la póliza"
    case override = "override"
    case agregado = "agregado"
    case copiaPropia = "copia a ti"
}

struct ChipDestinatario: Identifiable {
    var id = UUID()
    var nombre: String
    var email: String
    var tipo: TipoDestinatario
    var origen: OrigenDestinatario
}

enum RecipientResolver {

    /// Resultado plano (listas de emails) para el envío.
    static func resolver(_ reclamo: Reclamo, copiaPropiaEmail: String?) -> DestinatariosResueltos {
        let chips = chips(reclamo, copiaPropiaEmail: copiaPropiaEmail)
        var r = DestinatariosResueltos()
        r.to  = chips.filter { $0.tipo == .to  }.map(\.email).deduplicado()
        r.cc  = chips.filter { $0.tipo == .cc  }.map(\.email).deduplicado()
        r.bcc = chips.filter { $0.tipo == .bcc }.map(\.email).deduplicado()
        return r
    }

    /// Chips con origen para la pantalla de envío (siempre visibles antes de enviar).
    static func chips(_ reclamo: Reclamo, copiaPropiaEmail: String?) -> [ChipDestinatario] {
        guard let cobertura = reclamo.cobertura else { return [] }

        // 1. Base.
        let usaOverride = !cobertura.destinatariosOverride.isEmpty
        let base = usaOverride
            ? cobertura.destinatariosOverride
            : (cobertura.poliza?.destinatarios ?? [])
        let origenBase: OrigenDestinatario = usaOverride ? .override : .poliza

        var chips: [ChipDestinatario] = base
            .filter { $0.activo }
            .map { ChipDestinatario(nombre: $0.nombre, email: $0.email, tipo: $0.tipo, origen: origenBase) }

        // 2. Extras puntuales del reclamo, siempre en Cc.
        for email in reclamo.destinatariosExtra where !email.isEmpty {
            chips.append(ChipDestinatario(nombre: "", email: email, tipo: .cc, origen: .agregado))
        }

        // 3. Copia a sí mismo (Bcc), si está activada (§8.6).
        if let mio = copiaPropiaEmail, !mio.isEmpty {
            chips.append(ChipDestinatario(nombre: "", email: mio, tipo: .bcc, origen: .copiaPropia))
        }

        return chips
    }
}

extension Array where Element == String {
    /// Deduplica emails ignorando mayúsculas/espacios, conservando el primer orden.
    func deduplicado() -> [String] {
        var vistos = Set<String>()
        var out: [String] = []
        for e in self {
            let clave = e.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !clave.isEmpty, !vistos.contains(clave) else { continue }
            vistos.insert(clave)
            out.append(e.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return out
    }
}
