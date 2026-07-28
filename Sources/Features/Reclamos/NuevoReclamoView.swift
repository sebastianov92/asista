import SwiftUI
import SwiftData

// Nuevo reclamo (§13.1): paciente → póliza (autoseleccionada si solo hay una)
// → datos del evento → crear y abrir cámara.

struct NuevoReclamoView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Paciente.apellidos) private var pacientes: [Paciente]
    @Query private var todosReclamos: [Reclamo]

    @State private var paciente: Paciente?
    @State private var cobertura: Cobertura?
    @State private var fechaEvento = Date()
    @State private var prestador = ""
    @State private var medico = ""
    @State private var diagnostico = ""

    @State private var reclamoCreado: Reclamo?

    private var coberturas: [Cobertura] {
        (paciente?.coberturas ?? []).filter { $0.activa }
            .sorted { ($0.poliza?.prioridad ?? 0) < ($1.poliza?.prioridad ?? 0) }
    }

    private var puedeCrear: Bool { cobertura != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Paciente") {
                    Picker("Paciente", selection: $paciente) {
                        Text("Selecciona…").tag(Paciente?.none)
                        ForEach(pacientes) { p in
                            Text(p.nombreCompleto).tag(Paciente?.some(p))
                        }
                    }
                    .onChange(of: paciente) { _, nuevo in
                        // Autoseleccionar la única cobertura si aplica.
                        let cobs = (nuevo?.coberturas ?? []).filter { $0.activa }
                        cobertura = cobs.count == 1 ? cobs.first : nil
                    }
                }

                if paciente != nil {
                    Section("Póliza") {
                        if coberturas.isEmpty {
                            Text("Este paciente no tiene coberturas activas. Agrégalas en su perfil.")
                                .foregroundStyle(.secondary)
                        } else {
                            Picker("Póliza", selection: $cobertura) {
                                Text("Selecciona…").tag(Cobertura?.none)
                                ForEach(coberturas) { c in
                                    Text(c.poliza?.nombreVisible ?? "Póliza")
                                        .tag(Cobertura?.some(c))
                                }
                            }
                            if let c = cobertura, let ase = c.poliza?.aseguradora {
                                LabeledContent("Aseguradora", value: ase.nombre)
                                if !c.numeroCertificado.isEmpty {
                                    LabeledContent("Certificado", value: c.numeroCertificado)
                                }
                            }
                        }
                    }
                }

                Section("Datos del evento") {
                    DatePicker("Fecha de atención", selection: $fechaEvento, displayedComponents: .date)
                    TextField("Prestador (clínica, laboratorio…)", text: $prestador)
                    TextField("Médico", text: $medico)
                    TextField("Diagnóstico", text: $diagnostico, axis: .vertical)
                }
            }
            .navigationTitle("Nuevo reclamo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Crear") { crear() }
                        .disabled(!puedeCrear)
                }
            }
            .navigationDestination(item: $reclamoCreado) { reclamo in
                ReclamoDetailView(reclamo: reclamo, autoEscanear: true)
            }
        }
    }

    private func crear() {
        guard let cobertura else { return }
        let siguiente = (todosReclamos.map(\.numero).max() ?? 0) + 1
        let reclamo = Reclamo(cobertura: cobertura)
        reclamo.numero = siguiente
        reclamo.fechaEvento = fechaEvento
        reclamo.prestador = prestador
        reclamo.medico = medico
        reclamo.diagnostico = diagnostico
        // Copiar el checklist por defecto de la póliza (editable por reclamo, §10).
        reclamo.checklist = cobertura.poliza?.checklistPorDefecto ?? []
        reclamo.tomarSnapshot()
        ctx.insert(reclamo)
        try? ctx.save()
        reclamoCreado = reclamo
    }
}
