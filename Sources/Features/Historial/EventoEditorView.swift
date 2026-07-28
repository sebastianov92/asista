import SwiftUI
import SwiftData

/// Alta y edición de un `EventoMedico` del historial de un paciente.
/// Los campos de médico y especialidad usan autocompletado alimentado por los
/// contactos y eventos existentes. Al guardar, registra al médico en el
/// directorio de contactos si aún no existe (best-effort).
struct EventoEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query private var contactos: [Contacto]
    @Query private var eventos: [EventoMedico]

    private let paciente: Paciente
    @State private var evento: EventoMedico
    private let esNuevo: Bool
    @State private var insertado = false

    // Espejo editable de los campos (para poder cancelar sin tocar el modelo
    // cuando es una edición existente, aunque aquí editamos el objeto directo).
    @State private var fecha: Date
    @State private var titulo: String
    @State private var especialidad: String
    @State private var medico: String
    @State private var diagnostico: String
    @State private var descripcion: String

    init(paciente: Paciente, evento: EventoMedico? = nil) {
        self.paciente = paciente
        if let evento {
            _evento = State(initialValue: evento)
            esNuevo = false
            _fecha = State(initialValue: evento.fecha)
            _titulo = State(initialValue: evento.titulo)
            _especialidad = State(initialValue: evento.especialidad)
            _medico = State(initialValue: evento.medico)
            _diagnostico = State(initialValue: evento.diagnostico)
            _descripcion = State(initialValue: evento.descripcion)
        } else {
            _evento = State(initialValue: EventoMedico())
            esNuevo = true
            _fecha = State(initialValue: Date())
            _titulo = State(initialValue: "")
            _especialidad = State(initialValue: "")
            _medico = State(initialValue: "")
            _diagnostico = State(initialValue: "")
            _descripcion = State(initialValue: "")
        }
    }

    // Sugerencias derivadas de contactos + eventos existentes.
    private var sugerenciasMedico: [String] {
        HistorialTexto.distintos(
            contactos.filter { $0.tipo == .medico }.map { $0.nombre }
            + eventos.map { $0.medico }
        )
    }

    private var sugerenciasEspecialidad: [String] {
        HistorialTexto.distintos(
            contactos.map { $0.especialidad } + eventos.map { $0.especialidad }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Evento") {
                    DatePicker("Fecha", selection: $fecha, displayedComponents: .date)
                    TextField("Título", text: $titulo)
                        .textInputAutocapitalization(.sentences)
                }

                Section("Atención") {
                    AutocompleteField(titulo: "Especialidad",
                                      texto: $especialidad,
                                      sugerencias: sugerenciasEspecialidad)
                    AutocompleteField(titulo: "Médico",
                                      texto: $medico,
                                      sugerencias: sugerenciasMedico)
                    TextField("Diagnóstico", text: $diagnostico)
                        .textInputAutocapitalization(.sentences)
                }

                Section("Descripción") {
                    TextEditor(text: $descripcion)
                        .frame(minHeight: 120)
                }
            }
            .navigationTitle(esNuevo ? "Nuevo evento" : "Editar evento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar", role: .cancel) { cancelar() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { guardar() }
                        .disabled(titulo.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func guardar() {
        if esNuevo && !insertado {
            context.insert(evento)
            insertado = true
        }

        evento.fecha = fecha
        evento.titulo = titulo.trimmingCharacters(in: .whitespaces)
        evento.especialidad = especialidad.trimmingCharacters(in: .whitespaces)
        evento.medico = medico.trimmingCharacters(in: .whitespaces)
        evento.diagnostico = diagnostico.trimmingCharacters(in: .whitespaces)
        evento.descripcion = descripcion

        if esNuevo {
            evento.paciente = paciente
            evento.creadoAutomaticamente = false
        }

        upsertContactoMedico()

        try? context.save()
        dismiss()
    }

    /// Si el médico tecleado no está en el directorio, lo agrega como Contacto.
    private func upsertContactoMedico() {
        let nombre = medico.trimmingCharacters(in: .whitespaces)
        guard !nombre.isEmpty else { return }

        if let existente = contactos.first(where: {
            HistorialTexto.iguales($0.nombre, nombre)
        }) {
            // Completa especialidad si faltaba.
            let esp = especialidad.trimmingCharacters(in: .whitespaces)
            if existente.especialidad.isEmpty && !esp.isEmpty {
                existente.especialidad = esp
            }
        } else {
            let nuevo = Contacto(nombre: nombre, tipo: .medico)
            nuevo.especialidad = especialidad.trimmingCharacters(in: .whitespaces)
            context.insert(nuevo)
        }
    }

    private func cancelar() {
        if esNuevo && insertado {
            context.delete(evento)
            try? context.save()
        }
        dismiss()
    }
}
