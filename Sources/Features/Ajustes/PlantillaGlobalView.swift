import SwiftUI
import SwiftData

// Editor de la plantilla global con vista previa e inserción de tokens (§9).

struct PlantillaGlobalView: View {
    @Environment(\.modelContext) private var ctx
    @Query(filter: #Predicate<PlantillaCorreo> { $0.esGlobalPorDefecto == true })
    private var globales: [PlantillaCorreo]

    @State private var asunto = ""
    @State private var cuerpo = ""
    @State private var campoActivo: Campo = .cuerpo
    enum Campo { case asunto, cuerpo }

    private var plantilla: PlantillaCorreo? { globales.first }

    var body: some View {
        Form {
            Section("Asunto") {
                TextField("Asunto", text: $asunto, axis: .vertical)
                    .onTapGesture { campoActivo = .asunto }
            }
            Section("Cuerpo") {
                TextEditor(text: $cuerpo)
                    .frame(minHeight: 200)
                    .onTapGesture { campoActivo = .cuerpo }
            }
            Section("Insertar token") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130))], spacing: 8) {
                    ForEach(TemplateEngine.tokensDisponibles, id: \.self) { t in
                        Button("{{\(t)}}") { insertar(t) }
                            .buttonStyle(.bordered).font(.caption2)
                    }
                }
            }
            Section("Vista previa (datos de ejemplo)") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(TemplateEngine.expandir(asunto, tokens: ejemplo))
                        .font(.callout.weight(.semibold))
                    Divider()
                    Text(TemplateEngine.expandir(cuerpo, tokens: ejemplo))
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Plantilla global")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: cargar)
        .onDisappear(perform: guardar)
    }

    private func cargar() {
        asunto = plantilla?.asunto ?? TemplateEngine.asuntoPorDefecto
        cuerpo = plantilla?.cuerpo ?? TemplateEngine.cuerpoPorDefecto
    }

    private func guardar() {
        if let p = plantilla {
            p.asunto = asunto
            p.cuerpo = cuerpo
        } else {
            let nueva = PlantillaCorreo(nombre: "Plantilla por defecto", asunto: asunto, cuerpo: cuerpo)
            nueva.esGlobalPorDefecto = true
            ctx.insert(nueva)
        }
        try? ctx.save()
    }

    private func insertar(_ token: String) {
        switch campoActivo {
        case .asunto: asunto += "{{\(token)}}"
        case .cuerpo: cuerpo += "{{\(token)}}"
        }
    }

    private let ejemplo: [String: String] = [
        "paciente": "Juan Pérez", "paciente_cedula": "0102030405", "parentesco": "Titular",
        "aseguradora": "Seguros Salud", "poliza": "Corporativa", "certificado": "C-88",
        "fecha_evento": "2026-07-27", "fecha_hoy": "2026-07-28", "diagnostico": "Faringitis",
        "medico": "Dra. Ruiz", "prestador": "Clínica Central", "monto_total": "120.00",
        "numero_reclamo": "5", "cantidad_documentos": "3",
        "lista_documentos": "• Receta\n• Factura del médico — USD 120.00\n• Resultado de exámenes",
    ]
}
