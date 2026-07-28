import SwiftUI
import SwiftData

/// Lista de pólizas agrupadas por aseguradora. Dentro del `NavigationStack` de `SegurosView`.
struct PolizasListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\Poliza.prioridad), SortDescriptor(\Poliza.alias)])
    private var polizas: [Poliza]

    @State private var nueva = false
    @State private var aEditar: Poliza?

    var body: some View {
        Group {
            if polizas.isEmpty {
                ContentUnavailableView {
                    Label("Sin pólizas", systemImage: "doc.text")
                } description: {
                    Text("Agrega tu primera póliza")
                } actions: {
                    Button("Agregar póliza") { nueva = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    ForEach(grupos, id: \.nombre) { grupo in
                        Section(grupo.nombre) {
                            ForEach(grupo.polizas) { pol in
                                Button {
                                    aEditar = pol
                                } label: {
                                    fila(pol)
                                }
                                .buttonStyle(.plain)
                            }
                            .onDelete { borrar($0, en: grupo.polizas) }
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    nueva = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Agregar póliza")
            }
        }
        .sheet(isPresented: $nueva) {
            PolizaEditorView()
        }
        .sheet(item: $aEditar) { pol in
            PolizaEditorView(poliza: pol)
        }
    }

    private func fila(_ pol: Poliza) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(pol.nombreVisible.isEmpty ? "Sin nombre" : pol.nombreVisible)
                    .font(.body.weight(.medium))
                Spacer()
                Text("Prioridad \(pol.prioridad)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if !pol.numero.isEmpty {
                Text("N.º \(pol.numero)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let vigencia = textoVigencia(pol) {
                Text(vigencia)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func textoVigencia(_ pol: Poliza) -> String? {
        switch (pol.vigenciaDesde, pol.vigenciaHasta) {
        case let (desde?, hasta?):
            return "Vigencia: \(Formato.fechaISO(desde)) → \(Formato.fechaISO(hasta))"
        case let (desde?, nil):
            return "Desde: \(Formato.fechaISO(desde))"
        case let (nil, hasta?):
            return "Hasta: \(Formato.fechaISO(hasta))"
        default:
            return nil
        }
    }

    // MARK: - Agrupado

    private struct Grupo { let nombre: String; let polizas: [Poliza] }

    private var grupos: [Grupo] {
        let dict = Dictionary(grouping: polizas) { $0.aseguradora?.nombre ?? "Sin aseguradora" }
        return dict.keys.sorted().map { Grupo(nombre: $0, polizas: dict[$0] ?? []) }
    }

    private func borrar(_ offsets: IndexSet, en lista: [Poliza]) {
        for i in offsets { context.delete(lista[i]) }
        try? context.save()
    }
}
