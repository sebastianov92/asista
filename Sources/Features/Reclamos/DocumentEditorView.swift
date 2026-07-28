import SwiftUI
import SwiftData
import UIKit

// Editor de documento (§5.3): escanear, filtros, rotar, reordenar, eliminar,
// elegir tipo, y generar el PDF final. OCR es Fase 2.

struct DocumentEditorView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    let reclamo: Reclamo
    /// Documento existente a editar, o nil para crear uno nuevo.
    @State var documento: Documento?
    /// Abrir la cámara al aparecer (flujo nuevo reclamo).
    var autoEscanear: Bool = false

    @EnvironmentObject private var settings: AppSettings

    @State private var tipo: TipoDocumento = .receta
    @State private var tipoPersonalizado = ""
    @State private var paginas: [PaginaEscaneada] = []
    @State private var mostrarScanner = false
    @State private var mostrarFotos = false
    @State private var generando = false
    @State private var error: String?
    /// Página que se está re-escaneando (reemplazo).
    @State private var reescaneandoOrden: Int?
    @State private var ocrCampos: CamposDetectados?
    @State private var mostrarOCR = false
    @State private var recetaPautas: [PautaDetectada] = []
    @State private var mostrarReceta = false

    private var puedeGuardar: Bool { !paginas.isEmpty }

    var body: some View {
        NavigationStack {
            List {
                Section("Tipo de documento") {
                    Picker("Tipo", selection: $tipo) {
                        ForEach(TipoDocumento.allCases, id: \.self) { t in
                            Label(t.etiqueta, systemImage: t.simbolo).tag(t)
                        }
                    }
                    if tipo == .otro {
                        TextField("Nombre del documento", text: $tipoPersonalizado)
                    }
                }

                Section {
                    if paginas.isEmpty {
                        Text("Sin páginas. Escanea o importa.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(paginas.sorted { $0.orden < $1.orden }) { pagina in
                            PaginaFila(pagina: pagina) {
                                rotar(pagina)
                            } cambiarFiltro: { f in
                                pagina.filtro = f
                            } reescanear: {
                                reescaneandoOrden = pagina.orden
                                mostrarScanner = true
                            }
                        }
                        .onDelete(perform: eliminar)
                        .onMove(perform: mover)
                    }
                } header: {
                    HStack {
                        Text("Páginas (\(paginas.count))")
                        Spacer()
                        Menu {
                            ForEach(FiltroEscaneo.allCases, id: \.self) { f in
                                Button(f.etiqueta) { aplicarFiltroATodas(f) }
                            }
                        } label: { Text("Filtro a todas").font(.caption) }
                    }
                }

                Section {
                    Button {
                        reescaneandoOrden = nil
                        mostrarScanner = true
                    } label: { Label("Escanear páginas", systemImage: "doc.viewfinder") }
                    Button {
                        mostrarFotos = true
                    } label: { Label("Importar de Fotos", systemImage: "photo.on.rectangle") }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle(documento == nil ? "Nuevo documento" : "Editar documento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { Task { await guardar() } }
                        .disabled(!puedeGuardar || generando)
                }
            }
            .overlay {
                if generando { ProgressView("Generando PDF…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) }
            }
            .fullScreenCover(isPresented: $mostrarScanner) {
                DocumentScannerView { imagenes in
                    mostrarScanner = false
                    recibirEscaneo(imagenes)
                } onCancel: {
                    mostrarScanner = false
                } onError: { e in
                    mostrarScanner = false
                    error = e.localizedDescription
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $mostrarFotos) {
                PhotoImportView { imagenes in
                    mostrarFotos = false
                    recibirEscaneo(imagenes)
                } onCancel: { mostrarFotos = false }
            }
            .sheet(isPresented: $mostrarOCR, onDismiss: { dismiss() }) {
                if let campos = ocrCampos, let doc = documento {
                    OCRRevisionView(documento: doc, reclamo: reclamo, campos: campos) {
                        try? ctx.save()
                    }
                }
            }
            .sheet(isPresented: $mostrarReceta, onDismiss: { dismiss() }) {
                if let paciente = reclamo.cobertura?.paciente {
                    RecetaAlarmasView(
                        paciente: paciente,
                        documentoRutaPDF: documento?.rutaPDF ?? "",
                        pautas: recetaPautas
                    ) { try? ctx.save() }
                }
            }
            .alert("Error", isPresented: .constant(error != nil)) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
            .onAppear(perform: cargar)
            .onAppear {
                if autoEscanear && paginas.isEmpty { mostrarScanner = true }
            }
        }
    }

    // MARK: - Carga

    private func cargar() {
        guard let doc = documento, paginas.isEmpty else { return }
        tipo = doc.tipo
        tipoPersonalizado = doc.tipoPersonalizado
        paginas = doc.paginas
    }

    // MARK: - Escaneo

    private func recibirEscaneo(_ imagenes: [UIImage]) {
        guard !imagenes.isEmpty else { return }

        // Re-escaneo de una página individual: reemplaza la imagen, conserva posición.
        if let orden = reescaneandoOrden, let img = imagenes.first,
           let pagina = paginas.first(where: { $0.orden == orden }) {
            guardarOriginal(img, para: pagina)
            reescaneandoOrden = nil
            return
        }

        let filtroSugerido = ImageFilters.sugerirFiltro(para: imagenes.first!)
        var siguiente = (paginas.map(\.orden).max() ?? -1) + 1
        for img in imagenes {
            let pagina = PaginaEscaneada(orden: siguiente)
            pagina.filtro = filtroSugerido
            guardarOriginal(img, para: pagina)
            paginas.append(pagina)
            siguiente += 1
        }
    }

    private func guardarOriginal(_ img: UIImage, para pagina: PaginaEscaneada) {
        let url = FileStore.urlOriginal(paginaID: pagina.id)
        if let data = img.jpegData(compressionQuality: 0.9) {
            try? FileStore.guardar(data, en: url)
            pagina.rutaOriginal = "originales/\(pagina.id).jpg"
        }
    }

    // MARK: - Edición

    private func rotar(_ pagina: PaginaEscaneada) {
        pagina.rotacion = (pagina.rotacion + 90) % 360
    }

    private func aplicarFiltroATodas(_ f: FiltroEscaneo) {
        for p in paginas { p.filtro = f }
    }

    private func eliminar(_ offsets: IndexSet) {
        let ordenadas = paginas.sorted { $0.orden < $1.orden }
        for i in offsets { if let idx = paginas.firstIndex(where: { $0.id == ordenadas[i].id }) { paginas.remove(at: idx) } }
        renumerar()
    }

    private func mover(_ from: IndexSet, _ to: Int) {
        var ordenadas = paginas.sorted { $0.orden < $1.orden }
        ordenadas.move(fromOffsets: from, toOffset: to)
        for (i, p) in ordenadas.enumerated() { p.orden = i }
        paginas = ordenadas
    }

    private func renumerar() {
        for (i, p) in paginas.sorted(by: { $0.orden < $1.orden }).enumerated() { p.orden = i }
    }

    // MARK: - Guardar / generar PDF

    private func guardar() async {
        generando = true
        defer { generando = false }

        let doc: Documento
        if let existente = documento {
            doc = existente
        } else {
            let nuevo = Documento(tipo: tipo, orden: (reclamo.documentos.map(\.orden).max() ?? -1) + 1)
            ctx.insert(nuevo)
            nuevo.reclamo = reclamo
            documento = nuevo
            doc = nuevo
        }
        doc.tipo = tipo
        doc.tipoPersonalizado = tipoPersonalizado
        doc.preajusteCalidad = settings.preajustePorDefecto

        // Vincular páginas al documento.
        for p in paginas { p.documento = doc }
        doc.paginas = paginas

        // Procesar cada página (filtro + rotación) → JPEG comprimido + imagen para OCR.
        var jpegs: [Data] = []
        var filtradas: [UIImage] = []
        for pagina in paginas.sorted(by: { $0.orden < $1.orden }) {
            let url = FileStore.urlOriginal(paginaID: pagina.id)
            guard let data = try? Data(contentsOf: url), let original = UIImage(data: data) else { continue }
            let filtrada = ImageFilters.aplicar(pagina.filtro, a: original, rotacion: pagina.rotacion)
            filtradas.append(filtrada)
            let grises = pagina.filtro == .escalaGrises || pagina.filtro == .blancoYNegro
            if let jpeg = ImageCompressor.comprimir(filtrada, preajuste: doc.preajusteCalidad, escalaGrises: grises) {
                jpegs.append(jpeg)
            }
        }

        guard !jpegs.isEmpty else { error = "No se pudieron procesar las páginas."; return }

        let nombre = FileNamer.nombre(documento: doc, patron: settings.patronNombres)
        let destino = FileStore.urlPDF(nombre: nombre)
        do {
            try PDFBuilder.construir(paginasJPEG: jpegs, titulo: doc.etiqueta, destino: destino)
            doc.rutaPDF = nombre
            doc.tamanoBytes = FileStore.tamano(destino)
        } catch {
            self.error = "No se pudo generar el PDF: \(error.localizedDescription)"
            return
        }

        // OCR en background (§7). Rellena solo campos vacíos; el usuario confirma.
        let campos = await OCRService.procesar(filtradas)
        doc.textoOCR = campos.textoCompleto
        if doc.emisor.isEmpty { doc.emisor = campos.emisor }
        if doc.ruc.isEmpty { doc.ruc = campos.ruc }
        if doc.numeroFactura.isEmpty { doc.numeroFactura = campos.numeroFactura }
        if doc.fechaDocumento == nil { doc.fechaDocumento = campos.fecha }
        if doc.monto == nil { doc.monto = campos.monto }
        MoneyCalc.recalcularMonto(reclamo)
        try? ctx.save()

        // Receta: siempre mostrar la pantalla de confirmación de la pauta (§alarmas).
        // Si el OCR no detectó nada, se abre con un renglón en blanco para llenar.
        if doc.tipo == .receta, reclamo.cobertura?.paciente != nil {
            let pautas = RecetaParser.parse(campos.textoCompleto)
            recetaPautas = pautas.isEmpty ? [PautaDetectada.enBlanco] : pautas
            mostrarReceta = true
            return
        }

        // Para documentos facturables mostramos la tarjeta de confirmación del monto.
        if doc.tipo.esFacturable {
            ocrCampos = campos
            mostrarOCR = true
        } else {
            dismiss()
        }
    }
}

// MARK: - Fila de página

private struct PaginaFila: View {
    let pagina: PaginaEscaneada
    var rotar: () -> Void
    var cambiarFiltro: (FiltroEscaneo) -> Void
    var reescanear: () -> Void

    @State private var thumb: UIImage?

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let thumb {
                    Image(uiImage: thumb).resizable().scaledToFill()
                } else {
                    Rectangle().fill(.quaternary)
                }
            }
            .frame(width: 48, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            Text("Página \(pagina.orden + 1)")
            Spacer()

            Menu {
                ForEach(FiltroEscaneo.allCases, id: \.self) { f in
                    Button {
                        cambiarFiltro(f); recargar()
                    } label: {
                        if pagina.filtro == f { Label(f.etiqueta, systemImage: "checkmark") } else { Text(f.etiqueta) }
                    }
                }
            } label: { Image(systemName: "camera.filters") }

            Button { rotar(); recargar() } label: { Image(systemName: "rotate.right") }
            Button { reescanear() } label: { Image(systemName: "arrow.triangle.2.circlepath.camera") }
        }
        .buttonStyle(.borderless)
        .onAppear(perform: recargar)
    }

    private func recargar() {
        let url = FileStore.urlOriginal(paginaID: pagina.id)
        DispatchQueue.global(qos: .userInitiated).async {
            guard let data = try? Data(contentsOf: url), let img = UIImage(data: data) else { return }
            let f = ImageFilters.aplicar(pagina.filtro, a: img, rotacion: pagina.rotacion)
            let mini = f.preparingThumbnail(of: CGSize(width: 96, height: 128)) ?? f
            DispatchQueue.main.async { thumb = mini }
        }
    }
}
