import Foundation

/// Construye el mensaje RFC 5322 / MIME (multipart/mixed).
///
/// Diseño para streaming de adjuntos:
///  - `headersAndBody(for:)` produce todo hasta (e incluyendo) la parte text/plain
///    y la línea de frontera que precede al primer adjunto (o la frontera de cierre
///    si no hay adjuntos).
///  - `attachmentPartHeader(for:)` produce la cabecera de una parte de adjunto.
///  - `wrapBase64(_:)` envuelve bytes en líneas base64 de 76 chars (bloques de 57 bytes).
///  - `partDelimiter` / `closingBoundary` para las fronteras entre/después de adjuntos.
///  - `mimeMessage(for:attachmentData:)` arma el mensaje COMPLETO en memoria (path de
///    test; el composer no usa MIME crudo). Este método NO aplica dot-stuffing.
///
/// DOT-STUFFING: NO se aplica aquí. Se aplica en la capa SMTP (SMTPMailSender),
/// línea a línea sobre el payload de DATA, justo antes de enviar. Así el mensaje
/// crudo de `mimeMessage` queda limpio para tests, y la transparencia de punto
/// solo vive donde importa (el diálogo SMTP).
struct MIMEBuilder {

    /// Frontera multipart. Estable durante la vida de este builder para que
    /// `headersAndBody`, las partes de adjunto y el cierre usen el mismo valor.
    let boundary: String

    init(boundary: String? = nil) {
        // Derivada de UUID; Date/UUID son aceptables aquí (app real, no script de workflow).
        self.boundary = boundary ?? "----=_Part_\(UUID().uuidString)"
    }

    // MARK: - Cabeceras + cuerpo

    /// Todo hasta la parte text/plain inclusive, más la frontera que precede al primer
    /// adjunto (o la frontera de cierre si no hay adjuntos). Líneas siempre con CRLF.
    func headersAndBody(for mail: OutgoingMail) -> String {
        var s = ""

        // --- Cabeceras ---
        s += "From: \(mail.from.header)\r\n"
        if !mail.to.isEmpty {
            s += "To: \(joinAddresses(mail.to))\r\n"
        }
        if !mail.cc.isEmpty {  // Cc se omite si vacío. Bcc NUNCA aparece en cabeceras.
            s += "Cc: \(joinAddresses(mail.cc))\r\n"
        }
        s += "Subject: \(encodeSubject(mail.subject))\r\n"
        s += "Date: \(Self.rfc5322Date(Date()))\r\n"
        s += "Message-ID: <\(mail.messageID)>\r\n"
        if let irt = mail.inReplyTo, !irt.isEmpty {
            s += "In-Reply-To: <\(irt)>\r\n"
        }
        if !mail.references.isEmpty {
            let refs = mail.references.map { "<\($0)>" }.joined(separator: " ")
            s += "References: \(refs)\r\n"
        }
        s += "MIME-Version: 1.0\r\n"
        s += "Content-Type: multipart/mixed; boundary=\"\(boundary)\"\r\n"
        s += "\r\n"  // fin de cabeceras

        // --- Parte text/plain (base64 del cuerpo UTF-8; simple y válido) ---
        s += partDelimiter
        s += "Content-Type: text/plain; charset=UTF-8\r\n"
        s += "Content-Transfer-Encoding: base64\r\n"
        s += "\r\n"
        s += wrapBase64(Data(mail.body.utf8))

        // --- Frontera hacia el primer adjunto, o cierre si no hay adjuntos ---
        if mail.attachments.isEmpty {
            s += closingBoundary
        } else {
            s += partDelimiter
        }
        return s
    }

    // MARK: - Partes de adjunto

    /// Cabecera de una parte de adjunto (termina con la línea en blanco).
    /// A continuación va el base64 envuelto de los bytes del fichero.
    func attachmentPartHeader(for att: Attachment) -> String {
        var s = ""
        s += "Content-Type: \(att.mimeType); name=\"\(att.filename)\"\r\n"
        s += "Content-Transfer-Encoding: base64\r\n"
        s += "Content-Disposition: attachment; filename=\"\(att.filename)\"\r\n"
        s += "\r\n"
        return s
    }

    /// Frontera entre partes: `--boundary\r\n`.
    var partDelimiter: String { "--\(boundary)\r\n" }

    /// Frontera de cierre: `--boundary--\r\n`.
    var closingBoundary: String { "--\(boundary)--\r\n" }

    // MARK: - Base64 wrapping (bloques de 57 bytes → 76 chars por línea)

    /// Envuelve `data` en líneas base64 de 76 chars separadas por CRLF, con CRLF final.
    /// 57 bytes crudos → exactamente 76 chars base64. Datos vacíos → cadena vacía.
    func wrapBase64(_ data: Data) -> String {
        let blockSize = 57
        var out = ""
        var index = 0
        let count = data.count
        while index < count {
            let end = min(index + blockSize, count)
            let chunk = data.subdata(in: index..<end)
            out += chunk.base64EncodedString()
            out += "\r\n"
            index = end
        }
        return out
    }

    // MARK: - Mensaje completo (test / no-streaming)

    /// Arma el mensaje MIME COMPLETO en memoria. Pensado para tests; el path SMTP real
    /// hace streaming pieza a pieza. NO aplica dot-stuffing (eso es de la capa SMTP).
    func mimeMessage(for mail: OutgoingMail, attachmentData: (URL) throws -> Data) rethrows -> Data {
        var s = headersAndBody(for: mail)
        for (i, att) in mail.attachments.enumerated() {
            s += attachmentPartHeader(for: att)
            s += wrapBase64(try attachmentData(att.url))
            // Tras el base64 de esta parte, frontera intermedia o cierre.
            s += (i == mail.attachments.count - 1) ? closingBoundary : partDelimiter
        }
        return Data(s.utf8)
    }

    // MARK: - Helpers de cabecera

    private func joinAddresses(_ addrs: [EmailAddress]) -> String {
        addrs.map { $0.header }.joined(separator: ", ")
    }

    /// Subject: si es ASCII puro se deja tal cual; si no, palabra codificada RFC 2047
    /// `=?UTF-8?B?<base64 utf8>?=` (una sola palabra codificada, aceptable para este uso).
    private func encodeSubject(_ subject: String) -> String {
        if subject.allSatisfy({ $0.isASCII }) {
            return subject
        }
        let b64 = Data(subject.utf8).base64EncodedString()
        return "=?UTF-8?B?\(b64)?="
    }

    /// Fecha en formato RFC 5322 con zona horaria, p.ej. `Mon, 27 Jul 2026 14:32:10 -0500`.
    static func rfc5322Date(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")  // nombres de día/mes en inglés, estables
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return f.string(from: date)
    }
}
