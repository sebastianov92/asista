import SwiftUI
import SwiftData
import UIKit

/// Perfil del paciente: datos, coberturas, historial estático y timeline.
struct PacienteDetailView: View {
    @Environment(\.modelContext) private var context
    @Bindable var paciente: Paciente

    @State private var editando = false
    @State private var nuevaCobertura = false
    @State private var coberturaAEditar: Cobertura?
    @State private var nuevoMedicamento = false
    @State private var medicamentoAEditar: Medicamento?

    var body: some View {
        List {
            seccionPerfil
            seccionCoberturas
            seccionMedicacion
            seccionHistorial
            seccionTimeline
        }
        .navigationTitle(paciente.nombreCompleto.isEmpty ? "Paciente" : paciente.nombreCompleto)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Editar") { editando = true }
            }
        }
        .sheet(isPresented: $editando) {
            PacienteEditorView(paciente: paciente)
        }
        .sheet(isPresented: $nuevaCobertura) {
            CoberturaEditorView(paciente: paciente)
        }
        .sheet(item: $coberturaAEditar) { cob in
            CoberturaEditorView(paciente: paciente, cobertura: cob)
        }
        .sheet(isPresented: $nuevoMedicamento) {
            MedicamentoEditorView(paciente: paciente)
        }
        .sheet(item: $medicamentoAEditar) { med in
            MedicamentoEditorView(paciente: paciente, medicamento: med)
        }
    }

    // MARK: - Medicación (alarmas)

    private var seccionMedicacion: some View {
        Section {
            if paciente.medicamentos.isEmpty {
                Text("Sin medicación registrada.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(paciente.medicamentos.sorted { $0.fechaInicio > $1.fechaInicio }) { med in
                Button {
                    medicamentoAEditar = med
                } label: {
                    HStack {
                        Image(systemName: med.sonarComoAlarma ? "alarm.waves.left.and.right.fill" : "pills.fill")
                            .foregroundStyle(med.activa ? Tema.acento : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(med.nombre.isEmpty ? "Medicamento" : med.nombre)
                                .foregroundStyle(.primary)
                            Text(med.resumen).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Spacer()
                        if !med.activa { Text("pausada").font(.caption2).foregroundStyle(.secondary) }
                    }
                }
                .buttonStyle(.plain)
            }
            .onDelete(perform: borrarMedicamento)

            Button { nuevoMedicamento = true } label: {
                Label("Agregar medicamento con alarma", systemImage: "plus.circle")
            }
        } header: {
            Text("Medicación")
        }
    }

    private func borrarMedicamento(_ offsets: IndexSet) {
        let ordenados = paciente.medicamentos.sorted { $0.fechaInicio > $1.fechaInicio }
        for i in offsets { context.delete(ordenados[i]) }
        try? context.save()
        let todos = (try? context.fetch(FetchDescriptor<Medicamento>())) ?? []
        Task { await AlarmaScheduler.reprogramar(todos) }
    }

    // MARK: - Perfil

    private var seccionPerfil: some View {
        Section {
            HStack(spacing: 16) {
                InicialesAvatar(nombre: paciente.nombreCompleto, fotoData: paciente.fotoData, lado: 72)
                VStack(alignment: .leading, spacing: 4) {
                    Text(paciente.nombreCompleto.isEmpty ? "Sin nombre" : paciente.nombreCompleto)
                        .font(.title3.weight(.semibold))
                    Text(paciente.parentesco.etiqueta)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        if !paciente.cedula.isEmpty {
                            Label(paciente.cedula, systemImage: "person.text.rectangle")
                        }
                        if let edad = paciente.edad {
                            Label("\(edad) años", systemImage: "calendar")
                        }
                        if !paciente.tipoSangre.isEmpty {
                            Label(paciente.tipoSangre, systemImage: "drop.fill")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Coberturas

    private var seccionCoberturas: some View {
        Section("Coberturas") {
            if paciente.coberturas.isEmpty {
                Text("Sin coberturas")
                    .foregroundStyle(.secondary)
            }
            ForEach(paciente.coberturas) { cob in
                Button {
                    coberturaAEditar = cob
                } label: {
                    filaCobertura(cob)
                }
                .buttonStyle(.plain)
            }
            Button {
                nuevaCobertura = true
            } label: {
                Label("Agregar cobertura", systemImage: "plus.circle")
            }
        }
    }

    private func filaCobertura(_ cob: Cobertura) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(cob.poliza?.nombreVisible ?? "Sin póliza")
                    .font(.body.weight(.medium))
                Text(cob.poliza?.aseguradora?.nombre ?? "—")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !cob.numeroCertificado.isEmpty {
                    Text("Certificado: \(cob.numeroCertificado)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Toggle("Activa", isOn: Binding(
                get: { cob.activa },
                set: { cob.activa = $0; try? context.save() }
            ))
            .labelsHidden()
        }
        .padding(.vertical, 2)
    }

    // MARK: - Historial estático

    private var seccionHistorial: some View {
        Section("Historial médico (estático)") {
            grupoChips("Alergias", items: paciente.alergias, color: .red)
            grupoChips("Condiciones crónicas", items: paciente.condicionesCronicas, color: .orange)
            grupoChips("Medicación habitual", items: paciente.medicacionHabitual, color: .teal)
            if !paciente.notasMedicas.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Notas").font(.caption).foregroundStyle(.secondary)
                    Text(paciente.notasMedicas)
                }
                .padding(.vertical, 2)
            }
        }
    }

    @ViewBuilder
    private func grupoChips(_ titulo: String, items: [String], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(titulo).font(.caption).foregroundStyle(.secondary)
            if items.isEmpty {
                Text("Ninguna").font(.subheadline).foregroundStyle(.tertiary)
            } else {
                FlowChips(items: items, color: color)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Timeline

    private var seccionTimeline: some View {
        Section("Timeline") {
            NavigationLink {
                TimelineView(paciente: paciente)
            } label: {
                Label("Ver historial completo", systemImage: "calendar.day.timeline.left")
            }
            if paciente.eventos.isEmpty {
                Text("Sin eventos registrados")
                    .foregroundStyle(.secondary)
            }
            ForEach(eventosOrdenados) { evento in
                VStack(alignment: .leading, spacing: 2) {
                    Text(evento.titulo.isEmpty ? "Evento" : evento.titulo)
                        .font(.body.weight(.medium))
                    HStack(spacing: 8) {
                        Text(Formato.fechaISO(evento.fecha))
                        if !evento.medico.isEmpty {
                            Text("· \(evento.medico)")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var eventosOrdenados: [EventoMedico] {
        paciente.eventos.sorted { $0.fecha > $1.fecha }
    }
}

/// Envoltura simple de chips que fluyen en varias líneas.
private struct FlowChips: View {
    let items: [String]
    var color: Color = Tema.acento

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 6, alignment: .leading)], alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { item in
                Chip(texto: item, color: color)
            }
        }
    }
}
