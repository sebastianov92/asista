import SwiftUI

struct SMTPSettingsView: View {
    @State private var usuario = ""
    @State private var appPassword = ""
    @State private var host = "smtp.gmail.com"
    @State private var puerto = 465
    @State private var estado: Estado = .idle
    @State private var guardado = false

    enum Estado: Equatable {
        case idle, probando, ok, error(String)
    }

    var body: some View {
        Form {
            Section {
                TextField("Correo (usuario@gmail.com)", text: $usuario)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                SecureField("Contraseña de aplicación (16 caracteres)", text: $appPassword)
                    .autocorrectionDisabled()
            } footer: {
                Text("La contraseña normal de Gmail no funciona. Necesitas una contraseña de aplicación de 16 caracteres (requiere verificación en 2 pasos). Google la muestra en 4 grupos de 4; puedes pegarla con espacios.")
            }

            Section("Servidor") {
                TextField("Host", text: $host).autocorrectionDisabled().textInputAutocapitalization(.never)
                Stepper("Puerto: \(puerto)", value: $puerto, in: 1...65535)
                Text("Recomendado: smtp.gmail.com puerto 465 (TLS).")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Button {
                    Task { await probar() }
                } label: {
                    HStack {
                        Label("Probar conexión", systemImage: "bolt.horizontal")
                        Spacer()
                        switch estado {
                        case .probando: ProgressView()
                        case .ok: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        case .error: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                        case .idle: EmptyView()
                        }
                    }
                }
                .disabled(usuario.isEmpty || appPassword.isEmpty || estado == .probando)

                if case .error(let msg) = estado {
                    Text(msg).font(.caption).foregroundStyle(.red)
                }
                if case .ok = estado {
                    Text("Credenciales válidas. Ya puedes enviar por SMTP.")
                        .font(.caption).foregroundStyle(.green)
                }
            }

            Section {
                Button {
                    guardar()
                } label: { Label("Guardar credenciales", systemImage: "checkmark.seal") }
                    .disabled(usuario.isEmpty || appPassword.isEmpty)
                if KeychainStore.hayCredenciales {
                    Button(role: .destructive) {
                        KeychainStore.borrar()
                        usuario = ""; appPassword = ""; estado = .idle
                    } label: { Label("Borrar credenciales", systemImage: "trash") }
                }
            } footer: {
                if guardado { Text("Guardado en Keychain (solo este dispositivo).").foregroundStyle(.green) }
            }
        }
        .navigationTitle("Cuenta de correo")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: cargar)
    }

    private func cargar() {
        guard let c = KeychainStore.leer() else { return }
        usuario = c.usuario
        appPassword = c.appPassword
        host = c.host
        puerto = c.puerto
    }

    private func creds() -> SMTPStoredCredentials {
        SMTPStoredCredentials(usuario: usuario.trimmingCharacters(in: .whitespaces),
                              appPassword: appPassword, host: host, puerto: puerto)
    }

    private func probar() async {
        estado = .probando
        do {
            try await SMTPTester.probar(creds())
            estado = .ok
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            estado = .error(msg)
        }
    }

    private func guardar() {
        do {
            try KeychainStore.guardar(creds())
            guardado = true
        } catch {
            estado = .error("No se pudo guardar: \(error.localizedDescription)")
        }
    }
}
