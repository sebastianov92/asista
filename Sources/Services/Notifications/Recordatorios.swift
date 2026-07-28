import Foundation
import UserNotifications
import SwiftData

// Recordatorios locales (§14). Se reprograman por completo en cada arranque y al
// volver a primer plano, así siempre reflejan el estado actual de los reclamos.

enum Recordatorios {
    private static let center = UNUserNotificationCenter.current()

    static func solicitarPermiso() async {
        var opciones: UNAuthorizationOptions = [.alert, .badge, .sound]
        // Alertas críticas: ignoran el silencio/Foco aun con la app cerrada.
        // Requiere el entitlement de Critical Alerts (aprobado por Apple).
        if UserDefaults.standard.bool(forKey: "alarmasCriticas") { opciones.insert(.criticalAlert) }
        _ = try? await center.requestAuthorization(options: opciones)
    }

    @MainActor
    static func reprogramar(reclamos: [Reclamo], polizas: [Poliza], settings: AppSettings) async {
        let estado = await center.notificationSettings()
        guard estado.authorizationStatus == .authorized || estado.authorizationStatus == .provisional else { return }

        center.removeAllPendingNotificationRequests()

        // 1. Seguimiento: reclamo enviado / en revisión sin respuesta a los N días.
        if settings.recordatorioSeguimientoActivo {
            let dias = settings.recordatorioSeguimientoDias
            for r in reclamos where r.estado == .enviado || r.estado == .enRevision {
                let base = r.envios.map(\.fecha).max() ?? r.fechaCreacion
                guard let fire = Calendar.current.date(byAdding: .day, value: dias, to: base), fire > Date() else { continue }
                programar(
                    id: "seg-\(r.id.uuidString)",
                    titulo: "Reclamo #\(r.numero) sin respuesta",
                    cuerpo: "Han pasado \(dias) días. Considera dar seguimiento a \(r.cobertura?.paciente?.nombreCompleto ?? "tu reclamo").",
                    fecha: fire
                )
            }
        }

        // 2. Borrador olvidado: documentos escaneados que nunca se enviaron.
        if settings.recordatorioBorradorActivo {
            let dias = settings.recordatorioBorradorDias
            for r in reclamos where r.estado == .borrador && !r.documentos.isEmpty {
                guard let fire = Calendar.current.date(byAdding: .day, value: dias, to: r.fechaCreacion), fire > Date() else { continue }
                programar(
                    id: "bor-\(r.id.uuidString)",
                    titulo: "Reclamo sin enviar",
                    cuerpo: "El reclamo #\(r.numero) tiene documentos pero sigue en borrador.",
                    fecha: fire
                )
            }
        }

        // 3. Vigencia de póliza próxima a vencer (aviso 30 días antes).
        for p in polizas {
            guard let hasta = p.vigenciaHasta,
                  let aviso = Calendar.current.date(byAdding: .day, value: -30, to: hasta),
                  aviso > Date() else { continue }
            programar(
                id: "pol-\(p.id.uuidString)",
                titulo: "Póliza por vencer",
                cuerpo: "\(p.nombreVisible) vence el \(Formato.fechaISO(hasta)).",
                fecha: aviso
            )
        }
    }

    private static func programar(id: String, titulo: String, cuerpo: String, fecha: Date) {
        let content = UNMutableNotificationContent()
        content.title = titulo
        content.body = cuerpo
        content.sound = .default

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fecha)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}
