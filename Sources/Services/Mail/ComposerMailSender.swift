import Foundation
import UIKit
import MessageUI

/// Remitente vía `MFMailComposeViewController`: presenta el compositor del sistema
/// prellenado. Requiere interacción del usuario (`puedeEnviarSilenciosamente == false`).
///
/// LIMITACIÓN: el compositor del sistema NO permite fijar Message-ID / In-Reply-To /
/// References. El correo realmente enviado por Mail NO llevará el `messageID` de
/// `OutgoingMail`; aun así devolvemos un `SentReceipt` con ese `messageID` (para que la
/// app conserve su propio hilo lógico) y `metodo: .composer`. Los campos de hilo
/// (`inReplyTo`, `references`) se ignoran en este path.
final class ComposerMailSender: MailSender {

    let puedeEnviarSilenciosamente = false

    func send(_ mail: OutgoingMail) async throws -> SentReceipt {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<SentReceipt, Error>) in
            // La UI debe tocarse en el hilo principal.
            Task { @MainActor in
                guard MFMailComposeViewController.canSendMail() else {
                    // Sin cuenta de correo configurada en el dispositivo.
                    cont.resume(throwing: MailError.conexion("Este dispositivo no tiene configurada una cuenta de correo."))
                    return
                }
                guard let presenter = Self.topViewController() else {
                    cont.resume(throwing: MailError.conexion("No hay una vista disponible para mostrar el compositor de correo."))
                    return
                }

                let vc = MFMailComposeViewController()
                let coordinator = ComposerCoordinator(messageID: mail.messageID, continuation: cont)
                vc.mailComposeDelegate = coordinator

                vc.setToRecipients(mail.to.map { $0.email })
                vc.setCcRecipients(mail.cc.map { $0.email })
                vc.setBccRecipients(mail.bcc.map { $0.email })
                vc.setSubject(mail.subject)
                vc.setMessageBody(mail.body, isHTML: false)

                for att in mail.attachments {
                    if let data = try? Data(contentsOf: att.url) {
                        vc.addAttachmentData(data, mimeType: att.mimeType, fileName: att.filename)
                    }
                }

                coordinator.retainSelf()  // se mantiene vivo hasta el callback del delegate
                presenter.present(vc, animated: true)
            }
        }
    }

    /// Localiza el view controller más alto desde el que presentar.
    @MainActor
    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes
        let window = scenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })
            ?? scenes.compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }.first

        var top = window?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        if let nav = top as? UINavigationController { top = nav.visibleViewController ?? nav }
        if let tab = top as? UITabBarController { top = tab.selectedViewController ?? tab }
        return top
    }
}

/// Puente entre el callback del delegate y la continuación async.
private final class ComposerCoordinator: NSObject, MFMailComposeViewControllerDelegate {

    private let messageID: String
    private var continuation: CheckedContinuation<SentReceipt, Error>?
    private var strongSelf: ComposerCoordinator?

    init(messageID: String, continuation: CheckedContinuation<SentReceipt, Error>) {
        self.messageID = messageID
        self.continuation = continuation
    }

    /// Auto-retención: el delegate de MFMailComposeViewController es weak, así que
    /// nos mantenemos vivos hasta recibir el callback.
    func retainSelf() { strongSelf = self }

    func mailComposeController(_ controller: MFMailComposeViewController,
                               didFinishWith result: MFMailComposeResult,
                               error: Error?) {
        controller.dismiss(animated: true) { [self] in
            defer { self.strongSelf = nil }
            guard let cont = continuation else { return }
            continuation = nil

            if let error {
                cont.resume(throwing: MailError.conexion(error.localizedDescription))
                return
            }
            switch result {
            case .sent:
                cont.resume(returning: SentReceipt(messageID: messageID, fecha: Date(), metodo: .composer))
            case .cancelled, .saved:
                // Guardado en borradores tampoco es un envío efectivo.
                cont.resume(throwing: MailError.canceladoPorUsuario)
            case .failed:
                cont.resume(throwing: MailError.conexion("Falló el envío desde el compositor de correo."))
            @unknown default:
                cont.resume(throwing: MailError.canceladoPorUsuario)
            }
        }
    }
}
