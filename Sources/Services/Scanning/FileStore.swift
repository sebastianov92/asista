import Foundation

/// Almacenamiento en disco de originales y PDFs dentro del contenedor de la app.
///
/// Base: <container>/Documents/Reclamos. Subcarpetas `originales/` y `pdfs/` se
/// crean de forma perezosa. Todo se escribe con protección de datos completa
/// (`.complete`): los archivos quedan cifrados en reposo con el passcode (§8).
enum FileStore {

    /// Directorio raíz de datos de reclamos, creado si no existe.
    static var documentosDir: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Reclamos", isDirectory: true)
        try? crearDirectorio(dir)
        return dir
    }

    /// Ruta del original (imagen recortada sin filtro) de una página.
    /// .../Reclamos/originales/<id>.jpg
    static func urlOriginal(paginaID: UUID) -> URL {
        let dir = documentosDir.appendingPathComponent("originales", isDirectory: true)
        try? crearDirectorio(dir)
        return dir.appendingPathComponent("\(paginaID.uuidString).jpg", isDirectory: false)
    }

    /// Ruta de un PDF ya nombrado. .../Reclamos/pdfs/<nombre>
    static func urlPDF(nombre: String) -> URL {
        let dir = documentosDir.appendingPathComponent("pdfs", isDirectory: true)
        try? crearDirectorio(dir)
        return dir.appendingPathComponent(nombre, isDirectory: false)
    }

    /// Escribe `data` en `url`, creando los directorios padre y forzando
    /// protección de archivo completa.
    static func guardar(_ data: Data, en url: URL) throws {
        try crearDirectorio(url.deletingLastPathComponent())
        try data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    /// Tamaño en bytes del archivo; 0 si no existe o no es legible.
    static func tamano(_ url: URL) -> Int {
        let valores = try? url.resourceValues(forKeys: [.fileSizeKey])
        return valores?.fileSize ?? 0
    }

    // MARK: - Privado

    private static func crearDirectorio(_ dir: URL) throws {
        try FileManager.default.createDirectory(at: dir,
                                                withIntermediateDirectories: true,
                                                attributes: nil)
    }
}
