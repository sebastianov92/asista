import Foundation
import SwiftData

// Siembra mínima: una plantilla global por defecto si no existe ninguna.

enum Seeder {
    @MainActor
    static func sembrarSiVacio(_ ctx: ModelContext) async {
        let fetch = FetchDescriptor<PlantillaCorreo>(
            predicate: #Predicate { $0.esGlobalPorDefecto == true }
        )
        let existentes = (try? ctx.fetch(fetch)) ?? []
        guard existentes.isEmpty else { return }

        let global = PlantillaCorreo(
            nombre: "Plantilla por defecto",
            asunto: TemplateEngine.asuntoPorDefecto,
            cuerpo: TemplateEngine.cuerpoPorDefecto
        )
        global.esGlobalPorDefecto = true
        ctx.insert(global)
        try? ctx.save()
    }
}
