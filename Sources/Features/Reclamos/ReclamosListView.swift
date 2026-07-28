import SwiftUI
import SwiftData

struct ReclamosListView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Reclamo.fechaCreacion, order: .reverse) private var reclamos: [Reclamo]
    @Query private var pacientes: [Paciente]

    @EnvironmentObject private var sendQueue: SendQueue
    @State private var mostrarNuevo = false
    @State private var filtroEstado: EstadoReclamo?
    @State private var busqueda = ""

    private var filtrados: [Reclamo] {
        reclamos.filter { r in
            (filtroEstado == nil || r.estado == filtroEstado) &&
            (busqueda.isEmpty || coincide(r, busqueda))
        }
    }

    /// Agrupado por estado, en orden lógico de flujo.
    private var grupos: [(EstadoReclamo, [Reclamo])] {
        EstadoReclamo.allCases.compactMap { estado in
            let items = filtrados.filter { $0.estado == estado }
            return items.isEmpty ? nil : (estado, items)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if reclamos.isEmpty {
                    VacioView(
                        icono: "doc.badge.plus",
                        titulo: "Sin reclamos todavía",
                        detalle: pacientes.isEmpty
                            ? "Primero crea un paciente y una póliza, luego arma tu primer reclamo."
                            : "Toca + para escanear y enviar tu primer reclamo."
                    )
                } else {
                    List {
                        if sendQueue.pendientes > 0 || !sendQueue.conectado {
                            Section {
                                HStack {
                                    Image(systemName: sendQueue.conectado ? "arrow.up.circle" : "wifi.slash")
                                        .foregroundStyle(.orange)
                                    Text(sendQueue.conectado
                                         ? "\(sendQueue.pendientes) envío(s) pendiente(s), se reintentan solos."
                                         : "Sin conexión. Los envíos quedan en cola.")
                                        .font(.caption)
                                    Spacer()
                                    if sendQueue.conectado {
                                        Button("Reintentar") { Task { await sendQueue.procesar() } }
                                            .font(.caption)
                                    }
                                }
                            }
                        }
                        Section {
                            PendienteDeCobroCard(reclamos: reclamos) { estado in
                                filtroEstado = estado
                            }
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                        }

                        if filtroEstado != nil {
                            Button {
                                filtroEstado = nil
                            } label: {
                                Label("Quitar filtro: \(filtroEstado!.etiqueta)", systemImage: "xmark.circle.fill")
                            }
                        }

                        ForEach(grupos, id: \.0) { estado, items in
                            Section(estado.etiqueta) {
                                ForEach(items) { reclamo in
                                    NavigationLink {
                                        ReclamoDetailView(reclamo: reclamo)
                                    } label: {
                                        ReclamoFila(reclamo: reclamo)
                                    }
                                }
                            }
                        }
                    }
                    .searchable(text: $busqueda, prompt: "Buscar por paciente, prestador, diagnóstico")
                }
            }
            .navigationTitle("Reclamos")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        mostrarNuevo = true
                    } label: { Image(systemName: "plus") }
                    .disabled(pacientes.isEmpty)
                }
            }
            .sheet(isPresented: $mostrarNuevo) {
                NuevoReclamoView()
            }
            .onAppear {
                sendQueue.actualizarConteo()
                // Atajo de Siri "Nuevo reclamo" (§Fase 4).
                if UserDefaults.standard.bool(forKey: "abrirNuevoReclamo") && !pacientes.isEmpty {
                    UserDefaults.standard.set(false, forKey: "abrirNuevoReclamo")
                    mostrarNuevo = true
                }
            }
        }
    }

    private func coincide(_ r: Reclamo, _ q: String) -> Bool {
        let campos = [
            r.cobertura?.paciente?.nombreCompleto ?? "",
            r.prestador, r.medico, r.diagnostico, r.notas,
        ]
        return campos.contains { $0.localizedCaseInsensitiveContains(q) }
    }
}

struct ReclamoFila: View {
    let reclamo: Reclamo
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: reclamo.estado.simbolo)
                .foregroundStyle(reclamo.estado.color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(reclamo.pacienteNombre.isEmpty ? "Paciente" : reclamo.pacienteNombre)
                    .font(.body.weight(.medium))
                Text("#\(reclamo.numero) · \(reclamo.prestador.isEmpty ? "Sin prestador" : reclamo.prestador)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Formato.montoUSD(reclamo.montoReclamado))
                    .font(.callout.weight(.semibold))
                if reclamo.envios.contains(where: { $0.estado == .pendiente || $0.estado == .fallido }) {
                    Label("Pendiente de envío", systemImage: "arrow.up.circle")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .labelStyle(.iconOnly)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct VacioView: View {
    let icono: String
    let titulo: String
    let detalle: String
    var body: some View {
        ContentUnavailableView {
            Label(titulo, systemImage: icono)
        } description: {
            Text(detalle)
        }
    }
}
