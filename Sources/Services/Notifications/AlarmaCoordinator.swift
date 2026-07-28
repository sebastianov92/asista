import Foundation
import UserNotifications
import AVFoundation
import SwiftData

// Maneja la alarma cuando llega la notificación de medicación. En primer plano
// reproduce el sonido en loop con AVAudioSession .playback, que SÍ ignora el
// switch de silencio, dando sensación de alarma real. Muestra AlarmaView.

@MainActor
final class AlarmaCoordinator: NSObject, ObservableObject {
    @Published var alarma: AlarmaInfo?
    private var player: AVAudioPlayer?

    struct AlarmaInfo: Identifiable {
        let id = UUID()
        var nombre: String
        var dosis: String
        var instrucciones: String
        var userInfo: [AnyHashable: Any]
    }

    func configurar() {
        UNUserNotificationCenter.current().delegate = self
        AlarmaScheduler.registrarCategoria()
    }

    func mostrar(_ userInfo: [AnyHashable: Any]) {
        alarma = AlarmaInfo(
            nombre: userInfo["nombre"] as? String ?? "Medicamento",
            dosis: userInfo["dosis"] as? String ?? "",
            instrucciones: userInfo["instrucciones"] as? String ?? "",
            userInfo: userInfo
        )
        reproducir()
    }

    func tome() {
        if let info = alarma?.userInfo { registrar(.tomada, info) }
        detener()
    }

    func posponer() {
        if let info = alarma?.userInfo {
            registrar(.pospuesta, info)
            AlarmaScheduler.posponer(userInfo: info)
        }
        detener()
    }

    func saltar() {
        if let info = alarma?.userInfo { registrar(.saltada, info) }
        detener()
    }

    /// Registra la toma para calcular adherencia.
    func registrar(_ estado: EstadoToma, _ userInfo: [AnyHashable: Any]) {
        guard let idStr = userInfo["medID"] as? String, let uuid = UUID(uuidString: idStr) else { return }
        let ctx = SharedModel.container.mainContext
        let meds = (try? ctx.fetch(FetchDescriptor<Medicamento>())) ?? []
        guard let med = meds.first(where: { $0.id == uuid }) else { return }
        let t = TomaMedicamento(estado: estado)
        ctx.insert(t)
        t.medicamento = med
        try? ctx.save()
    }

    private func reproducir() {
        guard let url = Bundle.main.url(forResource: "alarma", withExtension: "caf") else { return }
        do {
            // .playback ignora el switch de silencio.
            try AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            player = try AVAudioPlayer(contentsOf: url)
            player?.numberOfLoops = -1     // en loop hasta que el usuario responda
            player?.volume = 1.0
            player?.play()
        } catch { }
    }

    private func detener() {
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        alarma = nil
    }
}

extension AlarmaCoordinator: UNUserNotificationCenterDelegate {
    // Notificación mientras la app está en primer plano: mostrarla y disparar la alarma.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
        let info = notification.request.content.userInfo
        if notification.request.content.categoryIdentifier == AlarmaScheduler.categoria {
            Task { @MainActor in self.mostrar(info) }
        }
    }

    // El usuario tocó la notificación o una acción.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        let accion = response.actionIdentifier
        Task { @MainActor in
            switch accion {
            case "TOMAR":
                self.registrar(.tomada, info)
            case "POSPONER":
                self.registrar(.pospuesta, info)
                AlarmaScheduler.posponer(userInfo: info)
            case "SALTAR":
                self.registrar(.saltada, info)
            default:
                // Toque normal: abrir la pantalla de alarma.
                if response.notification.request.content.categoryIdentifier == AlarmaScheduler.categoria {
                    self.mostrar(info)
                }
            }
        }
        completionHandler()
    }
}
