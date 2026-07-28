import SwiftUI
import SwiftData

/// Raíz de la pestaña Pacientes. Lista, búsqueda y alta de pacientes.
struct PacientesListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Paciente.apellidos) private var pacientes: [Paciente]

    @State private var busqueda: String = ""
    @State private var mostrandoNuevo = false
    @State private var aBorrar: Paciente?

    var body: some View {
        NavigationStack {
            Group {
                if pacientes.isEmpty {
                    estadoVacio
                } else {
                    lista
                }
            }
            .navigationTitle("Pacientes")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        mostrandoNuevo = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Agregar paciente")
                }
            }
            .sheet(isPresented: $mostrandoNuevo) {
                PacienteEditorView()
            }
            .alert("¿Eliminar paciente?", isPresented: .init(
                get: { aBorrar != nil }, set: { if !$0 { aBorrar = nil } }
            ), presenting: aBorrar) { p in
                Button("Eliminar todo", role: .destructive) { borrarCompleto(p) }
                Button("Cancelar", role: .cancel) { aBorrar = nil }
            } message: { p in
                Text("Se eliminará a \(p.nombreCompleto) y TODO su historial: reclamos, documentos, eventos, coberturas y medicación. No se puede deshacer.")
            }
        }
    }

    private var lista: some View {
        List {
            ForEach(filtrados) { paciente in
                NavigationLink {
                    PacienteDetailView(paciente: paciente)
                } label: {
                    fila(paciente)
                }
            }
            .onDelete(perform: eliminar)
        }
        .searchable(text: $busqueda, prompt: "Buscar por nombre o cédula")
    }

    private func fila(_ p: Paciente) -> some View {
        HStack(spacing: 12) {
            InicialesAvatar(nombre: p.nombreCompleto, fotoData: p.fotoData, lado: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(p.nombreCompleto.isEmpty ? "Sin nombre" : p.nombreCompleto)
                    .font(.body.weight(.medium))
                HStack(spacing: 6) {
                    Text(p.parentesco.etiqueta)
                    if let edad = p.edad {
                        Text("· \(edad) años")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var estadoVacio: some View {
        ContentUnavailableView {
            Label("Sin pacientes", systemImage: "person.crop.circle.badge.plus")
        } description: {
            Text("Agrega tu primer paciente")
        } actions: {
            Button("Agregar paciente") { mostrandoNuevo = true }
                .buttonStyle(.borderedProminent)
        }
    }

    private var filtrados: [Paciente] {
        let q = busqueda.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return pacientes }
        return pacientes.filter {
            $0.nombreCompleto.lowercased().contains(q) ||
            $0.cedula.lowercased().contains(q)
        }
    }

    private func eliminar(_ offsets: IndexSet) {
        // Confirmar antes de borrar (arrastra todo el historial).
        if let i = offsets.first { aBorrar = filtrados[i] }
    }

    /// Borra al paciente y TODO su historial médico, incluidos los reclamos
    /// (que no se eliminan en cascada porque solo referencian la cobertura).
    private func borrarCompleto(_ paciente: Paciente) {
        let pid = paciente.id
        let reclamos = (try? context.fetch(FetchDescriptor<Reclamo>())) ?? []
        for r in reclamos where r.cobertura?.paciente?.id == pid {
            context.delete(r)
        }
        // Cascade borra coberturas, eventos y medicamentos del paciente.
        context.delete(paciente)
        try? context.save()
        aBorrar = nil
    }
}
