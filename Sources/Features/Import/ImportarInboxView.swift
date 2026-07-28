import SwiftUI
import SwiftData
import UIKit

// Importa lo recibido por la Share Extension (§5.4). El usuario elige a qué
// reclamo van los PDFs/imágenes que llegaron desde Mail, WhatsApp o Safari.

enum ImportInbox {
    /// Convierte cada archivo del inbox en un Documento del reclamo destino.
    @MainActor
    static func importar(_ urls: [URL], a reclamo: Reclamo, patron: String, ctx: ModelContext) {
        var orden = (reclamo.documentos.map(\.orden).max() ?? -1) + 1
        for url in urls {
            let ext = url.pathExtension.lowercased()
            let doc = Documento(tipo: .otro, orden: orden)
            ctx.insert(doc)
            doc.reclamo = reclamo

            if ext == "pdf" {
                let nombre = FileNamer.nombre(documento: doc, patron: patron)
                let destino = FileStore.urlPDF(nombre: nombre)
                if let data = try? Data(contentsOf: url) {
                    try? FileStore.guardar(data, en: destino)
                    doc.rutaPDF = nombre
                    doc.tamanoBytes = FileStore.tamano(destino)
                }
            } else if let data = try? Data(contentsOf: url), let img = UIImage(data: data) {
                // Imagen → una página escaneada → PDF.
                let pagina = PaginaEscaneada(orden: 0)
                pagina.filtro = .documento
                ctx.insert(pagina)
                pagina.documento = doc
                if let jpeg = img.jpegData(compressionQuality: 0.9) {
                    try? FileStore.guardar(jpeg, en: FileStore.urlOriginal(paginaID: pagina.id))
                    pagina.rutaOriginal = "originales/\(pagina.id).jpg"
                }
                doc.paginas = [pagina]
                DocumentoPDF.regenerar(doc, patron: patron, preajuste: .media)
            }

            orden += 1
            AppGroup.eliminar(url)
        }
        MoneyCalc.recalcularMonto(reclamo)
        try? ctx.save()
    }
}

struct ImportarInboxView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettings

    let archivos: [URL]
    @Query(sort: \Reclamo.fechaCreacion, order: .reverse) private var reclamos: [Reclamo]
    @State private var destino: Reclamo?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Llegaron \(archivos.count) archivo(s) para importar.")
                        .font(.callout)
                    ForEach(archivos, id: \.self) { url in
                        Label(url.lastPathComponent, systemImage: url.pathExtension.lowercased() == "pdf" ? "doc.fill" : "photo")
                            .font(.caption).lineLimit(1).truncationMode(.middle)
                    }
                }

                Section("Reclamo destino") {
                    if reclamos.isEmpty {
                        Text("No tienes reclamos. Crea uno y vuelve a compartir los archivos.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Reclamo", selection: $destino) {
                            Text("Selecciona…").tag(Reclamo?.none)
                            ForEach(reclamos) { r in
                                Text("#\(r.numero) — \(r.cobertura?.paciente?.nombreCompleto ?? "Paciente")")
                                    .tag(Reclamo?.some(r))
                            }
                        }
                    }
                }
            }
            .navigationTitle("Importar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Descartar") { descartar() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Importar") { importar() }.disabled(destino == nil)
                }
            }
        }
    }

    private func importar() {
        guard let destino else { return }
        ImportInbox.importar(archivos, a: destino, patron: settings.patronNombres, ctx: ctx)
        dismiss()
    }

    private func descartar() {
        for url in archivos { AppGroup.eliminar(url) }
        dismiss()
    }
}
