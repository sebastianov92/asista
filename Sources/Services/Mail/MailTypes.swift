import Foundation

// MARK: - Tipos de valor del subsistema de correo
//
// IMPORTANTE: este subsistema opera SOLO con estos tipos de valor.
// NO importa ni referencia ningún @Model de SwiftData. El resto de la app
// mapea sus modelos a estos structs antes de invocar el envío.

/// Dirección de correo con nombre opcional para cabeceras.
struct EmailAddress: Equatable {
    var nombre: String   // puede estar vacío
    var email: String

    init(_ email: String, nombre: String = "") {
        self.email = email
        self.nombre = nombre
    }

    /// Renderizado para una cabecera: `Nombre <email>` o solo `email` si nombre vacío.
    /// Casos raros: si el nombre lleva caracteres no ASCII se codifica RFC 2047; si
    /// lleva "specials" RFC 5322 se entrecomilla. El caso normal queda `Nombre <email>`.
    var header: String {
        if nombre.isEmpty {
            return email
        }
        // No ASCII → palabra codificada RFC 2047 (el display-name crudo solo admite ASCII).
        if !nombre.allSatisfy({ $0.isASCII }) {
            let b64 = Data(nombre.utf8).base64EncodedString()
            return "=?UTF-8?B?\(b64)?= <\(email)>"
        }
        // Con "specials" → entrecomillar y escapar comillas/backslashes.
        let specials = CharacterSet(charactersIn: "()<>[]:;@\\,.\"")
        if nombre.rangeOfCharacter(from: specials) != nil {
            let escapado = nombre
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escapado)\" <\(email)>"
        }
        return "\(nombre) <\(email)>"
    }
}

/// Adjunto local. Se lee de forma perezosa/streamed — NO cargar todo en memoria de golpe.
struct Attachment {
    var url: URL          // fichero local
    var filename: String  // ASCII (garantizado por el caller), p.ej. 2026-07-27_JuanPerez_01-Receta.pdf
    var mimeType: String  // p.ej. "application/pdf"
}

/// Correo saliente ya resuelto a tipos de valor.
struct OutgoingMail {
    var from: EmailAddress
    var to: [EmailAddress]
    var cc: [EmailAddress]
    var bcc: [EmailAddress]
    var subject: String
    var body: String              // texto plano, UTF-8, puede llevar tildes/saltos de línea
    var attachments: [Attachment]
    var messageID: String         // valor completo SIN ángulos, p.ej. "uuid@asista.app"; los < > los añadimos nosotros
    var inReplyTo: String?        // messageID sin ángulos, o nil
    var references: [String]      // messageIDs sin ángulos
}

/// Recibo de envío satisfactorio.
struct SentReceipt {
    var messageID: String
    var fecha: Date
    var metodo: MetodoEnvio   // MetodoEnvio YA EXISTE en Sources/Models/Enums.swift; no se redeclara.
}

/// Credenciales SMTP (Gmail app password).
struct SMTPCredentials {
    var usuario: String       // dirección gmail completa
    var appPassword: String   // 16 chars, espacios ya eliminados por el caller
    var host: String          // por defecto "smtp.gmail.com"
    var puerto: UInt16        // por defecto 465

    init(usuario: String, appPassword: String, host: String = "smtp.gmail.com", puerto: UInt16 = 465) {
        self.usuario = usuario
        self.appPassword = appPassword
        self.host = host
        self.puerto = puerto
    }
}

/// Errores del subsistema. Los mensajes de `errorDescription` son los del spec (§8.2).
enum MailError: LocalizedError {
    case sinCredenciales
    case credencialesRechazadas   // 535 5.7.8
    case requiereAppPassword      // 534 5.7.9
    case correoDemasiadoGrande    // 552 / 523
    case timeout
    case conexion(String)
    case protocolo(String)        // respuesta inesperada del servidor
    case canceladoPorUsuario      // extensión: el usuario cerró el composer sin enviar

    var errorDescription: String? {
        switch self {
        case .sinCredenciales:
            return "No hay credenciales de correo configuradas. Añade tu cuenta de Gmail y una contraseña de aplicación en Ajustes."
        case .credencialesRechazadas:
            return "Gmail rechazó tus credenciales. Revisa tu dirección de correo y la contraseña de aplicación."
        case .requiereAppPassword:
            return "Gmail requiere una contraseña de aplicación. Genera una en tu cuenta de Google y vuelve a intentarlo."
        case .correoDemasiadoGrande:
            return "El correo es demasiado grande para enviarse. Reduce el número o el tamaño de los adjuntos."
        case .timeout:
            return "Se agotó el tiempo de conexión con el servidor de correo. Comprueba tu conexión a internet e inténtalo de nuevo."
        case .conexion(let detalle):
            return "No se pudo conectar con el servidor de correo. \(detalle)"
        case .protocolo(let detalle):
            return "Respuesta inesperada del servidor de correo. \(detalle)"
        case .canceladoPorUsuario:
            return "Envío cancelado."
        }
    }
}

/// Contrato común de un remitente de correo.
protocol MailSender {
    /// `true` si puede enviar sin interacción del usuario (SMTP), `false` si requiere UI (composer).
    var puedeEnviarSilenciosamente: Bool { get }
    func send(_ mail: OutgoingMail) async throws -> SentReceipt
}
