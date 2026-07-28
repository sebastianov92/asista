import SwiftUI
import SwiftData

/// Línea de tiempo del historial médico de un paciente: los eventos ordenados
/// por fecha descendente, con línea vertical, puntos y tarjetas. Incluye filtros
/// por año, especialidad y médico derivados de los propios eventos del paciente.
struct TimelineView: View {
    @Environment(\.modelContext) private var context

    private let paciente: Paciente

    @State private var filtroAnio: String? = nil
    @State private var filtroEspecialidad: String? = nil
    @State private var filtroMedico: String? = nil
    @State private var mostrarEditor = false

    init(paciente: Paciente) {
        self.paciente = paciente
    }

    // Eventos del paciente ordenados por fecha descendente.
    private var eventosOrdenados: [EventoMedico] {
        paciente.eventos.sorted { $0.fecha > $1.fecha }
    }

    private var eventosFiltrados: [EventoMedico] {
        eventosOrdenados.filter { ev in
            if let filtroAnio, anio(ev.fecha) != filtroAnio { return false }
            if let filtroEspecialidad,
               !HistorialTexto.iguales(ev.especialidad, filtroEspecialidad) { return false }
            if let filtroMedico,
               !HistorialTexto.iguales(ev.medico, filtroMedico) { return false }
            return true
        }
    }

    // Opciones distintas para los menús de filtro.
    private var anios: [String] {
        HistorialTexto.distintos(eventosOrdenados.map { anio($0.fecha) })
            .sorted(by: >)
    }
    private var especialidades: [String] {
        HistorialTexto.distintos(eventosOrdenados.map { $0.especialidad }).sorted()
    }
    private var medicos: [String] {
        HistorialTexto.distintos(eventosOrdenados.map { $0.medico }).sorted()
    }

    var body: some View {
        Group {
            if eventosOrdenados.isEmpty {
                ContentUnavailableView(
                    "Sin eventos",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Agrega el primer evento del historial médico de \(paciente.nombreCompleto).")
                )
            } else if eventosFiltrados.isEmpty {
                ContentUnavailableView(
                    "Sin coincidencias",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text("Ningún evento coincide con los filtros seleccionados.")
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(eventosFiltrados.enumerated()), id: \.element.id) { idx, ev in
                            FilaTimeline(evento: ev,
                                         esUltima: idx == eventosFiltrados.count - 1)
                        }
                    }
                    .padding(.horizontal, Tema.espacio)
                    .padding(.vertical, Tema.espacio)
                }
            }
        }
        .navigationTitle("Historial")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                menuFiltros
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    mostrarEditor = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $mostrarEditor) {
            EventoEditorView(paciente: paciente)
        }
    }

    private var menuFiltros: some View {
        Menu {
            if !anios.isEmpty {
                Menu("Año") {
                    Button("Todos") { filtroAnio = nil }
                    ForEach(anios, id: \.self) { a in
                        Button {
                            filtroAnio = a
                        } label: {
                            if filtroAnio == a { Label(a, systemImage: "checkmark") }
                            else { Text(a) }
                        }
                    }
                }
            }
            if !especialidades.isEmpty {
                Menu("Especialidad") {
                    Button("Todas") { filtroEspecialidad = nil }
                    ForEach(especialidades, id: \.self) { e in
                        Button {
                            filtroEspecialidad = e
                        } label: {
                            if filtroEspecialidad == e { Label(e, systemImage: "checkmark") }
                            else { Text(e) }
                        }
                    }
                }
            }
            if !medicos.isEmpty {
                Menu("Médico") {
                    Button("Todos") { filtroMedico = nil }
                    ForEach(medicos, id: \.self) { m in
                        Button {
                            filtroMedico = m
                        } label: {
                            if filtroMedico == m { Label(m, systemImage: "checkmark") }
                            else { Text(m) }
                        }
                    }
                }
            }
            Divider()
            Button("Quitar filtros", role: .destructive) {
                filtroAnio = nil
                filtroEspecialidad = nil
                filtroMedico = nil
            }
            .disabled(filtroAnio == nil && filtroEspecialidad == nil && filtroMedico == nil)
        } label: {
            Image(systemName: hayFiltro
                  ? "line.3.horizontal.decrease.circle.fill"
                  : "line.3.horizontal.decrease.circle")
        }
    }

    private var hayFiltro: Bool {
        filtroAnio != nil || filtroEspecialidad != nil || filtroMedico != nil
    }

    private func anio(_ d: Date) -> String {
        String(Calendar.current.component(.year, from: d))
    }
}

// MARK: - Fila de la línea de tiempo

private struct FilaTimeline: View {
    let evento: EventoMedico
    let esUltima: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Columna de línea + punto.
            VStack(spacing: 0) {
                Circle()
                    .fill(Tema.acento)
                    .frame(width: 12, height: 12)
                    .padding(.top, 6)
                if !esUltima {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 12)

            tarjeta
                .padding(.bottom, Tema.espacio)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var tarjeta: some View {
        if let reclamo = evento.reclamoRelacionado {
            NavigationLink {
                ReclamoDetailView(reclamo: reclamo)
            } label: {
                contenido
            }
            .buttonStyle(.plain)
        } else {
            contenido
        }
    }

    private var contenido: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(Formato.fecha(evento.fecha))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if evento.creadoAutomaticamente {
                    Text("auto")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Tema.acento.opacity(0.15))
                        .foregroundStyle(Tema.acento)
                        .clipShape(Capsule())
                }
                if evento.reclamoRelacionado != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Text(evento.titulo.isEmpty ? "Sin título" : evento.titulo)
                .font(.headline)
                .foregroundStyle(.primary)

            if !subtitulo.isEmpty {
                Text(subtitulo)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !evento.diagnostico.isEmpty {
                Text(evento.diagnostico)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Tema.espacio)
        .background(Tema.tarjeta)
        .clipShape(RoundedRectangle(cornerRadius: Tema.radio, style: .continuous))
    }

    // "Médico · Especialidad" omitiendo los vacíos.
    private var subtitulo: String {
        [evento.medico, evento.especialidad]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}
