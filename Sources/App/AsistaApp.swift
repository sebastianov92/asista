import SwiftUI
import SwiftData

@main
struct AsistaApp: App {
    let container: ModelContainer
    @StateObject private var settings = AppSettings()
    @StateObject private var auth = BiometricAuth()
    @StateObject private var sendQueue: SendQueue
    @StateObject private var alarmas = AlarmaCoordinator()
    @Environment(\.scenePhase) private var scenePhase

    /// Momento en que la app pasó a segundo plano, para el umbral de bloqueo.
    @State private var fondoDesde: Date?

    init() {
        // Registrar el handler de BGTask antes de terminar el launch (§8.5).
        SendQueue.registrarHandler()
        let container = SharedModel.container
        self.container = container
        _sendQueue = StateObject(wrappedValue: SendQueue(container: container))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(auth)
                .environmentObject(sendQueue)
                .environmentObject(alarmas)
                .task { await Seeder.sembrarSiVacio(container.mainContext) }
                .task { sendQueue.iniciar(settings: settings) }
                .task { alarmas.configurar() }
                .task {
                    await Recordatorios.solicitarPermiso()
                    reprogramarRecordatorios()
                    await reprogramarAlarmas()
                }
                .task {
                    if settings.faceIDActivo && auth.disponible {
                        await auth.autenticar()
                    } else {
                        auth.desbloqueado = true
                    }
                }
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, fase in
            manejarFase(fase)
            if fase == .background { sendQueue.programarBGTask() }
            if fase == .active {
                Task { await sendQueue.procesar() }
                reprogramarRecordatorios()
                Task { await reprogramarAlarmas() }
            }
        }
    }

    private func reprogramarRecordatorios() {
        let ctx = container.mainContext
        let reclamos = (try? ctx.fetch(FetchDescriptor<Reclamo>())) ?? []
        let polizas = (try? ctx.fetch(FetchDescriptor<Poliza>())) ?? []
        Task { await Recordatorios.reprogramar(reclamos: reclamos, polizas: polizas, settings: settings) }
    }

    private func reprogramarAlarmas() async {
        let ctx = container.mainContext
        let meds = (try? ctx.fetch(FetchDescriptor<Medicamento>())) ?? []
        // Tratamiento terminado → apagar sus alarmas automáticamente.
        let ahora = Date()
        var cambio = false
        for m in meds where m.activa {
            if let fin = m.fechaFin, ahora > fin { m.activa = false; cambio = true }
        }
        if cambio { try? ctx.save() }
        await AlarmaScheduler.reprogramar(meds)
    }

    private func manejarFase(_ fase: ScenePhase) {
        guard settings.faceIDActivo && auth.disponible else { return }
        switch fase {
        case .background, .inactive:
            if fondoDesde == nil { fondoDesde = Date() }
        case .active:
            if let desde = fondoDesde {
                let transcurrido = Date().timeIntervalSince(desde)
                if transcurrido >= Double(settings.umbralBloqueoSegundos) {
                    auth.bloquear()
                    Task { await auth.autenticar() }
                }
            }
            fondoDesde = nil
        @unknown default:
            break
        }
    }
}

/// Puerta de Face ID + overlay de privacidad al pasar al app switcher (§12).
struct RootView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var auth: BiometricAuth
    @EnvironmentObject var alarmas: AlarmaCoordinator
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            if auth.desbloqueado {
                MainTabView()
            } else {
                LockView()
            }
            // Blur en el app switcher.
            if scenePhase != .active && auth.desbloqueado {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()
                    .overlay(Image(systemName: "lock.shield").font(.largeTitle).foregroundStyle(.secondary))
            }
        }
        .fullScreenCover(item: $alarmas.alarma) { info in
            AlarmaView(info: info)
        }
    }
}

struct LockView: View {
    @EnvironmentObject var auth: BiometricAuth
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 56))
                .foregroundStyle(Tema.acento)
            Text("Asista")
                .font(.largeTitle.bold())
            Text("Tus datos médicos están protegidos.")
                .foregroundStyle(.secondary)
            if let e = auth.error {
                Text(e).foregroundStyle(.red).font(.callout)
            }
            Button {
                Task { await auth.autenticar() }
            } label: {
                Label("Desbloquear con \(auth.tipoTexto)", systemImage: "faceid")
                    .padding(.horizontal)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
        }
        .padding()
    }
}
