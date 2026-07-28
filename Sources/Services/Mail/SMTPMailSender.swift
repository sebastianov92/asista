import Foundation
import Network

/// Remitente SMTP directo contra Gmail (TLS implícito, puerto 465).
///
/// Envía SIN interacción del usuario (`puedeEnviarSilenciosamente == true`).
/// Las credenciales se obtienen de forma perezosa vía closure (típicamente Keychain);
/// si el closure devuelve nil, `send` lanza `.sinCredenciales`.
///
/// El diálogo SMTP y la lectura de respuestas se implementan sobre `NWConnection`
/// envolviendo send/receive en continuaciones async/await.
final class SMTPMailSender: MailSender {

    /// Límite de tamaño total. base64 infla ~1.37x, así que validamos el crudo contra
    /// este techo dejando margen. Público para que el resto de la app lo consulte.
    static let maxTotalBytes = 25 * 1024 * 1024   // 25 MB

    let puedeEnviarSilenciosamente = true

    private let credentialsProvider: () -> SMTPCredentials?
    private let timeout: TimeInterval

    init(timeout: TimeInterval = 30, credentialsProvider: @escaping () -> SMTPCredentials?) {
        self.timeout = timeout
        self.credentialsProvider = credentialsProvider
    }

    // MARK: - MailSender

    func send(_ mail: OutgoingMail) async throws -> SentReceipt {
        guard let creds = credentialsProvider() else { throw MailError.sinCredenciales }

        // Validación de tamaño ANTES de abrir conexión (base64 infla ~1.37x).
        try validarTamaño(mail.attachments)

        let conn = SMTPConnection(host: creds.host, port: creds.puerto, timeout: timeout)
        try await conn.connect()
        defer { conn.cancel() }

        // 1) Saludo del servidor.
        try expect([220], try await conn.readReply())

        // 2) EHLO.
        try await conn.send(line: "EHLO asista.local")
        try expect([250], try await conn.readReply())

        // 3) AUTH LOGIN (usuario y contraseña en base64, cada uno tras un 334).
        try await conn.send(line: "AUTH LOGIN")
        try expect([334], try await conn.readReply(), authContext: true)

        try await conn.send(line: Data(creds.usuario.utf8).base64EncodedString())
        try expect([334], try await conn.readReply(), authContext: true)

        try await conn.send(line: Data(creds.appPassword.utf8).base64EncodedString())
        try expect([235], try await conn.readReply(), authContext: true)

        // 4) MAIL FROM.
        try await conn.send(line: "MAIL FROM:<\(creds.usuario)>")
        try expect([250], try await conn.readReply())

        // 5) RCPT TO por cada destinatario (to + cc + bcc). Bcc también recibe copia,
        //    pero NO aparece en las cabeceras (eso ya lo garantiza MIMEBuilder).
        let destinatarios = mail.to + mail.cc + mail.bcc
        for addr in destinatarios {
            try await conn.send(line: "RCPT TO:<\(addr.email)>")
            // Gmail responde 250/251 a un RCPT aceptado.
            try expect([250, 251], try await conn.readReply())
        }

        // 6) DATA.
        try await conn.send(line: "DATA")
        try expect([354], try await conn.readReply())

        // 7) Streaming del mensaje. NO construimos un Data gigante con todos los adjuntos:
        //    enviamos cabeceras+cuerpo y luego cada adjunto pieza a pieza. Cada pieza
        //    empieza y termina en frontera de línea (CRLF), así el dot-stuffing por pieza
        //    es correcto (ninguna línea cruza el límite de una pieza).
        let builder = MIMEBuilder()

        try await conn.send(dataStuffed: builder.headersAndBody(for: mail))

        for (i, att) in mail.attachments.enumerated() {
            try await conn.send(dataStuffed: builder.attachmentPartHeader(for: att))
            // Un solo PDF completo en memoria a la vez (permitido); no todos a la vez.
            let data = try Data(contentsOf: att.url)
            try await conn.send(dataStuffed: builder.wrapBase64(data))
            let frontera = (i == mail.attachments.count - 1) ? builder.closingBoundary
                                                             : builder.partDelimiter
            try await conn.send(dataStuffed: frontera)
        }

        // 8) Terminador de DATA. El payload ya acaba en CRLF; enviamos "\r\n.\r\n"
        //    (el CRLF extra queda como epílogo tras la frontera de cierre, se ignora).
        try await conn.sendRaw(Data("\r\n.\r\n".utf8))
        try expect([250], try await conn.readReply())

        // 9) QUIT (cortesía; no bloqueamos por su respuesta).
        try? await conn.send(line: "QUIT")

        return SentReceipt(messageID: mail.messageID, fecha: Date(), metodo: .smtp)
    }

