import AppIntents
import SwiftData

// App Intents / Atajos de Siri (§Fase 4). "Oye Siri, ¿cuánto me deben?" responde
// el total pendiente de cobro; "Nuevo reclamo" abre la app.

struct ConsultarPendienteIntent: AppIntent {
    static var title: LocalizedStringResource = "¿Cuánto me deben?"
    static var description = IntentDescription("Consulta el total pendiente de cobro de tus reclamos.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let ctx = SharedModel.container.mainContext
        let reclamos = (try? ctx.fetch(FetchDescriptor<Reclamo>())) ?? []
        let p = MoneyCalc.pendiente(reclamos)
        let monto = Formato.montoUSD(p.total)
        let dialogo: IntentDialog = p.cantidad == 0
            ? "No tienes reclamos pendientes de cobro."
            : "Te deben \(monto) en \(p.cantidad) \(p.cantidad == 1 ? "reclamo" : "reclamos")."
        return .result(value: monto, dialog: dialogo)
    }
}

struct NuevoReclamoIntent: AppIntent {
    static var title: LocalizedStringResource = "Nuevo reclamo"
    static var description = IntentDescription("Abre Asista para armar un nuevo reclamo.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        // Señal para que la app abra directamente el flujo de nuevo reclamo.
        UserDefaults.standard.set(true, forKey: "abrirNuevoReclamo")
        return .result()
    }
}

struct AsistaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ConsultarPendienteIntent(),
            phrases: [
                "¿Cuánto me deben en \(.applicationName)?",
                "Pendiente de cobro en \(.applicationName)",
            ],
            shortTitle: "Pendiente de cobro",
            systemImageName: "dollarsign.circle"
        )
        AppShortcut(
            intent: NuevoReclamoIntent(),
            phrases: [
                "Nuevo reclamo en \(.applicationName)",
                "Crear reclamo en \(.applicationName)",
            ],
            shortTitle: "Nuevo reclamo",
            systemImageName: "doc.badge.plus"
        )
    }
}
