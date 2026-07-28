import Foundation
import Security

// Credenciales SMTP en Keychain (§12). Nunca en el modelo de datos, nunca en logs.
// Accesibles solo con el dispositivo desbloqueado y sin migrar a otros equipos.

struct SMTPStoredCredentials: Codable, Equatable {
    var usuario: String       // dirección completa de Gmail
    var appPassword: String   // 16 caracteres, se guardan ya sin espacios
    var host: String
    var puerto: Int

    init(usuario: String, appPassword: String, host: String = "smtp.gmail.com", puerto: Int = 465) {
        self.usuario = usuario
        // La app password se muestra en 4 grupos de 4; quitar espacios antes de usar (§8.2.6).
        self.appPassword = appPassword.replacingOccurrences(of: " ", with: "")
        self.host = host
        self.puerto = puerto
    }
}

enum KeychainStore {
    private static let service = "com.sebastian.Asista.smtp"
    private static let account = "smtp-credentials"

    static func guardar(_ creds: SMTPStoredCredentials) throws {
        let data = try JSONEncoder().encode(creds)
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        // Borrar cualquier valor previo y reinsertar.
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.osStatus(status) }
    }

    static func leer() -> SMTPStoredCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(SMTPStoredCredentials.self, from: data)
    }

    static func borrar() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    static var hayCredenciales: Bool { leer() != nil }
}

enum KeychainError: LocalizedError {
    case osStatus(OSStatus)
    var errorDescription: String? {
        switch self {
        case .osStatus(let s):
            return "No se pudieron guardar las credenciales (código \(s))."
        }
    }
}
