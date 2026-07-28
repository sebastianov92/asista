import SwiftUI
import SwiftData
import PhotosUI
import UIKit

/// Alta y edición de un `Paciente`. Trabaja sobre un borrador insertado en el
/// contexto; en cancelar se descarta si era nuevo.
struct PacienteEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var paciente: Paciente
    private let esNuevo: Bool
    @State private var insertado = false

    @State private var seleccionFoto: PhotosPickerItem?

    init(paciente: Paciente? = nil) {
        if let paciente {
            _paciente = State(initialValue: paciente)
            esNuevo = false
        } else {
            _paciente = State(initialValue: Paciente())
            esNuevo = true
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                seccionFoto
                seccionDatos
                seccionMedico
                EditableStringList(title: "Alergias", items: $paciente.alergias, placeholder: "Nueva alergia")
                EditableStringList(title: "Condiciones crónicas", items: $paciente.condicionesCronicas, placeholder: "Nueva condición")
                EditableStringList(title: "Medicación habitual", items: $paciente.medicacionHabitual, placeholder: "Nuevo medicamento")
                seccionNotas
            }
            .navigationTitle(esNuevo ? "Nuevo paciente" : "Editar paciente")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar", role: .cancel) { cancelar() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { guardar() }
                        .disabled(paciente.nombres.trimmingCharacters(in: .whitespaces).isEmpty &&
                                  paciente.apellidos.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if esNuevo && !insertado {
                    context.insert(paciente)
                    insertado = true
                }
            }
            .onChange(of: seleccionFoto) { _, nuevo in
                Task { await cargarFoto(nuevo) }
            }
        }
    }

    // MARK: - Secciones

    private var seccionFoto: some View {
        Section {
            HStack {
                Spacer()
                VStack(spacing: 12) {
                    InicialesAvatar(nombre: paciente.nombreCompleto, fotoData: paciente.fotoData, lado: 96)
                    PhotosPicker(selection: $seleccionFoto, matching: .images) {
                        Text(paciente.fotoData == nil ? "Agregar foto" : "Cambiar foto")
                    }
                    if paciente.fotoData != nil {
                        Button("Quitar foto", role: .destructive) {
                            paciente.fotoData = nil
                            seleccionFoto = nil
                        }
                        .font(.caption)
                    }
                }
                Spacer()
            }
            .listRowBackground(Color.clear)
        }
    }

    private var seccionDatos: some View {
        Section("Datos") {
            TextField("Nombres", text: $paciente.nombres)
            TextField("Apellidos", text: $paciente.apellidos)
            TextField("Cédula", text: $paciente.cedula)
                .keyboardType(.numbersAndPunctuation)
            Picker("Parentesco", selection: $paciente.parentesco) {
                ForEach(Parentesco.allCases, id: \.self) { p in
                    Text(p.etiqueta).tag(p)
                }
            }
            FechaOpcionalRow(titulo: "Fecha de nacimiento", fecha: $paciente.fechaNacimiento)
        }
    }

    private var seccionMedico: some View {
        Section("Salud") {
            TextField("Tipo de sangre (ej. O+)", text: $paciente.tipoSangre)
                .textInputAutocapitalization(.characters)
        }
    }

    private var seccionNotas: some View {
        Section("Notas médicas") {
            TextEditor(text: $paciente.notasMedicas)
                .frame(minHeight: 100)
        }
    }

    // MARK: - Acciones

    private func cargarFoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        if let data = try? await item.loadTransferable(type: Data.self) {
            let comprimida = Self.reescalar(data) ?? data
            await MainActor.run { paciente.fotoData = comprimida }
        }
    }

    private static func reescalar(_ data: Data, ladoMax: CGFloat = 512) -> Data? {
        guard let ui = UIImage(data: data) else { return nil }
        let lado = max(ui.size.width, ui.size.height)
        guard lado > ladoMax else { return ui.jpegData(compressionQuality: 0.8) }
        let escala = ladoMax / lado
        let nuevoTam = CGSize(width: ui.size.width * escala, height: ui.size.height * escala)
        let renderer = UIGraphicsImageRenderer(size: nuevoTam)
        let img = renderer.image { _ in ui.draw(in: CGRect(origin: .zero, size: nuevoTam)) }
        return img.jpegData(compressionQuality: 0.8)
    }

    private func guardar() {
        if esNuevo && !insertado {
            context.insert(paciente)
        }
        try? context.save()
        dismiss()
    }

    private func cancelar() {
        if esNuevo && insertado {
            context.delete(paciente)
            try? context.save()
        }
        dismiss()
    }
}
