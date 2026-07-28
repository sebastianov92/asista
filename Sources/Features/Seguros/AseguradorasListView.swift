import SwiftUI
import SwiftData
import UIKit

/// Lista de aseguradoras. Se muestra dentro del `NavigationStack` de `SegurosView`.
struct AseguradorasListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Aseguradora.nombre) private var aseguradoras: [Aseguradora]

    @State private var nueva = false
    @State private var aEditar: Aseguradora?

    var body: some View {
        Group {
            if aseguradoras.isEmpty {
                ContentUnavailableView {
                    Label("Sin aseguradoras", systemImage: "building.2")
                } description: {
                    Text("Agrega tu primera aseguradora")
                } actions: {
                    Button("Agregar aseguradora") { nueva = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    ForEach(aseguradoras) { ase in
                        Button {
                            aEditar = ase
                        } label: {
                            fila(ase)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: eliminar)
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
                .accessibilityLabel("Agregar aseguradora")
            }
        }
        .sheet(isPresented: $nueva) {
            AseguradoraEditorView()
        }
        .sheet(item: $aEditar) { ase in
            AseguradoraEditorView(aseguradora: ase)
        }
    }

    private func fila(_ ase: Aseguradora) -> some View {
        HStack(spacing: 12) {
            swatch(ase)
            VStack(alignment: .leading, spacing: 2) {
                Text(ase.nombre.isEmpty ? "Sin nombre" : ase.nombre)
                    .font(.body.weight(.medium))
                Text("\(ase.polizas.count) póliza\(ase.polizas.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func swatch(_ ase: Aseguradora) -> some View {
        let color = ase.colorHex.flatMap { Color(hex: $0) } ?? Tema.acento
        if let data = ase.logoData, let ui = UIImage(data: data) {
            Image(uiImage: ui)
                .resizable()
                .scaledToFit()
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(color)
                .frame(width: 36, height: 36)
        }
    }

    private func eliminar(_ offsets: IndexSet) {
        for i in offsets { context.delete(aseguradoras[i]) }
        try? context.save()
    }
}
