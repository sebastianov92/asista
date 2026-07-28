import SwiftUI
import SwiftData
import UIKit

// Subvistas reutilizables internas para los editores de Pacientes y Seguros.
// Todo vive en el mismo módulo, así que estas se usan sin imports adicionales.

// MARK: - Lista editable de textos

/// Sección de un `Form` para editar un `[String]` (alergias, condiciones, etc.).
/// Cada fila es editable en sitio; se agregan y eliminan libremente.
struct EditableStringList: View {
    let title: String
    @Binding var items: [String]
    var placeholder: String = "Agregar…"

    @State private var nuevo: String = ""

    var body: some View {
        Section(title) {
            ForEach(items.indices, id: \.self) { i in
                TextField("", text: Binding(
                    get: { i < items.count ? items[i] : "" },
                    set: { if i < items.count { items[i] = $0 } }
                ))
            }
            .onDelete { items.remove(atOffsets: $0) }

            HStack {
                TextField(placeholder, text: $nuevo)
                Button(action: agregar) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Tema.acento)
                }
                .buttonStyle(.borderless)
                .disabled(nuevo.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func agregar() {
        let t = nuevo.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        items.append(t)
        nuevo = ""
    }
}

// MARK: - Campo de monto (Decimal opcional)

/// Campo de texto para importes en USD. Bindea a `Decimal?`; vacío = nil.
struct DecimalField: View {
    let titulo: String
    @Binding var valor: Decimal?
    var placeholder: String = "0.00"

    @State private var texto: String = ""

    var body: some View {
        HStack {
            Text(titulo)
            Spacer()
            Text("USD")
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $texto)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 120)
                .onAppear {
                    if texto.isEmpty, let v = valor {
                        texto = Formato.monto(v)
                    }
                }
                .onChange(of: texto) { _, nuevo in
                    valor = Self.parse(nuevo)
                }
        }
    }

    static func parse(_ s: String) -> Decimal? {
        let limpio = s
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "USD", with: "")
            .trimmingCharacters(in: .whitespaces)
        if limpio.isEmpty { return nil }
        return Decimal(string: limpio, locale: Locale(identifier: "en_US_POSIX"))
    }
}

// MARK: - Fila de fecha opcional

/// Toggle + DatePicker que guarda `nil` cuando está apagado.
struct FechaOpcionalRow: View {
    let titulo: String
    @Binding var fecha: Date?

    var body: some View {
        Toggle(titulo, isOn: Binding(
            get: { fecha != nil },
            set: { fecha = $0 ? (fecha ?? Date()) : nil }
        ))
        if fecha != nil {
            DatePicker(
                titulo,
                selection: Binding(
                    get: { fecha ?? Date() },
                    set: { fecha = $0 }
                ),
                displayedComponents: .date
            )
            .datePickerStyle(.compact)
        }
    }
}

// MARK: - Avatar con iniciales o foto

struct InicialesAvatar: View {
    let nombre: String
    var fotoData: Data?
    var lado: CGFloat = 56

    var body: some View {
        Group {
            if let data = fotoData, let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Tema.acento.opacity(0.15)
                    Text(iniciales)
                        .font(.system(size: lado * 0.38, weight: .semibold))
                        .foregroundStyle(Tema.acento)
                }
            }
        }
        .frame(width: lado, height: lado)
        .clipShape(Circle())
    }

    private var iniciales: String {
        let partes = nombre.split(separator: " ").prefix(2)
        let s = partes.compactMap { $0.first }.map(String.init).joined()
        return s.isEmpty ? "?" : s.uppercased()
    }
}

// MARK: - Chip

struct Chip: View {
    let texto: String
    var color: Color = Tema.acento

    var body: some View {
        Text(texto)
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

// MARK: - Editor de destinatarios (reutilizado en Póliza y Cobertura)

/// Edita un arreglo de `Destinatario` que vive como relación en un `@Model`.
/// Inserta/borra en el `modelContext` para mantener la integridad del grafo.
struct DestinatariosEditor: View {
    @Binding var destinatarios: [Destinatario]
    let context: ModelContext

    var body: some View {
        ForEach(destinatarios) { dest in
            VStack(alignment: .leading, spacing: 8) {
                TextField("Nombre", text: Binding(
                    get: { dest.nombre },
                    set: { dest.nombre = $0 }
                ))
                .font(.body.weight(.medium))

                TextField("correo@ejemplo.com", text: Binding(
                    get: { dest.email },
                    set: { dest.email = $0 }
                ))
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(.secondary)

                HStack {
                    Picker("Tipo", selection: Binding(
                        get: { dest.tipo },
                        set: { dest.tipo = $0 }
                    )) {
                        ForEach(TipoDestinatario.allCases, id: \.self) { t in
                            Text(t.etiqueta).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 200)

                    Spacer()

                    Toggle("Activo", isOn: Binding(
                        get: { dest.activo },
                        set: { dest.activo = $0 }
                    ))
                    .labelsHidden()
                }
            }
            .padding(.vertical, 4)
        }
        .onDelete(perform: eliminar)

        Button {
            let d = Destinatario()
            context.insert(d)
            destinatarios.append(d)
        } label: {
            Label("Agregar destinatario", systemImage: "person.badge.plus")
        }
    }

    private func eliminar(_ offsets: IndexSet) {
        let aBorrar = offsets.map { destinatarios[$0] }
        destinatarios.remove(atOffsets: offsets)
        for d in aBorrar { context.delete(d) }
    }
}
