import SwiftUI
import SwiftData
import UIKit
import UniformTypeIdentifiers

// Sube una receta SIN reclamo: elegir paciente → escanear/importar/manual →
// OCR → pauta → alarmas.

struct AgregarRecetaView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Paciente.apellidos) private var pacientes: [Paciente]

    @State private var paciente: Paciente?
    @State private var mostrarScanner = false
    @State private var mostrarFotos = false
    @State private var mostrarPDF = false
    @State private var procesando = false

    @State private var pautas: [PautaDetectada] = []
    @State private var rutaPDF = ""
    @State private var mostrarPautas = false
    @State private var mostrarManual = false
    @State private var aviso: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Paciente") {
                    Picker("Paciente", selection: $paciente) {
                        Text("Selecciona…").tag(Paciente?.none)
                        ForEach(pacientes) { p in Text(p.nombreCompleto).tag(Paciente?.some(p)) }
                    }
                }

                Section {
                    Button { mostrarScanner = true } label: { Label("Escanear receta", systemImage: "doc.viewfinder") }
                    Button { mostrarFotos = true } label: { Label("Importar de Fotos", systemImage: "photo") }
                    Button { mostrarPDF = true } label: { Label("Importar PDF", systemImage: "doc") }
                    Button { mostrarManual = true } label: { Label("Agregar manualmente", systemImage: "square.and.pencil") }
                }
                .disabled(paciente == nil)
            }
            .navigationTitle("Nueva receta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } } }
            .overlay { if procesando { ProgressView("Leyendo receta…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
            .onAppear { if paciente == nil, pacientes.count == 1 { paciente = pacientes.first } }
            .fullScreenCover(isPresented: $mostrarScanner) {
                DocumentScannerView { imgs in mostrarScanner = false; Task { await procesarImagenes(imgs) } }
                    onCancel: { mostrarScanner = false }
                    onError: { _ in mostrarScanner = false }
                    .ignoresSafeArea()
            }
            .sheet(isPresented: $mostrarFotos) {
                PhotoImportView { imgs in mostrarFotos = false; Task { await procesarImagenes(imgs) } }
                    onCancel: { mostrarFotos = false }
            }
            .fileImporter(isPresented: $mostrarPDF, allowedContentTypes: [.pdf]) { res in
                if case .success(let url) = res { Task { await procesarPDF(url) } }
            }
            .sheet(isPresented: $mostrarPautas, onDismiss: { dismiss() }) {
                if let p = paciente {
                    RecetaAlarmasView(paciente: p, documentoRutaPDF: rutaPDF, pautas: pautas) { }
                }
            }
            .sheet(isPresented: $mostrarManual, onDismiss: { dismiss() }) {
                if let p = paciente { MedicamentoEditorView(paciente: p) }
            }
            .alert("Receta", isPresented: .init(get: { aviso != nil }, set: { if !$0 { aviso = nil } })) {
                Button("Agregar manual") { aviso = nil; mostrarManual = true }
                Button("Cancelar", role: .cancel) { aviso = nil }
            } message: { Text(aviso ?? "") }
        }
    }

    private func procesarImagenes(_ imgs: [UIImage]) async {
        guard !imgs.isEmpty else { return }
        procesando = true; defer { procesando = false }
        // Guardar un PDF de la receta como referencia.
        let nombre = "Receta-\(UUID().uuidString).pdf"
        let destino = FileStore.urlPDF(nombre: nombre)
        try? PDFBuilder.construir(imagenes: imgs, preajuste: .media, escalaGrises: false, titulo: "Receta", destino: destino)
        rutaPDF = FileManager.default.fileExists(atPath: destino.path) ? nombre : ""

        let r = await RecetaOCR.desdeImagenes(imgs)
        entregar(r)
    }

    private func procesarPDF(_ url: URL) async {
        procesando = true; defer { procesando = false }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let nombre = "Receta-\(UUID().uuidString).pdf"
        let destino = FileStore.urlPDF(nombre: nombre)
        if let data = try? Data(contentsOf: url) { try? FileStore.guardar(data, en: destino) }
        rutaPDF = FileManager.default.fileExists(atPath: destino.path) ? nombre : ""

        let r = await RecetaOCR.desdePDF(destino)
        entregar(r)
    }

    private func entregar(_ r: RecetaOCR.Resultado) {
        // Siempre mostrar la confirmación; en blanco si no se detectó nada.
        pautas = r.pautas.isEmpty ? [PautaDetectada.enBlanco] : r.pautas
        mostrarPautas = true
    }
}
