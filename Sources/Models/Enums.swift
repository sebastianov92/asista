import Foundation

// Enumeraciones del dominio. Todas Codable para poder almacenarlas en SwiftData
// como propiedades escalares o dentro de arreglos.

// MARK: - Destinatario

enum TipoDestinatario: String, Codable, CaseIterable {
    case to, cc, bcc

    var etiqueta: String {
        switch self {
        case .to: return "Para"
        case .cc: return "Cc"
        case .bcc: return "Cco"
        }
    }
}

// MARK: - Paciente

enum Parentesco: String, Codable, CaseIterable {
    case titular, conyuge, hijo, hija, padre, madre, otro

    var etiqueta: String {
        switch self {
        case .titular: return "Titular"
        case .conyuge: return "Cónyuge"
        case .hijo: return "Hijo"
        case .hija: return "Hija"
        case .padre: return "Padre"
        case .madre: return "Madre"
        case .otro: return "Otro"
        }
    }
}

// MARK: - Reclamo

enum EstadoReclamo: String, Codable, CaseIterable {
    case borrador, enviado, enRevision, aprobado, pagado, rechazado, requiereDocumentos

    var etiqueta: String {
        switch self {
        case .borrador: return "Borrador"
        case .enviado: return "Enviado"
        case .enRevision: return "En revisión"
        case .aprobado: return "Aprobado"
        case .pagado: return "Pagado"
        case .rechazado: return "Rechazado"
        case .requiereDocumentos: return "Requiere documentos"
        }
    }

    /// Nombre de símbolo SF Symbols para la UI.
    var simbolo: String {
        switch self {
        case .borrador: return "doc.text"
        case .enviado: return "paperplane"
        case .enRevision: return "hourglass"
        case .aprobado: return "checkmark.seal"
        case .pagado: return "dollarsign.circle"
        case .rechazado: return "xmark.circle"
        case .requiereDocumentos: return "exclamationmark.triangle"
        }
    }

    /// Cuenta para el panel "Pendiente de cobro" (§15.1): enviado, en revisión,
    /// aprobado y requiere documentos. Borrador/pagado/rechazado no.
    var cuentaEnPendiente: Bool {
        switch self {
        case .enviado, .enRevision, .aprobado, .requiereDocumentos: return true
        case .borrador, .pagado, .rechazado: return false
        }
    }

    var esTerminal: Bool { self == .pagado || self == .rechazado }
}

// MARK: - Documento

enum TipoDocumento: String, Codable, CaseIterable {
    case receta
    case facturaMedico
    case facturaReceta
    case ordenExamenes
    case resultadoExamenes
    case facturaExamenes
    case informeMedico
    case formularioAseguradora
    case cedula
    case liquidacionAseguradora   // para reclamos secundarios
    case certificadoAfiliacion
    case otro

    /// Nombre corto ASCII usado en el nombre de archivo (sin tildes ni espacios).
    var slug: String {
        switch self {
        case .receta: return "Receta"
        case .facturaMedico: return "Factura-Medico"
        case .facturaReceta: return "Factura-Receta"
        case .ordenExamenes: return "Orden-Examenes"
        case .resultadoExamenes: return "Resultado-Examenes"
        case .facturaExamenes: return "Factura-Examenes"
        case .informeMedico: return "Informe-Medico"
        case .formularioAseguradora: return "Formulario"
        case .cedula: return "Cedula"
        case .liquidacionAseguradora: return "Liquidacion"
        case .certificadoAfiliacion: return "Certificado"
        case .otro: return "Documento"
        }
    }

    var etiqueta: String {
        switch self {
        case .receta: return "Receta"
        case .facturaMedico: return "Factura del médico"
        case .facturaReceta: return "Factura de receta"
        case .ordenExamenes: return "Orden de exámenes"
        case .resultadoExamenes: return "Resultado de exámenes"
        case .facturaExamenes: return "Factura de exámenes"
        case .informeMedico: return "Informe médico"
        case .formularioAseguradora: return "Formulario de la aseguradora"
        case .cedula: return "Cédula"
        case .liquidacionAseguradora: return "Liquidación de aseguradora"
        case .certificadoAfiliacion: return "Certificado de afiliación"
        case .otro: return "Otro"
        }
    }

    /// Si es true, se intenta extraer monto por OCR (§7).
    var esFacturable: Bool {
        switch self {
        case .facturaMedico, .facturaReceta, .facturaExamenes: return true
        default: return false
        }
    }

    var simbolo: String {
        switch self {
        case .receta: return "pills"
        case .facturaMedico, .facturaReceta, .facturaExamenes: return "dollarsign.square"
        case .ordenExamenes: return "list.clipboard"
        case .resultadoExamenes: return "waveform.path.ecg"
        case .informeMedico: return "doc.text.magnifyingglass"
        case .formularioAseguradora: return "doc.badge.gearshape"
        case .cedula: return "person.text.rectangle"
        case .liquidacionAseguradora: return "doc.plaintext"
        case .certificadoAfiliacion: return "checkmark.rectangle"
        case .otro: return "doc"
        }
    }
}

enum FiltroEscaneo: String, Codable, CaseIterable {
    case original       // color tal cual
    case documento      // realce de contraste, fondo blanco (por defecto)
    case escalaGrises
    case blancoYNegro

    var etiqueta: String {
        switch self {
        case .original: return "Original"
        case .documento: return "Documento"
        case .escalaGrises: return "Escala de grises"
        case .blancoYNegro: return "Blanco y negro"
        }
    }
}

enum PreajusteCalidad: String, Codable, CaseIterable {
    case alta, media, baja

    var etiqueta: String {
        switch self {
        case .alta: return "Alta"
        case .media: return "Media"
        case .baja: return "Baja"
        }
    }

    /// Lado largo máximo en px (§6.2).
    var ladoLargo: CGFloat {
        switch self {
        case .alta: return 2400
        case .media: return 1800
        case .baja: return 1200
        }
    }

    /// Calidad JPEG (§6.2).
    var calidadJPEG: CGFloat {
        switch self {
        case .alta: return 0.75
        case .media: return 0.60
        case .baja: return 0.45
        }
    }
}

// MARK: - Envío

enum MetodoEnvio: String, Codable { case smtp, composer }

enum EstadoEnvio: String, Codable {
    case pendiente, enviando, enviado, fallido

    var etiqueta: String {
        switch self {
        case .pendiente: return "Pendiente"
        case .enviando: return "Enviando…"
        case .enviado: return "Enviado"
        case .fallido: return "Falló"
        }
    }
}
