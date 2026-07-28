import SwiftUI
import SwiftData

// Pantalla de envío (§13.2). Muestra destinatarios resueltos (con origen), asunto,
// cuerpo, adjuntos con peso, peso total en grande con color, y el botón de enviar.

struct EnvioView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettings

    let reclamo: Reclamo
    @Query(filter: #Predicate<PlantillaCorreo> { $0.esGlobalPorDefecto == true })
    private var globales: [PlantillaCorreo]

    @State private var asunto = ""
    @State private var cuerpo = ""
    @State private var nuevoEmail = ""
    @State private var enviando = false
    @State private var resultado: String?
    @State private var exito = false
    @State private var recomprimiendo = false

    private var plantillaGlobal: PlantillaCorreo? { globales.first }

    private var chips: [ChipDestinatario] {
        RecipientResolver.chips(reclamo, copiaPropiaEmail: settings.copiaPropiaActiva ? settings.miEmail : nil)
    }

    private var adjuntos: [(nombre: String, bytes: Int)] {
        reclamo.documentos.sorted { $0.orden < $1.orden }
            .filter { !$0.rutaPDF.isEmpty }
            .map { ($0.rutaPDF, $0.tamanoBytes) }
    }

    private var pesoTotal: Int { adjuntos.reduce(0) { $0 + $1.bytes } }
    private var enAmbarORojo: Bool { pesoTotal > 10 * 1024 * 1024 }

    private var faltanDocs: [TipoDocumento] {
        let presentes = Set(reclamo.documentos.map(\.tipo))
        return reclamo.checklist.filter { !presentes.contains($0) }
    }

    private var puedeEnviar: Bool {
        !adjuntos.isEmpty && chips.contains { $0.tipo == .to } && !enviando
    }

    var body: some View {
        NavigationStack {
            Form {
                destinatariosSection
                asuntoCuerpoSection
                adjuntosSection
                if !faltanDocs.isEmpty { checklistAviso }
            }
            .navigationTitle("Enviar reclamo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) { barraEnviar }
            .onAppear(perform: cargarBorrador)
            .alert(exito ? "Enviado" : "No se pudo enviar", isPresented: .constant(resultado != nil)) {
                Button("OK") {
                    let cerrar = exito
                    resultado = nil
                    if cerrar { dismiss() }
                }
            } message: { Text(resultado ?? "") }
        }
    }

    // MARK: - Secciones

    private var destinatariosSection: some View {
        Section("Destinatarios") {
            if chips.isEmpty {
                Text("Sin destinatarios. Configura los de la póliza.")
                    .foregroundStyle(.secondary)
            }
            ForEach(chips) { chip in
                HStack {
                    Text(chip.tipo.etiqueta)
                        .font(.caption.weight(.bold))
                        .frame(width: 34)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading) {
                        Text(chip.email)
                        Text(chip.origen.rawValue).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if chip.origen == .agregado {
                        Button(role: .destructive) { quitarExtra(chip.email) } label: {
                            Image(systemName: "minus.circle.fill")
                        }.buttonStyle(.borderless)
                    }
                }
            }
            HStack {
                TextField("Agregar correo (Cc)", text: $nuevoEmail)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                Button("Agregar") { agregarExtra() }
                    .disabled(!nuevoEmail.contains("@"))
            }
        }
    }

    private var asuntoCuerpoSection: some View {
        Section("Mensaje") {
            TextField("Asunto", text: $asunto, axis: .vertical)
            TextField("Cuerpo", text: $cuerpo, axis: .vertical)
                .frame(minHeight: 160, alignment: .top)
        }
    }

    private var adjuntosSection: some View {
        Section("Adjuntos (\(adjuntos.count))") {
            ForEach(adjuntos, id: \.nombre) { a in
                HStack {
                    Image(systemName: "doc.fill").foregroundStyle(.secondary)
                    Text(a.nombre).font(.caption).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Text(Formato.peso(a.bytes)).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var checklistAviso: some View {
        Section {
            ForEach(faltanDocs, id: \.self) { t in
                Label(t.etiqueta, systemImage: "xmark.circle").foregroundStyle(.orange)
            }
        } header: {
            Text("Faltan \(faltanDocs.count) documentos del checklist")
        }
    }

    // MARK: - Barra inferior

    private var barraEnviar: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Peso total").font(.caption).foregroundStyle(.secondary)
                    Text(Formato.peso(pesoTotal))
                        .font(.title2.bold().monospacedDigit())
                        .foregroundStyle(PesoColor.color(bytes: pesoTotal))
                }
                Spacer()
                if enAmbarORojo {
                    Button {
                        Task { await recomprimir() }
                    } label: {
                        Label("Bajar calidad", systemImage: "arrow.down.circle")
                    }
                    .disabled(recomprimiendo)
                }
            }
            Button {
                Task { await enviar() }
            } label: {
                HStack {
                    if enviando { ProgressView().tint(.white) }
                    Text(enviando ? "Enviando…" : "Enviar")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!puedeEnviar)
        }
        .padding()
        .background(.regularMaterial)
    }

    // MARK: - Acciones

    private func cargarBorrador() {
        let b = EnvioCoordinator.borrador(
            reclamo, plantillaGlobal: plantillaGlobal,
            miEmail: settings.miEmail, copiaPropiaActiva: settings.copiaPropiaActiva
        )
        asunto = b.asunto
        cuerpo = b.cuerpo
    }

    private func agregarExtra() {
        let e = nuevoEmail.trimmingCharacters(in: .whitespaces)
        guard e.contains("@") else { return }
        reclamo.destinatariosExtra.append(e)
        nuevoEmail = ""
        try? ctx.save()
    }

    private func quitarExtra(_ email: String) {
        reclamo.destinatariosExtra.removeAll { $0 == email }
        try? ctx.save()
    }

    private func recomprimir() async {
        recomprimiendo = true
        defer { recomprimiendo = false }
        let entradas = reclamo.documentos.map {
            AutoCompressor.Entrada(id: $0.id, tamanoBytes: $0.tamanoBytes, preajuste: $0.preajusteCalidad)
        }
        let plan = AutoCompressor.planificar(entradas, umbralBytes: settings.umbralTamanoBytes)
        for cambio in plan {
            if let doc = reclamo.documentos.first(where: { $0.id == cambio.documentoID }) {
                DocumentoPDF.regenerar(doc, patron: settings.patronNombres, preajuste: cambio.a)
            }
        }
        try? ctx.save()
    }

    private func enviar() async {
        enviando = true
        defer { enviando = false }
        var b = EnvioCoordinator.borrador(
            reclamo, plantillaGlobal: plantillaGlobal,
            miEmail: settings.miEmail, copiaPropiaActiva: settings.copiaPropiaActiva
        )
        // Usar el asunto/cuerpo editados en pantalla.
        b.asunto = asunto
        b.cuerpo = cuerpo
        let res = await EnvioCoordinator.enviar(reclamo, borrador: b, ctx: ctx, settings: settings)
        switch res {
        case .exito:
            exito = true
            resultado = "El reclamo se envió en un solo correo a \(b.to.count + b.cc.count) destinatarios."
        case .fallo(let msg):
            exito = false
            resultado = msg
        }
    }
}
