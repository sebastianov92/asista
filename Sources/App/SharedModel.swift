import Foundation
import SwiftData

// Contenedor SwiftData único, compartido por la app y por los App Intents.
// Aquí vive también la lógica opcional de CloudKit (§Fase 4): si el usuario la
// activa y el entitlement de iCloud está disponible, se usa; si no, cae a local
// sin romper nada.

enum SharedModel {
    static let schema = Schema([
        Aseguradora.self, FormularioEnBlanco.self, Poliza.self,
        Destinatario.self, Paciente.self, Cobertura.self, Reclamo.self,
        Documento.self, PaginaEscaneada.self, Envio.self,
        PlantillaCorreo.self, EventoMedico.self, Contacto.self, Medicamento.self,
        TomaMedicamento.self,
    ])

    static let container: ModelContainer = construir()

    private static func construir() -> ModelContainer {
        let quiereCloud = UserDefaults.standard.bool(forKey: "iCloudActivo")

        if quiereCloud {
            // Requiere entitlement de iCloud/CloudKit + cuenta de desarrollador.
            // Si falta, la creación lanza y caemos a almacenamiento local.
            let cloudConfig = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .automatic
            )
            if let c = try? ModelContainer(for: schema, configurations: cloudConfig) {
                return c
            }
            // Falló CloudKit (sin entitlement): continuar en local.
        }

        let localConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: localConfig)
        } catch {
            fatalError("No se pudo crear el contenedor SwiftData: \(error)")
        }
    }
}
