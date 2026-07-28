import SwiftUI
import SwiftData

// "Receta detectada": el OCR arma la pauta; el usuario solo ajusta y elige la
// hora de la primera toma. Crea un Medicamento (con alarmas) por cada renglón.

struct RecetaAlarmasView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    let paciente: Paciente
    let documentoRutaPDF: String
    @State var pautas: [PautaDetectada]
    var onListo: () -> Void

    @State private var fechaInicio = RecetaAlarmasView.proximaHora()
    @State private var sonarComoAlarma = true

    private let opcionesHoras = [4, 6, 8, 12, 24]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Detectamos la receta. Revisa la pauta y elige a qué hora empiezas.",
                          systemImage: "pills.circle")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("Primera toma") {
                    DatePicker("Empiezo a tomar", selection: $fechaInicio)
                    Toggle("Sonar como alarma", isOn: $sonarComoAlarma)
                }

                ForEach($pautas) { $p in
                    Section {
                        TextField("Medicamento", text: $p.nombre)
                        TextField("Dosis", text: $p.dosis)
                        Picker("Cada", selection: $p.cadaHoras) {
                            ForEach(opcionesHoras, id: \.self) { Text("\($0) h").tag($0) }
                        }
                        Stepper(p.duracionDias > 0 ? "Durante \(p.duracionDias) días" : "Sin fin definido",
                                value: $p.duracionDias, in: 0...90)
                    } header: {
                        HStack {
                            Text(p.nombre.isEmpty ? "Medicamento" : p.nombre)
                            Spacer()
                            Button(role: .destructive) { quitar(p) } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless)
                        }
                    } footer: {
                        if p.dosisTotales > 0 {
                            Text("Por cantidad: \(p.dosisTotales) tomas. Termina ~\(finEstimado(p)). Las alarmas se detienen solas.")
                        } else if p.duracionDias > 0 {
                            Text("Las alarmas se detienen solas al terminar el tratamiento (\(p.duracionDias) días).")
                        } else {
                            Text("Sin fin definido: sonará hasta que la pauses.")
                        }
                    }
                }

                Section {
                    Button {
                        pautas.append(.enBlanco)
                    } label: {
                        Label("Agregar medicamento", systemImage: "plus.circle")
                    }
                }
            }
            .navigationTitle("Receta detectada")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Omitir") { onListo(); dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Crear alarmas") { crear() }.disabled(pautas.isEmpty)
                }
            }
        }
    }

    private func quitar(_ p: PautaDetectada) {
        pautas.removeAll { $0.id == p.id }
    }

    private func finEstimado(_ p: PautaDetectada) -> String {
        guard p.dosisTotales > 0 else { return "" }
        let seg = TimeInterval((p.dosisTotales - 1) * p.cadaHoras) * 3600
        let fin = fechaInicio.addingTimeInterval(seg)
        let f = DateFormatter(); f.locale = Locale(identifier: "es_EC"); f.dateFormat = "EEE d MMM, HH:mm"
        return f.string(from: fin)
    }

    private func crear() {
        for p in pautas where !p.nombre.trimmingCharacters(in: .whitespaces).isEmpty {
            let m = Medicamento(nombre: p.nombre, cadaHoras: p.cadaHoras)
            m.dosis = p.dosis
            m.duracionDias = p.duracionDias
            m.dosisTotales = p.dosisTotales
            m.fechaInicio = fechaInicio
            m.sonarComoAlarma = sonarComoAlarma
            m.documentoRutaPDF = documentoRutaPDF
            m.activa = true
            ctx.insert(m)
            m.paciente = paciente
        }
        try? ctx.save()

        let todos = (try? ctx.fetch(FetchDescriptor<Medicamento>())) ?? []
        Task { await AlarmaScheduler.reprogramar(todos) }
        onListo()
        dismiss()
    }

    /// Próxima hora en punto como valor por defecto de inicio.
    private static func proximaHora() -> Date {
        let cal = Calendar.current
        let ahora = Date()
        var comps = cal.dateComponents([.year, .month, .day, .hour], from: ahora)
        comps.hour = (comps.hour ?? 0) + 1
        comps.minute = 0
        return cal.date(from: comps) ?? ahora
    }
}
