import Foundation
import SwiftData

// Orquesta el envío: arma OutgoingMail desde el Reclamo, elige el MailSender,
// registra el Envio, actualiza estado y crea el EventoMedico automático.

struct BorradorEnvio {
    var asunto: String
    var cuerpo: String
    var to: [String]
    var cc: [String]
    var bcc: [String]
    var adjuntos: [Attachment]
    var tamanoTotal: Int
}

@MainActor
enum EnvioCoordinator {

    /// Construye el borrador (sujeto a edición del usuario en la pantalla de envío).
    static func borrador(
        _ reclamo: Reclamo,
        plantillaGlobal: PlantillaCorreo?,
        miEmail: String,
        copiaPropiaActiva: Bool
    ) -> BorradorEnvio {
        let plantilla = TemplateEngine.render(reclamo, plantillaGlobal: plantillaGlobal)
        let dest = RecipientResolver.resolver(
            reclamo,
            copiaPropiaEmail: copiaPropiaActiva ? miEmail : nil
        )

        // Adjuntos: un PDF por documento, en orden.
        var adjuntos: [Attachment] = []
        var total = 0
        for doc in reclamo.documentos.sorted(by: { $0.orden < $1.orden }) where !doc.rutaPDF.isEmpty {
            let url = FileStore.urlPDF(nombre: doc.rutaPDF)
            adjuntos.append(Attachment(url: url, filename: doc.rutaPDF, mimeType: "application/pdf"))
            total += FileStore.tamano(url)
        }

        // Seguimiento: anteponer "Re: " al asunto (§8.4) si ya hubo envíos.
        let yaEnviado = reclamo.envios.contains { $0.estado == .enviado }
        let asunto = yaEnviado ? "Re: \(plantilla.asunto)" : plantilla.asunto

        return BorradorEnvio(
            asunto: asunto,
            cuerpo: plantilla.cuerpo,
            to: dest.to, cc: dest.cc, bcc: dest.bcc,
            adjuntos: adjuntos,
            tamanoTotal: total
        )
    }

    enum ResultadoEnvio {
        case exito(SentReceipt)
        case fallo(String)
    }

    /// Envía y persiste. Devuelve el Envio creado (queda .enviado, .fallido o
    /// .pendiente según el resultado / la cola).
    static func enviar(
        _ reclamo: Reclamo,
        borrador: BorradorEnvio,
        ctx: ModelContext,
        settings: AppSettings
    ) async -> ResultadoEnvio {

        let miEmail = settings.miEmail
        let from = EmailAddress(miEmail, nombre: "")

        // Continuidad de hilo (§8.4): el primer envío genera el Message-ID base;
        // los siguientes responden a él.
        let previos = reclamo.envios
            .filter { !$0.messageID.isEmpty }
            .sorted { $0.fecha < $1.fecha }
        let messageID = "\(UUID().uuidString)@asista.app"
        let inReplyTo = previos.first?.messageID
        let references = previos.map(\.messageID)

        let mail = OutgoingMail(
            from: from,
            to: borrador.to.map { EmailAddress($0) },
            cc: borrador.cc.map { EmailAddress($0) },
            bcc: borrador.bcc.map { EmailAddress($0) },
            subject: borrador.asunto,
            body: borrador.cuerpo,
            attachments: borrador.adjuntos,
            messageID: messageID,
            inReplyTo: inReplyTo,
            references: references
        )

        // Registrar el Envio antes de intentar (para la cola / historial).
        let envio = Envio()
        envio.reclamo = reclamo
        envio.asunto = borrador.asunto
        envio.cuerpo = borrador.cuerpo
        envio.destinatariosTo = borrador.to
        envio.destinatariosCc = borrador.cc
        envio.adjuntos = borrador.adjuntos.map(\.filename)
        envio.tamanoTotalBytes = borrador.tamanoTotal
        envio.messageID = messageID
        envio.inReplyTo = inReplyTo
        envio.references = references
        envio.estado = .enviando
        envio.intentos = 1
        ctx.insert(envio)

        // Elegir sender.
        let usarComposer = settings.preferirComposer || !KeychainStore.hayCredenciales
        let sender: MailSender = usarComposer
            ? ComposerMailSender()
            : SMTPMailSender(credentialsProvider: {
                guard let c = KeychainStore.leer() else { return nil }
                return SMTPCredentials(usuario: c.usuario, appPassword: c.appPassword,
                                       host: c.host, puerto: UInt16(c.puerto))
            })
        envio.metodo = usarComposer ? .composer : .smtp

        do {
            let receipt = try await sender.send(mail)
            envio.estado = .enviado
            envio.fecha = receipt.fecha
            marcarEnviado(reclamo, ctx: ctx)
            try? ctx.save()
            return .exito(receipt)
        } catch {
            // Sin red o fallo transitorio → queda en la cola para reintento (§8.5).
            envio.estado = esReintentable(error) ? .pendiente : .fallido
            envio.errorDescripcion = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            try? ctx.save()
            return .fallo(envio.errorDescripcion)
        }
    }

