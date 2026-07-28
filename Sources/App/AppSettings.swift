import Foundation
import SwiftUI

// Preferencias NO sensibles (§12: nada sensible en UserDefaults). Las credenciales
// SMTP viven en Keychain; aquí solo ajustes de comportamiento.

@MainActor
final class AppSettings: ObservableObject {
    @AppStorage("faceIDActivo") var faceIDActivo: Bool = true
    /// Segundos en segundo plano antes de exigir Face ID de nuevo.
    @AppStorage("umbralBloqueoSegundos") var umbralBloqueoSegundos: Int = 60
    @AppStorage("copiaPropiaActiva") var copiaPropiaActiva: Bool = true
    @AppStorage("preferirComposer") var preferirComposer: Bool = false

    @AppStorage("preajustePorDefectoRaw") private var preajustePorDefectoRaw: String = PreajusteCalidad.media.rawValue
    var preajustePorDefecto: PreajusteCalidad {
        get { PreajusteCalidad(rawValue: preajustePorDefectoRaw) ?? .media }
        set { preajustePorDefectoRaw = newValue.rawValue }
    }

    @AppStorage("patronNombres") var patronNombres: String = "{fecha}_{paciente}_{orden}-{tipo}"

    /// Umbral de peso total del correo antes de recomprimir automáticamente (§6.2).
    @AppStorage("umbralTamanoMB") var umbralTamanoMB: Int = 15

    // Recordatorios (§14) — se aplican en Fase 3, se guardan desde ya.
    @AppStorage("recordatorioSeguimientoActivo") var recordatorioSeguimientoActivo: Bool = true
    @AppStorage("recordatorioSeguimientoDias") var recordatorioSeguimientoDias: Int = 15
    @AppStorage("recordatorioBorradorActivo") var recordatorioBorradorActivo: Bool = true
    @AppStorage("recordatorioBorradorDias") var recordatorioBorradorDias: Int = 7

    /// Dirección propia, derivada de las credenciales SMTP (para copia y "From").
    var miEmail: String { KeychainStore.leer()?.usuario ?? "" }

    var umbralTamanoBytes: Int { umbralTamanoMB * 1024 * 1024 }
}
