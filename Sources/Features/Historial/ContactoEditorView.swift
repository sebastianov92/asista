import SwiftUI
import SwiftData

/// Alta y edición de un `Contacto` (médico o prestador) del directorio.
struct ContactoEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var contacto: Contacto
    private let esNuevo: Bool
    @State private var insertado = false

    // Espejos editables.
    @State private var nombre: String
    @State private var tipo: TipoContacto
    @State private var especialidad: String
    @State private var telefono: String
    @State private var notas: String

    init(contacto: Contacto? = nil) {
        if let contacto {
            _contacto = State(initialValue: contacto)
            esNuevo = false
            _nombre = State(initialValue: contacto.nombre)
            _tipo = State(initialValue: contacto.tipo)
            _especialidad = State(initialValue: contacto.especialidad)
            _telefono = State(initialValue: contacto.telefono)
            _notas = State(initialValue: contacto.notas)
        } else {
            _contacto = State(initialValue: Contacto())
            esNuevo = true
            _nombre = State(initialValue: "")
            _tipo = State(initialValue: .medico)
            _especialidad = State(initialValue: "")
            _telefono = State(initialValue: "")
            _notas = State(initialValue: "")
        }
    }

    var body: some View {
        contenido
            .navigationTitle(esNuevo ? "Nuevo contacto" : "Editar contacto")
            .navigationBarTitleDisplayMode(.inline)
    }

    // En alta se presenta como hoja (necesita su propia barra); en edición se
    // empuja en una pila existente. En ambos casos el Form es el mismo.
    @ViewBuilder
    private var contenido: some View {
        if esNuevo {
            NavigationStack { formulario }
        } else {
            formulario
        }
    }

    private var formulario: some View {
        Form {
            Section {
                TextField("Nombre", text: $nombre)
                    .textInputAutocapitalization(.words)
                Picker("Tipo", selection: $tipo) {
                    ForEach(TipoContacto.allCases, id: \.self) { t in
                        Text(t.etiqueta).tag(t)
                    }
                }
            }

            Section("Datos") {
                TextField("Especialidad", text: $especialidad)
                    .textInputAutocapitalization(.words)
                TextField("Teléfono", text: $telefono)
                    .keyboardType(.phonePad)
            }

            Section("Notas") {
                TextEditor(text: $notas)
                    .frame(minHeight: 100)
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancelar", role: .cancel) { cancelar() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar") { guardar() }
                    .disabled(nombre.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func guardar() {
        if esNuevo && !insertado {
            context.insert(contacto)
            insertado = true
        }
        contacto.nombre = nombre.trimmingCharacters(in: .whitespaces)
        contacto.tipo = tipo
        contacto.especialidad = especialidad.trimmingCharacters(in: .whitespaces)
        contacto.telefono = telefono.trimmingCharacters(in: .whitespaces)
        contacto.notas = notas
        try? context.save()
        dismiss()
    }

    private func cancelar() {
        if esNuevo && insertado {
            context.delete(contacto)
            try? context.save()
        }
        dismiss()
    }
}
