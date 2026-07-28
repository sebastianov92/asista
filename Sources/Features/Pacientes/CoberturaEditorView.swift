import SwiftUI
import SwiftData

/// Alta y edición de una `Cobertura` (join Paciente ↔ Póliza).
struct CoberturaEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Poliza.alias) private var polizas: [Poliza]

    private let paciente: Paciente
    @State private var cobertura: Cobertura
    private let esNueva: Bool
    @State private var insertada = false

    @State private var polizaSeleccionada: Poliza?

    init(paciente: Paciente, cobertura: Cobertura? = nil) {
        self.paciente = paciente
        if let cobertura {
            _cobertura = State(initialValue: cobertura)
            _polizaSeleccionada = State(initialValue: cobertura.poliza)
            esNueva = false
        } else {
            _cobertura = State(initialValue: Cobertura())
            _polizaSeleccionada = State(initialValue: nil)
            esNueva = true
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Póliza") {
                    Picker("Póliza", selection: $polizaSeleccionada) {
                        Text("Selecciona…").tag(Optional<Poliza>.none)
                        ForEach(polizas) { pol in
                            Text(etiquetaPoliza(pol)).tag(Optional(pol))
                        }
                    }
                    TextField("N.º de certificado", text: $cobertura.numeroCertificado)
                    Toggle("Activa", isOn: $cobertura.activa)
                }

                Section("Deducible") {
                    DecimalField(titulo: "Consumido", valor: Binding(
                        get: { cobertura.deducibleConsumido },
                        set: { cobertura.deducibleConsumido = $0 ?? 0 }
                    ))
                }

                Section {
                    DestinatariosEditor(destinatarios: $cobertura.destinatariosOverride, context: context)
                } header: {
                    Text("Destinatarios override")
                } footer: {
                    Text("Si agregas destinatarios aquí, REEMPLAZAN a los de la póliza para este paciente.")
                }
            }
            .navigationTitle(esNueva ? "Nueva cobertura" : "Editar cobertura")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar", role: .cancel) { cancelar() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { guardar() }
                        .disabled(polizaSeleccionada == nil)
                }
            }
            .onAppear {
                if esNueva && !insertada {
                    context.insert(cobertura)
                    insertada = true
                }
            }
        }
    }

    private func etiquetaPoliza(_ pol: Poliza) -> String {
        let ase = pol.aseguradora?.nombre ?? "Sin aseguradora"
        return "\(pol.nombreVisible) — \(ase)"
    }

    private func guardar() {
        if esNueva && !insertada {
            context.insert(cobertura)
        }
        cobertura.paciente = paciente
        cobertura.poliza = polizaSeleccionada
        try? context.save()
        dismiss()
    }

    private func cancelar() {
        if esNueva && insertada {
            for d in cobertura.destinatariosOverride { context.delete(d) }
            context.delete(cobertura)
            try? context.save()
        }
        dismiss()
    }
}
