import Foundation
import UserNotifications

// Alarmas de medicación. Programa una notificación por cada toma desde
// fechaInicio, cada `cadaHoras`, durante `duracionDias`.
//
// LÍMITE DE iOS: una app de terceros NO puede crear una alarma del sistema que
// siempre ignore el silencio con la app cerrada, salvo con el entitlement
// "Critical Alerts" (aprobado por Apple). Aquí usamos:
//   - nivel time-sensitive (rompe Foco/No molestar),
//   - sonido de alarma propio (alarma.caf, ~25s),
//   - y en primer plano un loop de audio con AVAudioSession .playback que sí
//     ignora el switch de silencio (ver AlarmaCoordinator).
// Si el usuario activa Critical Alerts (con su cuenta dev), usamos .critical.

enum AlarmaScheduler {
    static let categoria = "MEDICACION"
    private static let center = UNUserNotificationCenter.current()

    /// Máximo de tomas futuras a programar por medicamento (iOS limita ~64 pendientes/app).
    private static let maxPorMed = 16
    private static let maxGlobal = 60

    static let maxSnooze = 3

    static func registrarCategoria() {
        let tomar = UNNotificationAction(identifier: "TOMAR", title: "Ya la tomé", options: [])
        let posponer = UNNotificationAction(identifier: "POSPONER", title: "Posponer 10 min", options: [])
        let saltar = UNNotificationAction(identifier: "SALTAR", title: "Saltar esta toma", options: [.destructive])
        let cat = UNNotificationCategory(identifier: categoria, actions: [tomar, posponer, saltar],
                                         intentIdentifiers: [], options: [])
        center.setNotificationCategories([cat])
    }

    /// Cancela y reprograma todas las alarmas de medicación.
    @MainActor
    static func reprogramar(_ medicamentos: [Medicamento]) async {
        let estado = await center.notificationSettings()
        guard estado.authorizationStatus == .authorized || estado.authorizationStatus == .provisional else { return }

        // Borrar las de medicación previas (id con prefijo "med-").
        let pend = await center.pendingNotificationRequests()
        let viejas = pend.map(\.identifier).filter { $0.hasPrefix("med-") }
        center.removePendingNotificationRequests(withIdentifiers: viejas)

        let ahora = Date()
        var total = 0

        for med in medicamentos where med.activa {
            guard med.cadaHoras > 0 else { continue }
            let intervalo = TimeInterval(med.cadaHoras) * 3600
            let fin = med.fechaFin

            // Avanzar hasta la próxima toma >= ahora.
            var toma = med.fechaInicio
            if toma < ahora {
                let saltos = (ahora.timeIntervalSince(toma) / intervalo).rounded(.up)
                toma = toma.addingTimeInterval(saltos * intervalo)
            }

            var puestas = 0
            while puestas < maxPorMed && total < maxGlobal {
                if let fin, toma > fin { break }
                programarToma(med, fecha: toma, indice: puestas)
                puestas += 1; total += 1
                toma = toma.addingTimeInterval(intervalo)
            }
        }
    }

    private static func programarToma(_ med: Medicamento, fecha: Date, indice: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Hora de tu medicamento"
        content.body = med.dosis.isEmpty ? med.nombre : "\(med.dosis) — \(med.nombre)"
        if !med.instrucciones.isEmpty { content.subtitle = med.instrucciones }
        content.categoryIdentifier = categoria
        content.interruptionLevel = UserDefaults.standard.bool(forKey: "alarmasCriticas") ? .critical : .timeSensitive
        content.userInfo = [
            "medID": med.id.uuidString,
            "nombre": med.nombre,
            "dosis": med.dosis,
            "instrucciones": med.instrucciones,
        ]
        content.sound = sonido(med)

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fecha)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let id = "med-\(med.id.uuidString)-\(indice)"
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    /// Pospone una toma (acción "Posponer") con tope de reintentos.
    /// Devuelve false si ya se alcanzó el máximo (no reprograma).
    @discardableResult
    static func posponer(userInfo: [AnyHashable: Any], minutos: Int = 10) -> Bool {
        let cuenta = (userInfo["snoozeCount"] as? Int ?? 0) + 1
        guard cuenta <= maxSnooze else { return false }   // snooze inteligente: tope

        var info = userInfo
        info["snoozeCount"] = cuenta

        let content = UNMutableNotificationContent()
        content.title = "Recordatorio de medicamento"
        content.body = (userInfo["dosis"] as? String).flatMap { $0.isEmpty ? nil : "\($0) — \(userInfo["nombre"] as? String ?? "")" }
            ?? (userInfo["nombre"] as? String ?? "Toma tu medicamento")
        content.subtitle = "Pospuesto \(cuenta)/\(maxSnooze)"
        content.categoryIdentifier = categoria
        content.interruptionLevel = .timeSensitive
        content.userInfo = info
        content.sound = sonidoAlarma()

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(minutos * 60), repeats: false)
        let id = "med-snooze-\(UUID().uuidString)"
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        return true
    }

    private static func sonido(_ med: Medicamento) -> UNNotificationSound {
        guard med.sonarComoAlarma else { return .default }
        return sonidoAlarma()
    }

    /// Sonido de alarma. Con "alarmasCriticas" (entitlement Critical Alerts) suena
    /// fuerte ignorando el silencio aun con la app cerrada.
    private static func sonidoAlarma() -> UNNotificationSound {
        if UserDefaults.standard.bool(forKey: "alarmasCriticas") {
            return .criticalSoundNamed(UNNotificationSoundName("alarma.caf"), withAudioVolume: 1.0)
        }
        return UNNotificationSound(named: UNNotificationSoundName("alarma.caf"))
    }
}
