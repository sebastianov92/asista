import SwiftUI
import SwiftData
import UIKit
import PDFKit

struct ReclamoDetailView: View {
    @Environment(\.modelContext) private var ctx
    @Bindable var reclamo: Reclamo
    var autoEscanear: Bool = false

    @State private var editarDoc: Documento?
    @State private var nuevoDoc = false
    @State private var mostrarEnvio = false
    @State private var mostrarReembolso = false
    @State private var mostrarChecklist = false
    @State private var mostrarMonto = false
    @State private var mostrarSecundario = false
    @State private var zipItem: URLItem?
    @State private var arranqueHecho = false
    @State private var recetaPautas: [PautaDetectada] = []
    @State private var mostrarRecetaAlarmas = false
    @State private var procesandoReceta = false
    @State private var avisoReceta: String?

    private var docsOrdenados: [Documento] { reclamo.documentos.sorted { $0.orden < $1.orden } }
    private var urlsPDF: [URL] { docsOrdenados.filter { !$0.rutaPDF.isEmpty }.map { FileStore.urlPDF(nombre: $0.rutaPDF) } }

    var body: some View {
        List {
            cabecera
            checklistSection
            formulariosSection
            documentosSection
            if !reclamo.envios.isEmpty { enviosSection }
            reembolsoSection
            accionesSection
        }
        .navigationTitle("Reclamo #\(reclamo.numero)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) { menuEstado }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { mostrarMonto = true } label: { Label("Editar monto reclamado", systemImage: "pencil") }
                    Button { mostrarChecklist = true } label: { Label("Editar checklist", systemImage: "checklist") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .sheet(item: $editarDoc) { doc in
            DocumentEditorView(reclamo: reclamo, documento: doc)
        }
        .sheet(isPresented: $nuevoDoc) {
            DocumentEditorView(reclamo: reclamo, documento: nil)
        }
        .sheet(isPresented: $mostrarEnvio) {
            EnvioView(reclamo: reclamo)
        }
        .sheet(isPresented: $mostrarReembolso) {
            RegistrarReembolsoView(reclamo: reclamo)
        }
        .sheet(isPresented: $mostrarChecklist) {
            ChecklistEditorView(reclamo: reclamo)
        }
        .sheet(isPresented: $mostrarMonto) {
            MontoEditorView(reclamo: reclamo)
        }
        .sheet(isPresented: $mostrarSecundario) {
            CrearSecundarioView(origen: reclamo)
        }
        .sheet(item: $zipItem) { item in
            ActivityView(items: [item.url])
        }
        .sheet(isPresented: $mostrarRecetaAlarmas) {
            if let paciente = reclamo.cobertura?.paciente {
                RecetaAlarmasView(paciente: paciente, documentoRutaPDF: "", pautas: recetaPautas) { }
            }
        }
        .overlay {
            if procesandoReceta {
                ProgressView("Leyendo receta…").padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .alert("Receta", isPresented: .init(get: { avisoReceta != nil }, set: { if !$0 { avisoReceta = nil } })) {
            Button("OK") { avisoReceta = nil }
        } message: { Text(avisoReceta ?? "") }
        .onAppear {
            guard autoEscanear, !arranqueHecho else { return }
            arranqueHecho = true
            nuevoDoc = true
        }
    }

    // MARK: - Cabecera

    private var cabecera: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(reclamo.estado.etiqueta, systemImage: reclamo.estado.simbolo)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(reclamo.estado.color.opacity(0.15), in: Capsule())
                        .foregroundStyle(reclamo.estado.color)
                    Spacer()
                    Text(Formato.fechaISO(reclamo.fechaEvento)).font(.caption).foregroundStyle(.secondary)
                }
                Text(reclamo.pacienteNombre.isEmpty ? "Paciente" : reclamo.pacienteNombre)
                    .font(.title3.bold())
                Text("\(reclamo.polizaNombre) — \(reclamo.aseguradoraNombre)")
                    .font(.subheadline).foregroundStyle(.secondary)
                if reclamo.cobertura?.poliza == nil && !reclamo.polizaSnapshot.isEmpty {
                    Label("Hecho con una póliza que ya no existe.", systemImage: "clock.arrow.circlepath")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                if !reclamo.prestador.isEmpty { LabeledContent("Prestador", value: reclamo.prestador) }
                if !reclamo.diagnostico.isEmpty { LabeledContent("Diagnóstico", value: reclamo.diagnostico) }

                Divider()
                HStack {
                    montoBloque("Reclamado", Formato.montoUSD(reclamo.montoReclamado), .primary)
                    Spacer()
                    if let r = reclamo.montoReembolsado {
                        montoBloque("Reembolsado", Formato.montoUSD(r), .green)
                        Spacer()
                    }
                    montoBloque("Pendiente", Formato.montoUSD(reclamo.pendiente), Tema.acento)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func montoBloque(_ t: String, _ v: String, _ c: Color) -> some View {
        VStack(alignment: .leading) {
            Text(t).font(.caption2).foregroundStyle(.secondary)
            Text(v).font(.callout.weight(.semibold)).foregroundStyle(c)
        }
    }

    // MARK: - Checklist (§10)

    private var checklistSection: some View {
        Section {
            if reclamo.checklist.isEmpty {
                Text("Sin checklist. Toca «Editar» para definir los documentos requeridos.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(reclamo.checklist, id: \.self) { tipo in
                let presente = reclamo.documentos.contains { $0.tipo == tipo }
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Image(systemName: presente ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(presente ? .green : .secondary)
                        Text(tipo.etiqueta)
                        Spacer()
                        if !presente { Text("falta").font(.caption).foregroundStyle(.orange) }
                    }
                    // Aviso de firma: el formulario de la aseguradora se lleva impreso.
                    if tipo == .formularioAseguradora {
                        Label("Requiere firma del médico — llévalo impreso al consultorio.",
                              systemImage: "signature")
                            .font(.caption2).foregroundStyle(.orange)
                    }
                }
            }
        } header: {
            HStack {
                Text("Checklist de documentos")
                Spacer()
                Button("Editar") { mostrarChecklist = true }.font(.caption)
            }
        }
    }

    // MARK: - Formularios de la aseguradora (§3.2)

    private var formularios: [FormularioEnBlanco] {
        reclamo.cobertura?.poliza?.aseguradora?.formulariosEnBlanco ?? []
    }

    @ViewBuilder
    private var formulariosSection: some View {
        if !formularios.isEmpty {
            Section {
                ForEach(formularios) { form in
                    FormularioFila(form: form)
                }
            } header: {
                Text("Formularios de la aseguradora")
            } footer: {
                Text("Imprímelos y llévalos firmados por el médico si el reclamo los requiere.")
            }
        }
    }

    // MARK: - Documentos

    private var documentosSection: some View {
        Section {
            ForEach(docsOrdenados) { doc in
                Button { editarDoc = doc } label: {
                    HStack {
                        Image(systemName: doc.tipo.simbolo).foregroundStyle(Tema.acento).frame(width: 26)
                        VStack(alignment: .leading) {
                            Text(doc.etiqueta)
                            HStack(spacing: 6) {
                                Text("\(doc.paginas.count) pág").font(.caption2)
                                if doc.tamanoBytes > 0 { Text("· \(Formato.peso(doc.tamanoBytes))").font(.caption2) }
                                if let m = doc.monto { Text("· \(Formato.montoUSD(m))").font(.caption2) }
                            }.foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .leading) {
                    if doc.tipo == .receta && !doc.rutaPDF.isEmpty {
                        Button {
                            Task { await generarAlarmas(doc) }
                        } label: { Label("Alarmas", systemImage: "alarm") }
                        .tint(.blue)
                    }
                }
            }
            .onDelete(perform: eliminarDoc)

            Button { nuevoDoc = true } label: {
                Label("Agregar documento", systemImage: "doc.badge.plus")
            }
        } header: {
            Text("Documentos (\(reclamo.documentos.count))")
        }
    }

    // MARK: - Envíos

    private var enviosSection: some View {
        Section("Historial de envíos") {
            ForEach(reclamo.envios.sorted { $0.fecha > $1.fecha }) { envio in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(Formato.fecha(envio.fecha)).font(.caption)
                        Spacer()
                        Text(envio.estado.etiqueta)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(envio.estado == .enviado ? .green : (envio.estado == .fallido ? .red : .orange))
                    }
                    Text(envio.asunto).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    if envio.messageID.isEmpty {
                        Label("Enviado por composer: el hilo puede no encadenarse.",
                              systemImage: "exclamationmark.triangle")
                            .font(.caption2).foregroundStyle(.orange)
                    }
                    if !envio.errorDescripcion.isEmpty {
                        Text(envio.errorDescripcion).font(.caption2).foregroundStyle(.red)
                    }
                }
            }
        }
    }

    // MARK: - Reembolso

    private var reembolsoSection: some View {
        Section {
            Button {
                mostrarReembolso = true
            } label: {
                Label(reclamo.montoReembolsado == nil ? "Registrar reembolso" : "Actualizar reembolso",
                      systemImage: "dollarsign.arrow.circlepath")
            }
        }
    }

    // MARK: - Acciones

    private var accionesSection: some View {
        Section {
            Button {
                mostrarEnvio = true
            } label: {
                Label("Enviar reclamo", systemImage: "paperplane.fill")
            }
            .disabled(urlsPDF.isEmpty)

            if !urlsPDF.isEmpty {
                ShareLink(items: urlsPDF) {
                    Label("Compartir PDFs (WhatsApp, AirDrop…)", systemImage: "square.and.arrow.up")
                }
                Button {
                    imprimir()
                } label: { Label("Imprimir", systemImage: "printer") }

                Button {
                    if let url = try? Exportador.zipReclamo(reclamo) { zipItem = URLItem(url: url) }
                } label: { Label("Exportar como ZIP", systemImage: "doc.zipper") }
            }

            Button {
                mostrarSecundario = true
            } label: {
                Label("Crear reclamo secundario", systemImage: "arrow.triangle.branch")
            }

            if let origen = reclamo.reclamoOrigen {
                NavigationLink {
                    ReclamoDetailView(reclamo: origen)
                } label: {
                    Label("Ver reclamo primario #\(origen.numero)", systemImage: "arrow.uturn.backward")
                }
            }
        }
    }

    // MARK: - Toolbar estado

    private var menuEstado: some View {
        Menu {
            Picker("Estado", selection: $reclamo.estado) {
                ForEach(EstadoReclamo.allCases, id: \.self) { e in
                    Label(e.etiqueta, systemImage: e.simbolo).tag(e)
                }
            }
        } label: { Image(systemName: "flag") }
        .onChange(of: reclamo.estado) { _, _ in try? ctx.save() }
    }

    // MARK: - Ops

    /// Corre OCR sobre el PDF de la receta y ofrece crear las alarmas (§medicación).
    private func generarAlarmas(_ doc: Documento) async {
        guard reclamo.cobertura?.paciente != nil else {
            avisoReceta = "Este reclamo no tiene paciente asignado."
            return
        }
        procesandoReceta = true
        let r = await RecetaOCR.desdePDF(FileStore.urlPDF(nombre: doc.rutaPDF))
        procesandoReceta = false
        // Siempre abrir la confirmación; en blanco si el OCR no detectó nada.
        recetaPautas = r.pautas.isEmpty ? [PautaDetectada.enBlanco] : r.pautas
        mostrarRecetaAlarmas = true
    }

    private func eliminarDoc(_ offsets: IndexSet) {
        for i in offsets {
            let doc = docsOrdenados[i]
            ctx.delete(doc)
        }
        MoneyCalc.recalcularMonto(reclamo)
        try? ctx.save()
    }

    private func imprimir() {
        let ctrl = UIPrintInteractionController.shared
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.jobName = "Reclamo #\(reclamo.numero)"
        ctrl.printInfo = info
        // Combinar los PDFs en uno para imprimir.
        if let data = combinarPDFs(urlsPDF) { ctrl.printingItem = data }
        ctrl.present(animated: true)
    }

    private func combinarPDFs(_ urls: [URL]) -> Data? {
        let doc = PDFDocument()
        var idx = 0
        for url in urls {
            guard let src = PDFDocument(url: url) else { continue }
            for i in 0..<src.pageCount {
                if let page = src.page(at: i) { doc.insert(page, at: idx); idx += 1 }
            }
        }
        return doc.dataRepresentation()
    }
}

// MARK: - Registrar reembolso (§15.2)

struct RegistrarReembolsoView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Bindable var reclamo: Reclamo

    @State private var monto: Decimal = 0
    @State private var fecha = Date()
    @State private var marcarPagado = true
    @State private var ofrecerSecundario = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Monto reembolsado") {
                    TextField("USD", value: $monto, format: .number)
                        .keyboardType(.decimalPad)
                    DatePicker("Fecha del reembolso", selection: $fecha, displayedComponents: .date)
                }
                Section {
                    Toggle("Marcar reclamo como pagado", isOn: $marcarPagado)
                } footer: {
                    if monto < reclamo.montoReclamado && monto > 0 {
                        Text("Reembolso parcial: quedan \(Formato.montoUSD(reclamo.montoReclamado - monto)) sin cubrir. Podrías reclamarlos a una segunda póliza.")
                    }
                }
            }
            .navigationTitle("Reembolso")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Guardar") { guardar() } }
            }
        }
    }

    private func guardar() {
        reclamo.montoReembolsado = monto
        reclamo.fechaReembolso = fecha
        if marcarPagado { reclamo.estado = .pagado }
        else if reclamo.estado == .aprobado { reclamo.estado = .aprobado }
        try? ctx.save()
        dismiss()
    }
}

