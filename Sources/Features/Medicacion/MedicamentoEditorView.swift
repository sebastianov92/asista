import SwiftUI
import SwiftData

// Alta/edición de una pauta de medicación con alarmas.

struct MedicamentoEditorView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    let paciente: Paciente
    var medicamento: Medicamento?

    @State private var nombre = ""
    @State private var dosis = "1 pastilla"
    @State private var instrucciones = ""
    @State private var cadaHoras = 8
    @State private var fechaInicio = Date()
    @State private var conDuracion = false
    @State private var duracionDias = 7
    @State private var sonarComoAlarma = true
    @State private var activa = true

    private let opcionesHoras = [4, 6, 8, 12, 24]

    var body: some View {
        NavigationStack {
            Form {
                Section("Medicamento") {
                    TextField("Nombre (ej. Amoxicilina 500mg)", text: $nombre)
                    TextField("Dosis (ej. 1 pastilla)", text: $dosis)
                    TextField("Instrucciones (ej. con comida)", text: $instrucciones, axis: .vertical)
                }

                Section("Frecuencia") {
                    Picker("Cada", selection: $cadaHoras) {
                        ForEach(opcionesHoras, id: \.self) { h in
                            Text("\(h) horas").tag(h)
                        }
                    }
                    DatePicker("Primera toma", selection: $fechaInicio)
                    Toggle("Por tiempo definido", isOn: $conDuracion)
                    if conDuracion {
                        Stepper("Durante \(duracionDias) días", value: $duracionDias, in: 1...90)
                    }
                }

                Section {
                    Toggle(isOn: $sonarComoAlarma) {
                        Label("Sonar como alarma", systemImage: "alarm.waves.left.and.right")
                    }
                    Toggle("Activa", isOn: $activa)
                } footer: {
                    Text("Con «Sonar como alarma» usamos un sonido fuerte y la notificación es urgente. En primer plano suena aunque el teléfono esté en silencio. Para que suene siempre con la app cerrada e ignorando el silencio se necesita el permiso de «alertas críticas» de Apple (ajústalo en Xcode con tu cuenta de desarrollador).")
                }

                if !previewTomas.isEmpty {
                    Section("Próximas tomas") {
                        ForEach(previewTomas, id: \.self) { d in
                            Text(fechaHora(d)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle(medicamento == nil ? "Nuevo medicamento" : "Editar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { guardar() }.disabled(nombre.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: cargar)
        }
    }

    private var previewTomas: [Date] {
        var out: [Date] = []
        var t = fechaInicio
        let paso = TimeInterval(cadaHoras) * 3600
        for _ in 0..<4 { out.append(t); t = t.addingTimeInterval(paso) }
        return out
    }

    private func fechaHora(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "es_EC")
        f.dateFormat = "EEE d MMM, HH:mm"
        return f.string(from: d)
    }

    private func cargar() {
        guard let m = medicamento else { return }
        nombre = m.nombre; dosis = m.dosis; instrucciones = m.instrucciones
        cadaHoras = m.cadaHoras; fechaInicio = m.fechaInicio
        conDuracion = m.duracionDias > 0; duracionDias = max(1, m.duracionDias)
        sonarComoAlarma = m.sonarComoAlarma; activa = m.activa
    }

    private func guardar() {
        let m: Medicamento
        if let existente = medicamento { m = existente }
        else { m = Medicamento(); ctx.insert(m); m.paciente = paciente }
        m.nombre = nombre; m.dosis = dosis; m.instrucciones = instrucciones
        m.cadaHoras = cadaHoras; m.fechaInicio = fechaInicio
        m.duracionDias = conDuracion ? duracionDias : 0
        m.sonarComoAlarma = sonarComoAlarma; m.activa = activa
        try? ctx.save()

        // Reprogramar alarmas de todos los medicamentos del paciente.
        let todos = (try? ctx.fetch(FetchDescriptor<Medicamento>())) ?? []
        Task { await AlarmaScheduler.reprogramar(todos) }
        dismiss()
    }
}