    // MARK: - Validación de tamaño

    private func validarTamaño(_ attachments: [Attachment]) throws {
        var total = 0
        for att in attachments {
            let attrs = try? FileManager.default.attributesOfItem(atPath: att.url.path)
            total += (attrs?[.size] as? Int) ?? 0
        }
        // base64 infla ~1.37x.
        if Double(total) * 1.37 > Double(Self.maxTotalBytes) {
            throw MailError.correoDemasiadoGrande
        }
    }

    // MARK: - Mapeo de respuestas a MailError

    /// Verifica que el código de la respuesta esté en `codes`; si no, mapea a MailError.
    private func expect(_ codes: Set<Int>, _ reply: SMTPReply, authContext: Bool = false) throws {
        if codes.contains(reply.code) { return }
        switch reply.code {
        case 535:                       // 5.7.8 credenciales inválidas
            throw MailError.credencialesRechazadas
        case 534:                       // 5.7.9 requiere contraseña de aplicación
            throw MailError.requiereAppPassword
        case 552, 523:                  // mensaje/almacenamiento demasiado grande
            throw MailError.correoDemasiadoGrande
        default:
            if authContext && reply.code >= 500 {
                // Cualquier 5xx durante la autenticación se trata como rechazo de credenciales.
                throw MailError.credencialesRechazadas
            }
            throw MailError.protocolo("\(reply.code) \(reply.text)")
        }
    }
}

// MARK: - Respuesta SMTP

/// Respuesta parseada del servidor: código de 3 dígitos + texto completo.
struct SMTPReply {
    let code: Int
    let text: String
}

// MARK: - Conexión SMTP (NWConnection + async/await)

/// Envuelve un `NWConnection` con TLS implícito y expone send/receive como async.
private final class SMTPConnection {

    private let connection: NWConnection
    private let queue = DispatchQueue(label: "app.asista.smtp")
    private let timeout: TimeInterval

    /// Buffer de bytes recibidos aún no consumidos (para reconstruir respuestas multilínea).
    private var buffer = Data()

