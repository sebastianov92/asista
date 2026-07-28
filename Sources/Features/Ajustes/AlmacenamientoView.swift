import SwiftUI
import SwiftData

// Uso de almacenamiento y purga de originales (§5.4).

struct AlmacenamientoView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var reclamos: [Reclamo]

    @State private var diasPurga = 30
    @State private var resultadoPurga: String?

    private var pesoPDFs: Int {
        reclamos.flatMap(\.documentos).reduce(0) { $0 + $1.tamanoBytes }
    }
    private var pesoOriginales: Int {
        reclamos.flatMap(\.documentos).flatMap(\.paginas)
            .reduce(0) { $0 + FileStore.tamano(FileStore.urlOriginal(paginaID: $1.id)) }
    }

    var body: some View {
        Form {
            Section("Uso") {
                LabeledContent("PDFs finales", value: Formato.peso(pesoPDFs))
                LabeledContent("Originales de escaneo", value: Formato.peso(pesoOriginales))
                LabeledContent("Total", value: Formato.peso(pesoPDFs + pesoOriginales))
            }
            Section {
                Stepper("Más antiguos que \(diasPurga) días", value: $diasPurga, in: 7...180, step: 7)
                Button(role: .destructive) {
                    purgar()
                } label: {
                    Label("Liberar espacio (borrar originales)", systemImage: "trash")
                }
                if let r = resultadoPurga {
                    Text(r).font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text("Purga de originales")
            } footer: {
                Text("Elimina las imágenes originales de reclamos ya pagados o rechazados. Los PDFs finales se conservan intactos.")
            }
        }
        .navigationTitle("Almacenamiento")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func purgar() {
        var liberado = 0
        var cuenta = 0
        for reclamo in reclamos where reclamo.estado.esTerminal {
            let ref = reclamo.fechaReembolso ?? reclamo.fechaCreacion
            guard Formato.diasDesde(ref) >= diasPurga else { continue }
            for pagina in reclamo.documentos.flatMap(\.paginas) {
                let url = FileStore.urlOriginal(paginaID: pagina.id)
                let t = FileStore.tamano(url)
                if t > 0 {
                    try? FileManager.default.removeItem(at: url)
                    pagina.rutaOriginal = ""
                    liberado += t
                    cuenta += 1
                }
            }
        }
        try? ctx.save()
        resultadoPurga = cuenta == 0
            ? "No había originales que purgar."
            : "Se liberaron \(Formato.peso(liberado)) (\(cuenta) imágenes)."
    }
}
