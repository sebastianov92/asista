import SwiftUI
import SwiftData

struct AjustesView: View {
    @EnvironmentObject private var settings: AppSettings
    @AppStorage("iCloudActivo") private var iCloudActivo = false
    @AppStorage("alarmasCriticas") private var alarmasCriticas = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Correo") {
                    NavigationLink { SMTPSettingsView() } label: {
                        Label("Cuenta de correo (SMTP)", systemImage: "envelope")
                    }
                    Toggle(isOn: $settings.copiaPropiaActiva) {
                        Label("Guardarme copia (Cco)", systemImage: "tray.and.arrow.down")
                    }
                    Toggle(isOn: $settings.preferirComposer) {
                        Label("Usar app de Mail para enviar", systemImage: "square.and.pencil")
                    }
                }

                Section("Plantilla") {
                    NavigationLink { PlantillaGlobalView() } label: {
                        Label("Plantilla global", systemImage: "text.badge.star")
                    }
                }

                Section("Directorio") {
                    NavigationLink { ContactosWrapper() } label: {
                        Label("Médicos y prestadores", systemImage: "person.crop.circle.badge.checkmark")
                    }
                    NavigationLink { FormulariosHubView() } label: {
                        Label("Formularios en blanco", systemImage: "doc.on.doc")
                    }
                    NavigationLink { ReportesView() } label: {
                        Label("Reportes y exportación", systemImage: "chart.bar.doc.horizontal")
                    }
                }

                Section("Escaneo") {
                    Picker(selection: Binding(
                        get: { settings.preajustePorDefecto },
                        set: { settings.preajustePorDefecto = $0 })) {
                        ForEach(PreajusteCalidad.allCases, id: \.self) { Text($0.etiqueta).tag($0) }
                    } label: { Label("Calidad por defecto", systemImage: "camera") }

                    NavigationLink { PatronNombresView() } label: {
                        Label("Patrón de nombres", systemImage: "textformat")
                    }
                    Stepper(value: $settings.umbralTamanoMB, in: 5...25) {
                        Label("Aviso de peso: \(settings.umbralTamanoMB) MB", systemImage: "scalemass")
                    }
                }

                Section {
                    Toggle(isOn: $alarmasCriticas) {
                        Label("Alarmas críticas de medicación", systemImage: "alarm.waves.left.and.right")
                    }
                    .onChange(of: alarmasCriticas) { _, _ in
                        Task { await Recordatorios.solicitarPermiso() }
                    }
                } header: {
                    Text("Medicación")
                } footer: {
                    Text("Las alarmas críticas suenan fuerte e ignoran el silencio y el modo Foco aunque la app esté cerrada. Requiere activar la capacidad «Critical Alerts» en Xcode con tu cuenta de desarrollador y la aprobación de Apple. Sin eso, en primer plano igual suena ignorando el silencio.")
                }

                Section("Recordatorios") {
                    Toggle("Seguimiento sin respuesta", isOn: $settings.recordatorioSeguimientoActivo)
                    if settings.recordatorioSeguimientoActivo {
                        Stepper(value: $settings.recordatorioSeguimientoDias, in: 3...60) {
                            Text("A los \(settings.recordatorioSeguimientoDias) días")
                        }
                    }
                    Toggle("Borradores olvidados", isOn: $settings.recordatorioBorradorActivo)
                }

                Section("Seguridad") {
                    Toggle(isOn: $settings.faceIDActivo) {
                        Label("Exigir Face ID", systemImage: "faceid")
                    }
                    if settings.faceIDActivo {
                        Picker(selection: $settings.umbralBloqueoSegundos) {
                            Text("Inmediato").tag(0)
                            Text("30 s").tag(30)
                            Text("1 min").tag(60)
                            Text("5 min").tag(300)
                        } label: { Text("Bloquear tras") }
                    }
                }

                Section("Almacenamiento") {
                    NavigationLink { AlmacenamientoView() } label: {
                        Label("Uso y limpieza", systemImage: "internaldrive")
                    }
                }

                Section {
                    Toggle(isOn: $iCloudActivo) {
                        Label("Sincronizar con iCloud", systemImage: "icloud")
                    }
                } footer: {
                    Text("Sincroniza tus reclamos entre tus dispositivos con CloudKit. Requiere activar la capacidad de iCloud en Xcode con tu cuenta de desarrollador y reiniciar la app. Si no está disponible, la app sigue funcionando solo en este dispositivo.")
                }

                Section {
                    LabeledContent("Versión", value: "0.1.0 · Fase 1")
                }
            }
            .navigationTitle("Ajustes")
        }
    }
}

// Envuelve el directorio para poblarlo con los nombres ya usados en reclamos/eventos.
struct ContactosWrapper: View {
    @Environment(\.modelContext) private var ctx
    @Query private var reclamos: [Reclamo]
    @Query private var eventos: [EventoMedico]
    @Query private var contactos: [Contacto]

    var body: some View {
        ContactosView()
            .onAppear {
                DirectorioBuilder.sincronizar(reclamos: reclamos, eventos: eventos, existentes: contactos, ctx: ctx)
            }
    }
}

// MARK: - Patrón de nombres

struct PatronNombresView: View {
    @EnvironmentObject private var settings: AppSettings
    private let tokens = ["fecha", "paciente", "orden", "tipo", "aseguradora", "poliza", "reclamo"]

    var body: some View {
        Form {
            Section("Patrón") {
                TextField("Patrón", text: $settings.patronNombres)
                    .font(.system(.body, design: .monospaced))
            }
            Section("Insertar token") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110))], spacing: 8) {
                    ForEach(tokens, id: \.self) { t in
                        Button("{\(t)}") { settings.patronNombres += "{\(t)}" }
                            .buttonStyle(.bordered)
                            .font(.caption)
                    }
                }
            }
            Section("Ejemplo") {
                Text(ejemplo).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Patrón de nombres")
    }

    private var ejemplo: String {
        var s = settings.patronNombres
        let vals = ["fecha": "2026-07-27", "paciente": "JuanPerez", "orden": "02",
                    "tipo": "Factura-Medico", "aseguradora": "Salud", "poliza": "P123", "reclamo": "5"]
        for (k, v) in vals { s = s.replacingOccurrences(of: "{\(k)}", with: v) }
        return s + ".pdf"
    }
}
