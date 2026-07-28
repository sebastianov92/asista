import Foundation

// Contenedor compartido entre la app y la Share Extension (§5.4).
// La extensión deja archivos en Inbox; la app los importa al abrir.

enum AppGroup {
    static let id = "group.com.sebastian.Asista"

    /// Carpeta Inbox en el contenedor compartido. Si el App Group no está
    /// disponible (falta entitlement), cae al contenedor local para no romper.
    static var inbox: URL {
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Inbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Archivos pendientes de importar (PDFs/imágenes).
    static func pendientes() -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(
            at: inbox, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return items
            .filter { ["pdf", "jpg", "jpeg", "png", "heic"].contains($0.pathExtension.lowercased()) }
            .sorted { (fecha($0) ?? .distantPast) < (fecha($1) ?? .distantPast) }
    }

    static func eliminar(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// Guarda datos entrantes con un nombre único, conservando la extensión.
    @discardableResult
    static func guardarEntrante(_ data: Data, extension ext: String) -> URL {
        let url = inbox.appendingPathComponent("\(UUID().uuidString).\(ext)")
        try? data.write(to: url)
        return url
    }

    private static func fecha(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}
