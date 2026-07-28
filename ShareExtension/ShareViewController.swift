import UIKit
import UniformTypeIdentifiers

// Share Extension (§5.4): recibe PDFs e imágenes desde Mail, WhatsApp o Safari y
// los deja en el Inbox del App Group. La app los importa al abrir y los asigna a
// un reclamo existente o a uno nuevo.

final class ShareViewController: UIViewController {
    private let label = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        label.text = "Guardando en Asista…"
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Task { await procesar() }
    }

    private func procesar() async {
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        var guardados = 0
        for item in items {
            for provider in item.attachments ?? [] {
                if let ext = await guardar(provider) { _ = ext; guardados += 1 }
            }
        }
        label.text = guardados > 0 ? "Guardado en Asista" : "Nada para guardar"
        try? await Task.sleep(nanoseconds: 400_000_000)
        extensionContext?.completeRequest(returningItems: nil)
    }

    /// Carga el adjunto como PDF o imagen y lo escribe al Inbox compartido.
    private func guardar(_ provider: NSItemProvider) async -> String? {
        let tipos: [(UTType, String)] = [(.pdf, "pdf"), (.png, "png"), (.jpeg, "jpg"), (.heic, "heic"), (.image, "jpg")]
        for (tipo, ext) in tipos where provider.hasItemConformingToTypeIdentifier(tipo.identifier) {
            if let data = await cargarData(provider, tipo: tipo.identifier) {
                AppGroup.guardarEntrante(data, extension: ext)
                return ext
            }
        }
        return nil
    }

    private func cargarData(_ provider: NSItemProvider, tipo: String) async -> Data? {
        await withCheckedContinuation { cont in
            provider.loadDataRepresentation(forTypeIdentifier: tipo) { data, _ in
                cont.resume(returning: data)
            }
        }
    }
}
