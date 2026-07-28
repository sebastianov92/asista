import SwiftUI
import SwiftData

/// Alta y edición de una `Poliza`: aseguradora, vigencia, destinatarios (§4),
/// checklist por defecto y plantilla inline opcional.
struct PolizaEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Aseguradora.nombre) private var aseguradoras: [Aseguradora]

    @State private var poliza: Poliza
    private let esNueva: Bool
    @State private var insertada = false

    @State private var aseguradoraSeleccionada: Aseguradora?
    @State private var usarPorcentaje: Bool
    @State private var porcentaje: Double  // 0...100 para el slider
    @State private var usarPlantilla: Bool

    init(poliza: Poliza? = nil) {
        if let poliza {
            _poliza = State(initialValue: poliza)
            _aseguradoraSeleccionada = State(initialValue: poliza.aseguradora)
            _usarPorcentaje = State(initialValue: poliza.porcentajeCobertura != nil)
            _porcentaje = State(initialValue: (poliza.porcentajeCobertura ?? 0.8) * 100)
            _usarPlantilla = State(initialValue: poliza.plantilla != nil)
            esNueva = false
        } else {
            _poliza = State(initialValue: Poliza())
            _aseguradoraSeleccionada = State(initialValue: nil)
            _usarPorcentaje = State(initialValue: false)
            _porcentaje = State(initialValue: 80)
            _usarPlantilla = State(initialValue: false)
            esNueva = true
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                seccionDatos
                seccionVigencia
                seccionMontos
                seccionDestinatarios
                seccionChecklist
                seccionPlantilla
            }
            .navigationTitle(esNueva ? "Nueva póliza" : "Editar póliza")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar", role: .cancel) { cancelar() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { guardar() }
                        .disabled(aseguradoraSeleccionada == nil)
                }
            }
            .onAppear {
                if esNueva && !insertada {
                    context.insert(poliza)
                    insertada = true
                }
            }
        }
    }

    // MARK: - Secciones

    private var seccionDatos: some View {
        Section("Datos") {
            Picker("Aseguradora", selection: $aseguradoraSeleccionada) {
                Text("Selecciona…").tag(Optional<Aseguradora>.none)
                ForEach(aseguradoras) { ase in
                    Text(ase.nombre.isEmpty ? "Sin nombre" : ase.nombre).tag(Optional(ase))
                }
            }
            TextField("Número", text: $poliza.numero)
            TextField("Alias (ej. Seguro de la empresa)", text: $poliza.alias)
            TextField("Contratante", text: $poliza.contratante)
            Stepper("Prioridad: \(poliza.prioridad)", value: $poliza.prioridad, in: 0...20)
        }
    }

    private var seccionVigencia: some View {
        Section("Vigencia") {
            FechaOpcionalRow(titulo: "Vigencia desde", fecha: $poliza.vigenciaDesde)
            FechaOpcionalRow(titulo: "Vigencia hasta", fecha: $poliza.vigenciaHasta)
        }
    }

    private var seccionMontos: some View {
        Section("Montos") {
            DecimalField(titulo: "Deducible anual", valor: $poliza.deducibleAnual)
            DecimalField(titulo: "Tope anual", valor: $poliza.topeAnual)

            Toggle("Definir % de cobertura", isOn: Binding(
                get: { usarPorcentaje },
                set: { activar in
                    usarPorcentaje = activar
                    poliza.porcentajeCobertura = activar ? porcentaje / 100 : nil
                }
            ))
            if usarPorcentaje {
                VStack {
                    HStack {
                        Text("Cobertura")
                        Spacer()
                        Text("\(Int(porcentaje))%").foregroundStyle(.secondary)
                    }
                    Slider(value: Binding(
                        get: { porcentaje },
                        set: { porcentaje = $0; poliza.porcentajeCobertura = $0 / 100 }
                    ), in: 0...100, step: 1)
                }
            }
        }
    }

    private var seccionDestinatarios: some View {
        Section {
            DestinatariosEditor(destinatarios: $poliza.destinatarios, context: context)
        } header: {
            Text("Destinatarios de la póliza")
        } footer: {
            Text("Definen a quién se envía cada reclamo. Marca al menos un \"Para\".")
        }
    }

    private var seccionChecklist: some View {
        Section {
            ForEach(TipoDocumento.allCases, id: \.self) { tipo in
                Button {
                    alternarChecklist(tipo)
                } label: {
                    HStack {
                        Image(systemName: tipo.simbolo)
                            .foregroundStyle(Tema.acento)
                            .frame(width: 26)
                        Text(tipo.etiqueta)
                            .foregroundStyle(.primary)
                        Spacer()
                        if poliza.checklistPorDefecto.contains(tipo) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Tema.acento)
                        }
                    }
                }
            }
        } header: {
            Text("Checklist por defecto")
        } footer: {
            Text("Documentos que esta póliza exige por defecto en cada reclamo.")
        }
    }

    @ViewBuilder
    private var seccionPlantilla: some View {
        Section {
            Toggle("Plantilla de la póliza", isOn: Binding(
                get: { usarPlantilla },
                set: { activar in
                    usarPlantilla = activar
                    if activar {
                        if poliza.plantilla == nil {
                            let p = PlantillaCorreo(nombre: "Plantilla \(poliza.nombreVisible)")
                            context.insert(p)
                            poliza.plantilla = p
                        }
                    } else if let p = poliza.plantilla {
                        poliza.plantilla = nil
                        context.delete(p)
                    }
                }
            ))
            if usarPlantilla, let plantilla = poliza.plantilla {
                TextField("Nombre de la plantilla", text: Binding(
                    get: { plantilla.nombre }, set: { plantilla.nombre = $0 }
                ))
                TextField("Asunto", text: Binding(
                    get: { plantilla.asunto }, set: { plantilla.asunto = $0 }
                ))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Cuerpo").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: Binding(
                        get: { plantilla.cuerpo }, set: { plantilla.cuerpo = $0 }
                    ))
                    .frame(minHeight: 120)
                }
            }
        } header: {
            Text("Plantilla de correo")
        } footer: {
            Text("Si la defines, tiene prioridad sobre la plantilla de la aseguradora.")
        }
    }

    // MARK: - Acciones

    private func alternarChecklist(_ tipo: TipoDocumento) {
        if let idx = poliza.checklistPorDefecto.firstIndex(of: tipo) {
            poliza.checklistPorDefecto.remove(at: idx)
        } else {
            poliza.checklistPorDefecto.append(tipo)
        }
    }

    private func guardar() {
        if esNueva && !insertada {
            context.insert(poliza)
        }
        poliza.aseguradora = aseguradoraSeleccionada
        try? context.save()
        dismiss()
    }

    private func cancelar() {
        if esNueva && insertada {
            for d in poliza.destinatarios { context.delete(d) }
            if let p = poliza.plantilla { context.delete(p) }
            context.delete(poliza)
            try? context.save()
        }
        dismiss()
    }
}