    /// Reintenta un Envio existente (no crea uno nuevo) — usado por la cola.
    static func reintentar(_ envio: Envio, ctx: ModelContext, settings: AppSettings) async {
        guard envio.intentos < SendQueue.maxIntentos else {
            envio.estado = .fallido
            try? ctx.save()
            return
        }

        let from = EmailAddress(settings.miEmail, nombre: "")
        let adjuntos = envio.adjuntos.map {
            Attachment(url: FileStore.urlPDF(nombre: $0), filename: $0, mimeType: "application/pdf")
        }
        let mail = OutgoingMail(
            from: from,
            to: envio.destinatariosTo.map { EmailAddress($0) },
            cc: envio.destinatariosCc.map { EmailAddress($0) },
            bcc: [],
            subject: envio.asunto,
            body: envio.cuerpo,
            attachments: adjuntos,
            messageID: envio.messageID,
            inReplyTo: envio.inReplyTo,
            references: envio.references
        )

        envio.estado = .enviando
        envio.intentos += 1
        envio.fecha = Date()

        // La cola solo corre con SMTP; el composer requiere UI (no reintentable en background).
        guard KeychainStore.hayCredenciales, !settings.preferirComposer else {
            envio.estado = .pendiente
            try? ctx.save()
            return
        }
        let sender = SMTPMailSender(credentialsProvider: {
            guard let c = KeychainStore.leer() else { return nil }
            return SMTPCredentials(usuario: c.usuario, appPassword: c.appPassword,
                                   host: c.host, puerto: UInt16(c.puerto))
        })

        do {
            let receipt = try await sender.send(mail)
            envio.estado = .enviado
            envio.fecha = receipt.fecha
            envio.errorDescripcion = ""
            if let reclamo = envio.reclamo { marcarEnviado(reclamo, ctx: ctx) }
        } catch {
            envio.errorDescripcion = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            envio.estado = (envio.intentos >= SendQueue.maxIntentos || !esReintentable(error)) ? .fallido : .pendiente
        }
        try? ctx.save()
    }

    /// Errores de red/timeout se reintentan; credenciales/tamaño no.
    private static func esReintentable(_ error: Error) -> Bool {
        switch error {
        case MailError.timeout, MailError.conexion:
            return true
        case MailError.credencialesRechazadas, MailError.requiereAppPassword,
             MailError.correoDemasiadoGrande, MailError.sinCredenciales:
            return false
        default:
            return true
        }
    }

    /// Al pasar a .enviado por primera vez: subir estado y crear EventoMedico (§3.3).
    private static func marcarEnviado(_ reclamo: Reclamo, ctx: ModelContext) {
        let primero = reclamo.estado == .borrador
        if reclamo.estado == .borrador || reclamo.estado == .requiereDocumentos {
            reclamo.estado = .enviado
        }
        guard primero else { return }
        let evento = EventoMedico(titulo: "Reclamo #\(reclamo.numero) enviado")
        evento.paciente = reclamo.cobertura?.paciente
        evento.fecha = Date()
        evento.medico = reclamo.medico
        evento.diagnostico = reclamo.diagnostico
        evento.descripcion = reclamo.prestador
        evento.reclamoRelacionado = reclamo
        evento.creadoAutomaticamente = true
        ctx.insert(evento)
    }
}
