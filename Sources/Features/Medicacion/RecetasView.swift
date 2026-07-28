import SwiftUI
import SwiftData

// Tab Recetas: qué se está tomando ahora, cuánto falta, próxima toma, on/off.

struct RecetasView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Medicamento.fechaInicio, order: .reverse) private var medicamentos: [Medicamento]
    @Query private var pacientes: [Paciente]

    @State private var agregar = false
    @State private var editar: Medicamento?

    private var enCurso: [Medicamento] { medicamentos.filter { $0.enCurso } }
    private var programadas: [Medicamento] { medicamentos.filter { $0.programada } }
    private var terminadas: [Medicamento] { medicamentos.filter { $0.terminado || !$0.activa } }

    var body: some View {
        NavigationStack {
            Group {
                if medicamentos.isEmpty {
                    ContentUnavailableView {
                        Label("Sin recetas", systemImage: "pills")
                    } description: {
                        Text("Sube una receta y creamos las alarmas de cada toma.")
                    } actions: {
                        Button("Agregar receta") { agregar = true }.buttonStyle(.borderedProminent)
                            .disabled(pacientes.isEmpty)
                    }
                } else {
                    List {
                        if !enCurso.isEmpty {
                            Section("Tomando ahora") { ForEach(enCurso) { fila($0) } }
                        }
                        if !programadas.isEmpty {
                            Section("Programadas") { ForEach(programadas) { fila($0) } }
                        }
                        if !terminadas.isEmpty {
                            Section("Terminadas / pausadas") { ForEach(terminadas) { fila($0) } }
                        }
                    }
                }
            }
            .navigationTitle("Recetas")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { agregar = true } label: { Image(systemName: "plus") }
                        .disabled(pacientes.isEmpty)
                }
            }
            .sheet(isPresented: $agregar) { AgregarRecetaView() }
            .sheet(item: $editar) { med in
                if let p = med.paciente { MedicamentoEditorView(paciente: p, medicamento: med) }
            }
        }
    }

    @ViewBuilder
    private func fila(_ med: Medicamento) -> some View {
        HStack(spacing: 12) {
            Image(systemName: med.sonarComoAlarma ? "alarm.waves.left.and.right.fill" : "pills.fill")
                .foregroundStyle(med.activa && !med.terminado ? Tema.acento : .secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Button { editar = med } label: {
                    Text(med.nombre.isEmpty ? "Medicamento" : med.nombre)
                        .font(.body.weight(.medium)).foregroundStyle(.primary)
                }.buttonStyle(.plain)

                if let p = med.paciente {
                    Text(p.nombreCompleto).font(.caption2).foregroundStyle(.secondary)
                }
                Text(detalle(med)).font(.caption).foregroundStyle(.secondary)
                Text(restante(med)).font(.caption2).foregroundStyle(colorRestante(med))
                if med.tomasDadas > 0 {
                    Text("Tomadas: \(med.tomasConfirmadas)/\(med.tomasDadas)" +
                         (med.adherencia.map { " · \(Int($0 * 100))%" } ?? ""))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { med.activa },
                set: { med.activa = $0; guardarYReprogramar() }
            ))
            .labelsHidden()
        }
        .padding(.vertical, 2)
    }

    private func detalle(_ m: Medicamento) -> String {
        var s = "\(m.dosis) · cada \(m.cadaHoras)h"
        if let prox = m.proximaToma {
            s += " · próxima " + hora(prox)
        }
        return s
    }

    private func restante(_ m: Medicamento) -> String {
        if !m.activa { return "Pausada" }
        if m.terminado { return "Terminada" }
        if let r = m.tomasRestantes { return "Faltan \(r) tomas" + (m.fechaFin.map { " · termina \(fecha($0))" } ?? "") }
        if let fin = m.fechaFin { return "Termina \(fecha(fin))" }
        return "En curso (sin fin definido)"
    }

    private func colorRestante(_ m: Medicamento) -> Color {
        if !m.activa || m.terminado { return .secondary }
        if let r = m.tomasRestantes, r <= 2 { return .orange }
        return .secondary
    }

    private func guardarYReprogramar() {
        try? ctx.save()
        let todos = (try? ctx.fetch(FetchDescriptor<Medicamento>())) ?? []
        Task { await AlarmaScheduler.reprogramar(todos) }
    }

    private func hora(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "es_EC"); f.dateFormat = "EEE HH:mm"
        return f.string(from: d)
    }
    private func fecha(_ d: Date) -> String { Formato.fechaISO(d) }
}
