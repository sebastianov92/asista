import SwiftUI
import SwiftData

// MARK: - Helpers de texto compartidos por el módulo Historial

/// Normalización de texto insensible a mayúsculas y a tildes, para comparar y
/// deduplicar nombres de médicos/especialidades/prestadores.
enum HistorialTexto {
    /// Devuelve la versión plegada (sin tildes, minúsculas, sin espacios sobrantes).
    static func normalizar(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive],
                     locale: Locale(identifier: "es_EC"))
    }

    /// Dos cadenas son "iguales" si su forma normalizada coincide.
    static func iguales(_ a: String, _ b: String) -> Bool {
        normalizar(a) == normalizar(b)
    }

    /// Deduplica una lista conservando el primer texto original, ignorando vacíos.
    static func distintos(_ valores: [String]) -> [String] {
        var vistos = Set<String>()
        var salida: [String] = []
        for v in valores {
            let limpio = v.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !limpio.isEmpty else { continue }
            let clave = normalizar(limpio)
            if !vistos.contains(clave) {
                vistos.insert(clave)
                salida.append(limpio)
            }
        }
        return salida
    }
}

// MARK: - AutocompleteField

/// Campo de texto reutilizable con sugerencias. Muestra hasta ~5 sugerencias
/// tocables (coincidencia por "contiene", sin tildes ni mayúsculas) cuando el
/// texto no está vacío. Pensado para usarse dentro de un `Form`.
struct AutocompleteField: View {
    let titulo: String
    @Binding var texto: String
    let sugerencias: [String]   // candidatos; los provee quien lo usa

    private var coincidencias: [String] {
        let consulta = HistorialTexto.normalizar(texto)
        guard !consulta.isEmpty else { return [] }
        let distintas = HistorialTexto.distintos(sugerencias)
        return distintas.filter { sug in
            let n = HistorialTexto.normalizar(sug)
            // Contiene la consulta pero no es exactamente igual (ya escrito).
            return n.contains(consulta) && n != consulta
        }
        .prefix(5)
        .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(titulo, text: $texto)
                .textInputAutocapitalization(.words)

            if !coincidencias.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(coincidencias, id: \.self) { sug in
                            Button {
                                texto = sug
                            } label: {
                                Text(sug)
                                    .font(.footnote)
                                    .lineLimit(1)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Tema.acento.opacity(0.12))
                                    .foregroundStyle(Tema.acento)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}
