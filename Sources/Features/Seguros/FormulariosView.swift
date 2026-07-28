import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit
import PDFKit

// Formularios en blanco por aseguradora (§3.2). PDFs que la aseguradora exige;
// se importan una vez y se imprimen para llevarlos firmados al médico.

enum FormularioStore {
    static var dir: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Formularios", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }
    static func url(_ nombreArchivo: String) -> URL { dir.appendingPathComponent(nombreArchivo) }

    /// Copia un PDF importado al almacenamiento de la app. Devuelve el nombre relativo.
    static func importar(desde origen: URL) throws -> String {
        let necesitaScope = origen.startAccessingSecurityScopedResource()
        defer { if necesitaScope { origen.stopAccessingSecurityScopedResource() } }
        let nombre = "\(UUID().uuidString).pdf"
        let destino = url(nombre)
        let data = try Data(contentsOf: origen)
        try data.write(to: destino, options: .completeFileProtection)
        return nombre
    }
}

// Hub: elegir aseguradora.
struct FormulariosHubView: View {
    @Query(sort: \Aseguradora.nombre) private var aseguradoras: [Aseguradora]

    var body: some View {
        List {
            if aseguradoras.isEmpty {
                Text("Aún no hay aseguradoras.").foregroundStyle(.secondary)
            }
            ForEach(aseguradoras) { ase in
                NavigationLink {
                    FormulariosView(aseguradora: ase)
                } label: {
                    HStack {
                        Text(ase.nombre)
                        Spacer()
                        Text("\(ase.formulariosEnBlanco.count)").foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Formularios")
    }
}

struct FormulariosView: View {
    @Environment(\.modelContext) private var ctx
    @Bindable var aseguradora: Aseguradora
    @State private var importando = false
    @State private var pendiente: URL?
    @State private var nombreNuevo = ""
    @State private var firmaNuevo = true
    @State private var mostrarNombrar = false

    var body: some View {
        List {
            if aseguradora.formulariosEnBlanco.isEmpty {
                Text("Importa el PDF del formulario que exige esta aseguradora.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(aseguradora.formulariosEnBlanco) { form in
                FormularioFila(form: form)
            }
            .onDelete(perform: eliminar)

            Button {
                importando = true
            } label: { Label("Importar formulario (PDF)", systemImage: "doc.badge.plus") }
        }
        .navigationTitle(aseguradora.nombre)
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $importando, allowedContentTypes: [.pdf]) { resultado in
            if case .success(let url) = resultado {
                do {
                    let nombreArchivo = try FormularioStore.importar(desde: url)
                    pendiente = FormularioStore.url(nombreArchivo)
                    nombreNuevo = url.deletingPathExtension().lastPathComponent
                    firmaNuevo = true
                    mostrarNombrar = true
                } catch { }
            }
        }
        .alert("Nombre del formulario", isPresented: $mostrarNombrar) {
            TextField("Nombre", text: $nombreNuevo)
            Toggle("Requiere firma del médico", isOn: $firmaNuevo)
            Button("Guardar") { guardarPendiente() }
            Button("Cancelar", role: .cancel) { descartarPendiente() }
        }
    }

    private func guardarPendiente() {
        guard let url = pendiente else { return }
        let form = FormularioEnBlanco(nombre: nombreNuevo, rutaArchivo: url.lastPathComponent)
        form.requiereFirmaMedico = firmaNuevo
        ctx.insert(form)
        aseguradora.formulariosEnBlanco.append(form)
        try? ctx.save()
        pendiente = nil
    }

    private func descartarPendiente() {
        if let url = pendiente { try? FileManager.default.removeItem(at: url) }
        pendiente = nil
    }

    private func eliminar(_ offsets: IndexSet) {
        for i in offsets {
            let form = aseguradora.formulariosEnBlanco[i]
            try? FileManager.default.removeItem(at: FormularioStore.url(form.rutaArchivo))
            ctx.delete(form)
        }
        try? ctx.save()
    }
}

struct FormularioFila: View {
    let form: FormularioEnBlanco
    private var url: URL { FormularioStore.url(form.rutaArchivo) }

    var body: some View {
        HStack {
            Image(systemName: "doc.text").foregroundStyle(Tema.acento)
            VStack(alignment: .leading, spacing: 2) {
                Text(form.nombre.isEmpty ? "Formulario" : form.nombre)
                if form.requiereFirmaMedico {
                    Label("Requiere firma del médico", systemImage: "signature")
                        .font(.caption2).foregroundStyle(.orange)
                }
            }
            Spacer()
            if FileManager.default.fileExists(atPath: url.path) {
                ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                Button { imprimir() } label: { Image(systemName: "printer") }
            }
        }
        .buttonStyle(.borderless)
    }

    private func imprimir() {
        guard let data = try? Data(contentsOf: url) else { return }
        let ctrl = UIPrintInteractionController.shared
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.jobName = form.nombre
        ctrl.printInfo = info
        ctrl.printingItem = data
        ctrl.present(animated: true)
    }
}
