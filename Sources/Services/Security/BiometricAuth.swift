import Foundation
import LocalAuthentication

// Face ID / Touch ID para abrir la app (§12). Bloqueo al pasar a segundo plano
// con umbral configurable. El estado de bloqueo lo mantiene AppState.

@MainActor
final class BiometricAuth: ObservableObject {
    @Published var desbloqueado = false
    @Published var error: String?

    var disponible: Bool {
        var e: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &e)
    }

    var tipoTexto: String {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        switch ctx.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        default: return "código"
        }
    }

    func autenticar(motivo: String = "Desbloquea Asista para ver tus datos médicos") async {
        let ctx = LAContext()
        ctx.localizedFallbackTitle = "Usar código"
        var e: NSError?
        // .deviceOwnerAuthentication permite caer al código del dispositivo si la
        // biometría falla; así el usuario nunca queda fuera de sus datos.
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &e) else {
            // Sin biometría ni código configurado: no bloqueamos.
            desbloqueado = true
            return
        }
        do {
            let ok = try await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: motivo)
            desbloqueado = ok
            error = ok ? nil : "Autenticación fallida."
        } catch {
            self.error = "No se pudo autenticar."
            desbloqueado = false
        }
    }

    func bloquear() { desbloqueado = false }
}