    init(host: String, port: UInt16, timeout: TimeInterval) {
        self.timeout = timeout
        // TLS implícito: la sesión TLS se establece en cuanto conecta el socket (465).
        let params = NWParameters(tls: NWProtocolTLS.Options(), tcp: NWProtocolTCP.Options())
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port) ?? 465
        )
        self.connection = NWConnection(to: endpoint, using: params)
    }

    // MARK: Ciclo de vida

    func connect() async throws {
        try await withTimeout(timeout) {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                var resumed = false
                self.connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        guard !resumed else { return }
                        resumed = true
                        cont.resume()
                    case .failed(let error):
                        guard !resumed else { return }
                        resumed = true
                        cont.resume(throwing: MailError.conexion(error.localizedDescription))
                    case .cancelled:
                        guard !resumed else { return }
                        resumed = true
                        cont.resume(throwing: MailError.conexion("conexión cancelada"))
                    default:
                        break
                    }
                }
                self.connection.start(queue: self.queue)
            }
        }
    }

    func cancel() {
        connection.cancel()
    }

    // MARK: Envío

    /// Envía una línea de comando SMTP (se le añade CRLF).
    func send(line: String) async throws {
        try await sendRaw(Data((line + "\r\n").utf8))
    }

    /// Envía un fragmento del payload de DATA aplicando dot-stuffing por línea.
    /// Cada fragmento empieza/termina en frontera de línea, así el stuffing por
    /// fragmento es correcto.
    func send(dataStuffed s: String) async throws {
        try await sendRaw(SMTPConnection.dotStuff(s))
    }

    func sendRaw(_ data: Data) async throws {
        try await withTimeout(timeout) {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                self.connection.send(content: data, completion: .contentProcessed { error in
                    if let error {
                        cont.resume(throwing: MailError.conexion(error.localizedDescription))
                    } else {
                        cont.resume()
                    }
                })
            }
        }
    }

    // MARK: Recepción

    /// Lee una respuesta SMTP completa (soporta multilínea `250-...` / `250 ...`).
    func readReply() async throws -> SMTPReply {
        try await withTimeout(timeout) {
            while true {
                if let reply = self.extractReply() { return reply }
                let chunk = try await self.receiveChunk()
                self.buffer.append(chunk)
            }
        }
    }

    private func receiveChunk() async throws -> Data {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            self.connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
                if let error {
                    cont.resume(throwing: MailError.conexion(error.localizedDescription))
                    return
                }
                if let data, !data.isEmpty {
                    cont.resume(returning: data)
                    return
                }
                if isComplete {
                    cont.resume(throwing: MailError.conexion("el servidor cerró la conexión"))
                    return
                }
                cont.resume(returning: Data())  // sin datos aún; el bucle reintenta
            }
        }
    }

    /// Intenta extraer una respuesta completa del buffer. Una respuesta es multilínea
    /// mientras el 4º carácter de la línea sea `-` (`250-`); la última línea lleva un
    /// espacio en esa posición (`250 `). Trabaja sobre bytes (respuestas ASCII).
    private func extractReply() -> SMTPReply? {
        let bytes = [UInt8](buffer)
        var start = 0
        var i = 0
        while i + 1 < bytes.count {
            if bytes[i] == 0x0D && bytes[i + 1] == 0x0A {   // CRLF
                let lineLen = i - start
                if lineLen >= 4 && bytes[start + 3] == 0x20 {   // espacio en pos 3 → línea final
                    let code = SMTPConnection.parseCode(bytes, at: start)
                    let text = String(decoding: bytes[0..<i], as: UTF8.self)
                    buffer.removeFirst(i + 2)   // consume hasta e incluyendo el CRLF final
                    return SMTPReply(code: code, text: text)
                }
                start = i + 2
                i += 2
                continue
            }
            i += 1
        }
        return nil
    }

    private static func parseCode(_ bytes: [UInt8], at start: Int) -> Int {
        func digit(_ b: UInt8) -> Int { (b >= 48 && b <= 57) ? Int(b - 48) : 0 }
        return digit(bytes[start]) * 100 + digit(bytes[start + 1]) * 10 + digit(bytes[start + 2])
    }

    // MARK: Dot-stuffing

    /// Transparencia de punto (RFC 5321 §4.5.2): toda línea del payload que empiece por
    /// `.` se envía con un `.` extra. Se aplica por fragmento; como cada fragmento
    /// empieza en frontera de línea, es correcto.
    static func dotStuff(_ s: String) -> Data {
        let lines = s.components(separatedBy: "\r\n")
        var out = ""
        for (i, line) in lines.enumerated() {
            out += line.hasPrefix(".") ? "." + line : line
            if i < lines.count - 1 { out += "\r\n" }
        }
        return Data(out.utf8)
    }
}

// MARK: - Timeout helper

/// Ejecuta `op` con un límite de tiempo; si vence, lanza `.timeout`.
private func withTimeout<T>(_ seconds: TimeInterval, _ op: @escaping () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await op() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw MailError.timeout
        }
        // El primero en terminar gana; cancelamos el resto.
        guard let result = try await group.next() else { throw MailError.timeout }
        group.cancelAll()
        return result
    }
}
