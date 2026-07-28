import SwiftUI
import SwiftData
import PhotosUI
import UIKit

/// Alta y edición de una `Aseguradora`, con plantilla de correo inline opcional.
struct AseguradoraEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var aseguradora: Aseguradora
    private let esNueva: Bool
    @State private var insertada = false

    @State private var seleccionLogo: PhotosPickerItem?
    @State private var color: Color = Tema.acento
    @State private var usarPlantilla = false

    init(aseguradora: Aseguradora? = nil) {
        if let aseguradora {
            _aseguradora = State(initialValue: aseguradora)
            _color = State(initialValue: aseguradora.colorHex.flatMap { Color(hex: $0) } ?? Tema.acento)
            _usarPlantilla = State(initialValue: aseguradora.plantilla != nil)
            esNueva = false
        } else {
            _aseguradora = State(initialValue: Aseguradora())
            esNueva = true
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Datos") {
                    TextField("Nombre", text: $aseguradora.nombre)
                    ColorPicker("Color", selection: $color, supportsOpacity: false)
                    TextField("Hex (#RRGGBB)", text: Binding(
                        get: { aseguradora.colorHex ?? "" },
                        set: { aseguradora.colorHex = $0.isEmpty ? nil : $0 }
                    ))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                }

                Section("Logo") {
                    HStack {
                        if let data = aseguradora.logoData, let ui = UIImage(data: data) {
                            Image(uiImage: ui)
                                .resizable().scaledToFit()
                                .frame(width: 48, height: 48)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        PhotosPicker(selection: $seleccionLogo, matching: .images) {
                            Text(aseguradora.logoData == nil ? "Agregar logo" : "Cambiar logo")
                        }
                        if aseguradora.logoData != nil {
                            Spacer()
                            Button("Quitar", role: .destructive) {
                                aseguradora.logoData = nil
                                seleccionLogo = nil
                            }
                            .font(.caption)
                        }
                    }
                }

                Section("Notas") {
                    TextEditor(text: $aseguradora.notas)
                        .frame(minHeight: 80)
                }

                seccionPlantilla
            }
            .navigationTitle(esNueva ? "Nueva aseguradora" : "Editar aseguradora")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar", role: .cancel) { cancelar() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { guardar() }
                        .disabled(aseguradora.nombre.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if esNueva && !insertada {
                    context.insert(aseguradora)
                    insertada = true
                }
            }
            .onChange(of: color) { _, nuevo in
                aseguradora.colorHex = Self.hex(from: nuevo)
            }
            .onChange(of: seleccionLogo) { _, nuevo in
                Task { await cargarLogo(nuevo) }
            }
        }
    }

    @ViewBuilder
    private var seccionPlantilla: some View {
        Section {
            Toggle("Plantilla de esta aseguradora", isOn: Binding(
                get: { usarPlantilla },
                set: { activar in
                    usarPlantilla = activar
                    if activar {
                        if aseguradora.plantilla == nil {
                            let p = PlantillaCorreo(nombre: "Plantilla \(aseguradora.nombre)")
                            context.insert(p)
                            aseguradora.plantilla = p
                        }
                    } else if let p = aseguradora.plantilla {
                        aseguradora.plantilla = nil
                        context.delete(p)
                    }
                }
            ))

            if usarPlantilla, let plantilla = aseguradora.plantilla {
                TextField("Nombre de la plantilla", text: Binding(
                    get: { plantilla.nombre }, set: { plantilla.nombre = $0 }
                ))
                TextField("Asunto", text: Binding(
                    get: { plantilla.asunto }, set: { plantilla.asunto = $0 }
                ))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Cuerpo").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: Binding(
                        get: { plantilla.cuerpo }, set: { plantilla.cuerpo = $0 }
                    ))
                    .frame(minHeight: 120)
                }
            }
        } header: {
            Text("Plantilla de correo")
        } footer: {
            Text("Aplica a todas las pólizas de esta aseguradora salvo que la póliza tenga la suya.")
        }
    }

    // MARK: - Acciones

    private func cargarLogo(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        if let data = try? await item.loadTransferable(type: Data.self) {
            await MainActor.run { aseguradora.logoData = data }
        }
    }

    private static func hex(from color: Color) -> String {
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        let ri = Int((r * 255).rounded()), gi = Int((g * 255).rounded()), bi = Int((b * 255).rounded())
        return String(format: "#%02X%02X%02X", ri, gi, bi)
    }

    private func guardar() {
        if esNueva && !insertada {
            context.insert(aseguradora)
        }
        try? context.save()
        dismiss()
    }

    private func cancelar() {
        if esNueva && insertada {
            if let p = aseguradora.plantilla { context.delete(p) }
            context.delete(aseguradora)
            try? context.save()
        }
        dismiss()
    }
}
