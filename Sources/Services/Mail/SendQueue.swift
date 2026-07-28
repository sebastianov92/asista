import Foundation
import SwiftData
import Network
import BackgroundTasks

// Cola de envío persistente (§8.5). Los Envio con estado .pendiente se reintentan
// al recuperar conectividad y en segundo plano, con backoff exponencial.

@MainActor
final class SendQueue: ObservableObject {
    static let bgTaskID = "com.sebastian.Asista.envio.retry"
    static let maxIntentos = 5
    /// Espera antes del siguiente intento, indexada por intentos ya realizados − 1.
    static let backoff: [TimeInterval] = [30, 120, 600, 3600]

    /// Referencia para el handler de BGTask (registrado antes del launch, fuera del main actor).
    nonisolated(unsafe) static weak var shared: SendQueue?

    @Published var conectado = true
    @Published var pendientes = 0

    private let container: ModelContainer
    private var settings: AppSettings?
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "asista.net.monitor")
    private var iniciado = false

    nonisolated init(container: ModelContainer) {
        self.container = container
        SendQueue.shared = self
    }

    /// Debe llamarse en el arranque de la app (App.init), antes de terminar el launch.
    nonisolated static func registrarHandler() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: bgTaskID, using: nil) { task in
            guard let task = task as? BGProcessingTask else { return }
            Task { @MainActor in
                await SendQueue.shared?.procesar()
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { task.setTaskCompleted(success: false) }
        }
    }

    func iniciar(settings: AppSettings) {
        self.settings = settings
        guard !iniciado else { return }
        iniciado = true

        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                let ahoraConectado = path.status == .satisfied
                let recupero = !self.conectado && ahoraConectado
                self.conectado = ahoraConectado
                if recupero { await self.procesar() }
            }
        }
        monitor.start(queue: monitorQueue)

        // Rescatar envíos que quedaron "enviando" por una interrupción.
        rescatarInterrumpidos()
        Task { await procesar() }
    }

    private var ctx: ModelContext { container.mainContext }

    private func rescatarInterrumpidos() {
        let desc = FetchDescriptor<Envio>()
        guard let todos = try? ctx.fetch(desc) else { return }
        for e in todos where e.estado == .enviando {
            e.estado = .pendiente
        }
        try? ctx.save()
        actualizarConteo()
    }

    func actualizarConteo() {
        let todos = (try? ctx.fetch(FetchDescriptor<Envio>())) ?? []
        pendientes = todos.filter { $0.estado == .pendiente }.count
    }

    /// Procesa los envíos pendientes cuyo backoff ya venció.
    func procesar() async {
        guard let settings, conectado else { return }
        // Solo SMTP puede reintentar sin UI.
        guard KeychainStore.hayCredenciales, !settings.preferirComposer else { return }

        let todos = (try? ctx.fetch(FetchDescriptor<Envio>(sortBy: [SortDescriptor(\.fecha)]))) ?? []
        let pend = todos.filter { $0.estado == .pendiente }

        let ahora = Date()
        for envio in pend {
            guard envio.intentos < Self.maxIntentos else { envio.estado = .fallido; continue }
            let idx = min(max(envio.intentos - 1, 0), Self.backoff.count - 1)
            let espera = envio.intentos == 0 ? 0 : Self.backoff[idx]
            guard ahora.timeIntervalSince(envio.fecha) >= espera else { continue }
            await EnvioCoordinator.reintentar(envio, ctx: ctx, settings: settings)
        }
        try? ctx.save()
        actualizarConteo()
        programarBGTask()
    }

    // MARK: - Background

    func programarBGTask() {
        let req = BGProcessingTaskRequest(identifier: Self.bgTaskID)
        req.requiresNetworkConnectivity = true
        req.earliestBeginDate = Date(timeIntervalSinceNow: 60)
        try? BGTaskScheduler.shared.submit(req)
    }
}
