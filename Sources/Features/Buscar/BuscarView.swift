import SwiftUI
import SwiftData

// Búsqueda global (§11): un solo campo que resuelve en un par de segundos
// sobre reclamos, pacientes, eventos médicos y el texto OCR de los documentos.
// Ej.: "¿Cuándo fue la última vez que Ana fue al alergólogo?" → buscar
// "Ana alergólogo" encuentra el evento correspondiente.

struct BuscarView: View {
    @Query private var reclamos: [Reclamo]
    @Query private var pacientes: [Paciente]
    @Query private var eventos: [EventoMedico]
    @Query private var documentos: [Documento]

    @State private var consulta = ""
    @State private var resultados = ResultadosBusqueda()

    var body: some View {
        NavigationStack {
            Group {
                if consulta.trimmingCharacters(in: .whitespaces).isEmpty {
                    PistaBusqueda()
                } else if resultados.vacio {
                    ContentUnavailableView.search(text: consulta)
                } else {
                    List {
                        seccionReclamos
                        seccionPacientes
                        seccionEventos
                        seccionDocumentos
                    }
                }
            }
            .navigationTitle("Buscar")
        }
        .searchable(
            text: $consulta,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Paciente, médico, prestador, diagnóstico…"
        )
        .onChange(of: consulta) { _, nueva in
            recalcular(nueva)
        }
    }

    private func recalcular(_ q: String) {
        resultados = BusquedaEngine.buscar(
            q,
            reclamos: reclamos,
            pacientes: pacientes,
            eventos: eventos,
            documentos: documentos
        )
    }

    // MARK: - Secciones

    @ViewBuilder private var seccionReclamos: some View {
        if !resultados.reclamos.isEmpty {
            Section("Reclamos") {
                ForEach(resultados.reclamos) { reclamo in
                    NavigationLink {
                        ReclamoDetailView(reclamo: reclamo)
                    } label: {
                        FilaReclamo(reclamo: reclamo, consulta: consulta)
                    }
                }
            }
        }
    }

    @ViewBuilder private var seccionPacientes: some View {
        if !resultados.pacientes.isEmpty {
            Section("Pacientes") {
                ForEach(resultados.pacientes) { paciente in
                    NavigationLink {
                        PacienteDetailView(paciente: paciente)
                    } label: {
                        FilaPaciente(paciente: paciente)
                    }
                }
            }
        }
    }

    @ViewBuilder private var seccionEventos: some View {
        if !resultados.eventos.isEmpty {
            Section("Eventos médicos") {
                ForEach(resultados.eventos) { evento in
                    NavigationLink {
                        destinoEvento(evento)
                    } label: {
                        FilaEvento(evento: evento)
                    }
                }
            }
        }
    }

    @ViewBuilder private var seccionDocumentos: some View {
        if !resultados.documentos.isEmpty {
            Section("Documentos (OCR)") {
                ForEach(resultados.documentos) { documento in
                    if let reclamo = documento.reclamo {
                        NavigationLink {
                            ReclamoDetailView(reclamo: reclamo)
                        } label: {
                            FilaDocumento(documento: documento, consulta: consulta)
                        }
                    } else {
                        FilaDocumento(documento: documento, consulta: consulta)
                    }
                }
            }
        }
    }

    /// Un evento enlaza a su reclamo si existe; si no, al paciente.
    @ViewBuilder private func destinoEvento(_ evento: EventoMedico) -> some View {
        if let reclamo = evento.reclamoRelacionado {
            ReclamoDetailView(reclamo: reclamo)
        } else if let paciente = evento.paciente {
            PacienteDetailView(paciente: paciente)
        } else {
            // Sin destino navegable; se muestra un aviso sencillo.
            ContentUnavailableView(
                "Sin detalle",
                systemImage: "questionmark.circle",
                description: Text("Este evento no está enlazado a un reclamo ni a un paciente.")
            )
        }
    }
}

// MARK: - Pista inicial

private struct PistaBusqueda: View {
    var body: some View {
        ContentUnavailableView {
            Label("Busca en toda tu información", systemImage: "magnifyingglass")
        } description: {
            Text("Busca por paciente, médico, prestador, diagnóstico o texto de un documento.")
        }
    }
}

// MARK: - Filas

private struct FilaReclamo: View {
    let reclamo: Reclamo
    let consulta: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: reclamo.estado.simbolo)
                .foregroundStyle(reclamo.estado.color)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(reclamo.cobertura?.paciente?.nombreCompleto ?? "Paciente")
                        .font(.body.weight(.medium))
                    Text("#\(reclamo.numero)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(reclamo.estado.etiqueta)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(reclamo.estado.color.opacity(0.15), in: Capsule())
                    .foregroundStyle(reclamo.estado.color)
                if let pista = pistaCoincidencia {
                    Text(pista)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(Formato.fechaISO(reclamo.fechaEvento))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    /// Muestra el campo donde probablemente coincidió, para dar contexto.
    private var pistaCoincidencia: String? {
        let candidatos: [(String, String)] = [
            ("Diagnóstico", reclamo.diagnostico),
            ("Prestador", reclamo.prestador),
            ("Médico", reclamo.medico),
            ("CIE-10", reclamo.codigoCIE10),
            ("Notas", reclamo.notas),
        ]
        for (etiqueta, valor) in candidatos where coincide(valor, consulta) {
            return "\(etiqueta): \(valor)"
        }
        return nil
    }
}

private struct FilaPaciente: View {
    let paciente: Paciente
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle")
                .foregroundStyle(Tema.acento)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(paciente.nombreCompleto)
                    .font(.body.weight(.medium))
                if !paciente.cedula.isEmpty {
                    Text("Cédula: \(paciente.cedula)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct FilaEvento: View {
    let evento: EventoMedico
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "stethoscope")
                .foregroundStyle(Tema.acento)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(evento.titulo.isEmpty ? "Evento médico" : evento.titulo)
                    .font(.body.weight(.medium))
                Text(subtitulo)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(Formato.fechaISO(evento.fecha))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var subtitulo: String {
        let partes = [evento.medico, evento.especialidad].filter { !$0.isEmpty }
        return partes.isEmpty ? Formato.fecha(evento.fecha) : partes.joined(separator: " · ")
    }
}

private struct FilaDocumento: View {
    let documento: Documento
    let consulta: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: documento.tipo.simbolo)
                .foregroundStyle(Tema.acento)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(documento.etiqueta)
                    .font(.body.weight(.medium))
                if let paciente = documento.reclamo?.cobertura?.paciente?.nombreCompleto {
                    Text(paciente)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !snippet.isEmpty {
                    Text(snippet)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }

    /// Extracto del OCR alrededor de la coincidencia; si no está en el OCR,
    /// cae al emisor/factura para dar contexto.
    private var snippet: String {
        let ex = BusquedaEngine.extracto(de: documento.textoOCR, termino: consulta)
        if !ex.isEmpty { return ex }
        if !documento.emisor.isEmpty { return documento.emisor }
        if !documento.numeroFactura.isEmpty { return "Factura \(documento.numeroFactura)" }
        return ""
    }
}

// MARK: - Utilidad local de coincidencia (para las pistas)

private func coincide(_ texto: String, _ consulta: String) -> Bool {
    let campo = texto.folding(
        options: [.diacriticInsensitive, .caseInsensitive],
        locale: Locale(identifier: "es_EC")
    )
    let terminos = consulta
        .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_EC"))
        .split(separator: " ")
        .map(String.init)
    guard !terminos.isEmpty else { return false }
    return terminos.contains { !$0.isEmpty && campo.contains($0) }
}
