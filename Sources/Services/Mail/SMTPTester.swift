import Foundation
import Network

// Prueba de credenciales SMTP: greeting → EHLO → AUTH LOGIN → 235 → QUIT.
// No envía correo; solo verifica que la app password funciona (§13 Ajustes).

enum SMTPTester {

    static func probar(_ creds: SMTPStoredCredentials) async throws {
        let conn = NWConnection(
            host: NWEndpoint.Host(creds.host),
            port: NWEndpoint.Port(rawValue: UInt16(creds.puerto)) ?? 465,
            using: .tls
        )
        let q = DispatchQueue(label: "smtp.test")
        conn.start(queue: q)

        func esperar(_ prefijo: String) async throws {
            let linea = try await recibirLinea(conn)
            guard linea.hasPrefix(prefijo) else {
                if linea.hasPrefix("535") { throw MailError.credencialesRechazadas }
                if linea.hasPrefix("534") { throw MailError.requiereAppPassword }
                throw MailError.protocolo(linea)
            }
        }

        func enviar(_ s: String) async throws {
            try await mandar(conn, s + "\r\n")
        }

        defer { conn.cancel() }

        try await esperar("220")
        try await enviar("EHLO asista.local")
        try await esperar("250")
        try await enviar("AUTH LOGIN")
        try await esperar("334")
        try await enviar(Data(creds.usuario.utf8).base64EncodedString())
        try await esperar("334")
        try await enviar(Data(creds.appPassword.utf8).base64EncodedString())
        try await esperar("235")   // credenciales aceptadas
        try await enviar("QUIT")
    }

    // Lee una respuesta SMTP completa (maneja multilínea: 4º char '-' continúa).
    private static func recibirLinea(_ conn: NWConnection) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            var acumulado = Data()
            func leer() {
                conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, error in
                    if let error { cont.resume(throwing: MailError.conexion(error.localizedDescription)); return }
                    if let data { acumulado.append(data) }
                    let texto = String(decoding: acumulado, as: UTF8.self)
                    // Última línea completa termina en \r\n y su 4º char es espacio.
                    let lineas = texto.components(separatedBy: "\r\n").filter { !$0.isEmpty }
                    if let ultima = lineas.last, ultima.count >= 4 {
                        let idx = ultima.index(ultima.startIndex, offsetBy: 3)
                        if ultima[idx] == " " {
                            cont.resume(returning: ultima)
                            return
                        }
                    }
                    if data == nil {
                        cont.resume(throwing: MailError.protocolo(texto))
                        return
                    }
                    leer()
                }
            }
            leer()
        }
    }

    private static func mandar(_ conn: NWConnection, _ s: String) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            conn.send(content: Data(s.utf8), completion: .contentProcessed { error in
                if let error { cont.resume(throwing: MailError.conexion(error.localizedDescription)) }
                else { cont.resume() }
            })
        }
    }
}