// MARK: - Editar checklist (§10)

struct ChecklistEditorView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Bindable var reclamo: Reclamo

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Marca los documentos requeridos para este reclamo. A veces un caso concreto no necesita algo.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(TipoDocumento.allCases, id: \.self) { tipo in
                    let incluido = reclamo.checklist.contains(tipo)
                    Button {
                        alternar(tipo)
                    } label: {
                        HStack {
                            Image(systemName: incluido ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(incluido ? Tema.acento : .secondary)
                            Label(tipo.etiqueta, systemImage: tipo.simbolo)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Checklist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { try? ctx.save(); dismiss() } } }
        }
    }

    private func alternar(_ tipo: TipoDocumento) {
        if let i = reclamo.checklist.firstIndex(of: tipo) { reclamo.checklist.remove(at: i) }
        else { reclamo.checklist.append(tipo) }
    }
}

// MARK: - Editar monto reclamado (§7.2 — override manual)

struct MontoEditorView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Bindable var reclamo: Reclamo

    @State private var manual = false
    @State private var monto: Decimal = 0

    private var auto: Decimal { MoneyCalc.montoReclamadoAuto(reclamo) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Fijar monto manualmente", isOn: $manual)
                } footer: {
                    Text(manual
                         ? "El monto no se recalculará automáticamente desde los documentos."
                         : "El monto se suma automáticamente de los documentos facturables: \(Formato.montoUSD(auto)).")
                }
                if manual {
                    Section("Monto reclamado") {
                        HStack {
                            Text("USD")
                            TextField("0.00", value: $monto, format: .number).keyboardType(.decimalPad)
                        }
                    }
                }
            }
            .navigationTitle("Monto reclamado")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Guardar") { guardar() } }
            }
            .onAppear {
                manual = reclamo.montoManual
                monto = reclamo.montoReclamado
            }
        }
    }

    private func guardar() {
        reclamo.montoManual = manual
        if manual { reclamo.montoReclamado = monto }
        else { MoneyCalc.recalcularMonto(reclamo) }
        try? ctx.save()
        dismiss()
    }
}
