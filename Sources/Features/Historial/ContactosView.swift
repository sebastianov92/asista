import SwiftUI
import SwiftData

/// Directorio de médicos y prestadores. Raíz navegable (`ContactosView()`).
struct ContactosView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Contacto.nombre) private var contactos: [Contacto]

    @State private var filtro: FiltroContacto = .todos
    @State private var busqueda = ""
    @State private var mostrarEditor = false

    private enum FiltroContacto: String, CaseIterable, Identifiable {
        case medicos, prestadores, todos
        var id: String { rawValue }
        var etiqueta: String {
            switch self {
            case .medicos: return "Médicos"
            case .prestadores: return "Prestadores"
            case .todos: return "Todos"
            }
        }
    }

    private var contactosFiltrados: [Contacto] {
        contactos.filter { c in
            switch filtro {
            case .medicos where c.tipo != .medico: return false
            case .prestadores where c.tipo != .prestador: return false
            default: break
            }
            let q = HistorialTexto.normalizar(busqueda)
            guard !q.isEmpty else { return true }
            return HistorialTexto.normalizar(c.nombre).contains(q)
                || HistorialTexto.normalizar(c.especialidad).contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if contactos.isEmpty {
                    ContentUnavailableView(
                        "Sin contactos",
                        systemImage: "person.crop.circle.badge.plus",
                        description: Text("Agrega médicos y prestadores para reutilizarlos en tus reclamos.")
                    )
                } else {
                    List {
                        Picker("Filtro", selection: $filtro) {
                            ForEach(FiltroContacto.allCases) { f in
                                Text(f.etiqueta).tag(f)
                            }
                        }
                        .pickerStyle(.segmented)
                        .listRowSeparator(.hidden)

                        ForEach(contactosFiltrados) { contacto in
                            NavigationLink {
                                ContactoEditorView(contacto: contacto)
                            } label: {
                                FilaContacto(contacto: contacto)
                            }
                        }
                        .onDelete(perform: eliminar)
                    }
                }
            }
            .navigationTitle("Directorio")
            .searchable(text: $busqueda, prompt: "Buscar por nombre o especialidad")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        mostrarEditor = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $mostrarEditor) {
                ContactoEditorView()
            }
        }
    }

    private func eliminar(_ offsets: IndexSet) {
        let visibles = contactosFiltrados
        for i in offsets {
            context.delete(visibles[i])
        }
        try? context.save()
    }
}

// MARK: - Fila

private struct FilaContacto: View {
    let contacto: Contacto

    private var telUrl: URL? {
        let limpio = contacto.telefono.filter { !$0.isWhitespace }
        guard !limpio.isEmpty else { return nil }
        return URL(string: "tel:\(limpio)")
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: contacto.tipo.simbolo)
                .foregroundStyle(Tema.acento)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(contacto.nombre.isEmpty ? "Sin nombre" : contacto.nombre)
                    .font(.body)
                if !contacto.especialidad.isEmpty {
                    Text(contacto.especialidad)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !contacto.telefono.isEmpty {
                    Text(contacto.telefono)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let telUrl {
                Link(destination: telUrl) {
                    Image(systemName: "phone.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Tema.acento)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Constructor del directorio

enum DirectorioBuilder {
    /// Inserta filas `Contacto` para cada médico/prestador presente en
    /// reclamos/eventos que aún no exista en `existentes`. Devuelve cuántos agregó.
    /// Coincidencia insensible a mayúsculas y tildes; ignora vacíos y duplicados.
    @discardableResult
    static func sincronizar(reclamos: [Reclamo],
                            eventos: [EventoMedico],
                            existentes: [Contacto],
                            ctx: ModelContext) -> Int {
        // Claves ya presentes, por tipo (un médico y un prestador pueden compartir
        // nombre sin considerarse el mismo contacto).
        var clavesMedico = Set<String>()
        var clavesPrestador = Set<String>()
        for c in existentes {
            let k = HistorialTexto.normalizar(c.nombre)
            guard !k.isEmpty else { continue }
            if c.tipo == .medico { clavesMedico.insert(k) } else { clavesPrestador.insert(k) }
        }

        var agregados = 0

        func agregarMedico(_ nombre: String, especialidad: String) {
            let limpio = nombre.trimmingCharacters(in: .whitespacesAndNewlines)
            let k = HistorialTexto.normalizar(limpio)
            guard !k.isEmpty, !clavesMedico.contains(k) else { return }
            clavesMedico.insert(k)
            let c = Contacto(nombre: limpio, tipo: .medico)
            c.especialidad = especialidad.trimmingCharacters(in: .whitespacesAndNewlines)
            ctx.insert(c)
            agregados += 1
        }

        func agregarPrestador(_ nombre: String) {
            let limpio = nombre.trimmingCharacters(in: .whitespacesAndNewlines)
            let k = HistorialTexto.normalizar(limpio)
            guard !k.isEmpty, !clavesPrestador.contains(k) else { return }
            clavesPrestador.insert(k)
            let c = Contacto(nombre: limpio, tipo: .prestador)
            ctx.insert(c)
            agregados += 1
        }

        for r in reclamos {
            agregarMedico(r.medico, especialidad: "")
            agregarPrestador(r.prestador)
        }
        for e in eventos {
            agregarMedico(e.medico, especialidad: e.especialidad)
        }

        if agregados > 0 { try? ctx.save() }
        return agregados
    }
}
