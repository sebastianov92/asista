import Foundation
import SwiftData

// Modelo de datos completo (§3). Esquema CERRADO desde la Fase 1: aunque parte
// de la UI aún no exista, migrar SwiftData después es costoso.

// MARK: - Aseguradora

@Model
final class Aseguradora {
    var id: UUID = UUID()
    var nombre: String = ""
    var colorHex: String?
    var logoData: Data?
    var notas: String = ""

    @Relationship(deleteRule: .cascade)
    var formulariosEnBlanco: [FormularioEnBlanco] = []

    /// Plantilla a nivel de aseguradora. Aplica a todas sus pólizas salvo que una
    /// póliza defina la suya (§9).
    @Relationship(deleteRule: .cascade)
    var plantilla: PlantillaCorreo?

    @Relationship(deleteRule: .cascade, inverse: \Poliza.aseguradora)
    var polizas: [Poliza] = []

    init(nombre: String = "") {
        self.nombre = nombre
    }
}

@Model
final class FormularioEnBlanco {
    var id: UUID = UUID()
    var nombre: String = ""          // "Formulario de reembolso 2026"
    var rutaArchivo: String = ""     // relativa al contenedor
    var requiereFirmaMedico: Bool = true

    init(nombre: String = "", rutaArchivo: String = "") {
        self.nombre = nombre
        self.rutaArchivo = rutaArchivo
    }
}

// MARK: - Póliza

@Model
final class Poliza {
    var id: UUID = UUID()
    var numero: String = ""
    var alias: String = ""           // "Seguro de la empresa", "Privado familiar"
    var aseguradora: Aseguradora?

    var contratante: String = ""     // empresa o titular particular
    var vigenciaDesde: Date?
    var vigenciaHasta: Date?

    var deducibleAnual: Decimal?
    var topeAnual: Decimal?
    var porcentajeCobertura: Double? // 0.0 - 1.0, informativo

    /// Prioridad cuando un paciente tiene varias pólizas. Menor = se usa primero.
    var prioridad: Int = 0

    @Relationship(deleteRule: .cascade)
    var destinatarios: [Destinatario] = []

    @Relationship(deleteRule: .cascade)
    var plantilla: PlantillaCorreo?

    /// Tipos de documento que esta póliza exige por defecto.
    var checklistPorDefecto: [TipoDocumento] = []

    @Relationship(deleteRule: .cascade, inverse: \Cobertura.poliza)
    var coberturas: [Cobertura] = []

    init(numero: String = "", alias: String = "") {
        self.numero = numero
        self.alias = alias
    }

    var nombreVisible: String {
        alias.isEmpty ? numero : alias
    }
}

@Model
final class Destinatario {
    var id: UUID = UUID()
    var nombre: String = ""
    var email: String = ""
    var tipo: TipoDestinatario = TipoDestinatario.to
    var activo: Bool = true

    init(nombre: String = "", email: String = "", tipo: TipoDestinatario = .to) {
        self.nombre = nombre
        self.email = email
        self.tipo = tipo
    }
}

// MARK: - Paciente

@Model
final class Paciente {
    var id: UUID = UUID()
    var nombres: String = ""
    var apellidos: String = ""
    var cedula: String = ""
    var fechaNacimiento: Date?
    var parentesco: Parentesco = Parentesco.titular
    var fotoData: Data?

    // Historial médico estático
    var tipoSangre: String = ""
    var alergias: [String] = []
    var condicionesCronicas: [String] = []
    var medicacionHabitual: [String] = []
    var notasMedicas: String = ""

    @Relationship(deleteRule: .cascade, inverse: \Cobertura.paciente)
    var coberturas: [Cobertura] = []

    @Relationship(deleteRule: .cascade, inverse: \EventoMedico.paciente)
    var eventos: [EventoMedico] = []

    @Relationship(deleteRule: .cascade, inverse: \Medicamento.paciente)
    var medicamentos: [Medicamento] = []

    init(nombres: String = "", apellidos: String = "") {
        self.nombres = nombres
        self.apellidos = apellidos
    }

    var nombreCompleto: String {
        "\(nombres) \(apellidos)".trimmingCharacters(in: .whitespaces)
    }

    var edad: Int? {
        guard let fechaNacimiento else { return nil }
        return Calendar.current.dateComponents([.year], from: fechaNacimiento, to: Date()).year
    }
}

// MARK: - Cobertura (join Paciente ↔ Póliza)

@Model
final class Cobertura {
    var id: UUID = UUID()
    var paciente: Paciente?
    var poliza: Poliza?

    /// Número de certificado/afiliado individual dentro de la póliza.
    var numeroCertificado: String = ""
    var activa: Bool = true

    /// Si no está vacío, REEMPLAZA a los destinatarios de la póliza (§4).
    @Relationship(deleteRule: .cascade)
    var destinatariosOverride: [Destinatario] = []

    var deducibleConsumido: Decimal = 0

    init(paciente: Paciente? = nil, poliza: Poliza? = nil) {
        self.paciente = paciente
        self.poliza = poliza
    }

    var etiqueta: String {
        let p = paciente?.nombreCompleto ?? "?"
        let pol = poliza?.nombreVisible ?? "?"
        return "\(p) — \(pol)"
    }
}

// MARK: - Reclamo

@Model
final class Reclamo {
    var id: UUID = UUID()
    var numero: Int = 0              // consecutivo local, referencia humana
    var cobertura: Cobertura?

    var fechaEvento: Date = Date()
    var fechaCreacion: Date = Date()
    var diagnostico: String = ""
    var codigoCIE10: String = ""
    var prestador: String = ""       // clínica, laboratorio, farmacia
    var medico: String = ""

    var estado: EstadoReclamo = EstadoReclamo.borrador
    var montoReclamado: Decimal = 0
    var montoManual: Bool = false    // true si el usuario fijó el monto a mano
    var montoReembolsado: Decimal?
    var fechaReembolso: Date?
    var motivoRechazo: String = ""

    /// Para reclamos secundarios (coordinación de beneficios).
    var reclamoOrigen: Reclamo?

    /// Copia del paciente/póliza/aseguradora al momento de crear el reclamo.
    /// Así el reclamo "dice" con qué póliza se hizo aunque después cambies de
    /// seguro o borres esa póliza.
    var pacienteSnapshot: String = ""
    var polizaSnapshot: String = ""
    var aseguradoraSnapshot: String = ""
    var certificadoSnapshot: String = ""

    /// Overrides puntuales de este reclamo.
    var destinatariosExtra: [String] = []
    var asuntoOverride: String?
    var cuerpoOverride: String?

    /// Checklist efectivo del reclamo (parte del de la póliza, editable por reclamo).
    var checklist: [TipoDocumento] = []

    @Relationship(deleteRule: .cascade, inverse: \Documento.reclamo)
    var documentos: [Documento] = []

    @Relationship(deleteRule: .cascade, inverse: \Envio.reclamo)
    var envios: [Envio] = []

    var notas: String = ""

    init(cobertura: Cobertura? = nil) {
        self.cobertura = cobertura
    }

    var pendiente: Decimal {
        montoReclamado - (montoReembolsado ?? 0)
    }

    /// Toma el snapshot actual de la cobertura (llamar al crear el reclamo).
    func tomarSnapshot() {
        pacienteSnapshot = cobertura?.paciente?.nombreCompleto ?? pacienteSnapshot
        polizaSnapshot = cobertura?.poliza?.nombreVisible ?? polizaSnapshot
        aseguradoraSnapshot = cobertura?.poliza?.aseguradora?.nombre ?? aseguradoraSnapshot
        certificadoSnapshot = cobertura?.numeroCertificado ?? certificadoSnapshot
    }

    // Accesores que caen al snapshot si la cobertura/póliza ya no existe.
    var pacienteNombre: String { cobertura?.paciente?.nombreCompleto ?? pacienteSnapshot }
    var polizaNombre: String { cobertura?.poliza?.nombreVisible ?? polizaSnapshot }
    var aseguradoraNombre: String { cobertura?.poliza?.aseguradora?.nombre ?? aseguradoraSnapshot }
}

// MARK: - Documento

@Model
final class Documento {
    var id: UUID = UUID()
    var reclamo: Reclamo?
    var tipo: TipoDocumento = TipoDocumento.otro
    var tipoPersonalizado: String = ""   // si tipo == .otro
    var orden: Int = 0

    /// Ruta relativa del PDF generado.
    var rutaPDF: String = ""
    var tamanoBytes: Int = 0
    var preajusteCalidad: PreajusteCalidad = PreajusteCalidad.media

    // Datos extraídos por OCR (editables por el usuario)
    var monto: Decimal?
    var fechaDocumento: Date?
    var emisor: String = ""
    var ruc: String = ""
    var numeroFactura: String = ""
    var textoOCR: String = ""
    var ocrConfirmadoPorUsuario: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \PaginaEscaneada.documento)
    var paginas: [PaginaEscaneada] = []

    init(tipo: TipoDocumento = .otro, orden: Int = 0) {
        self.tipo = tipo
        self.orden = orden
    }

    var etiqueta: String {
        tipo == .otro && !tipoPersonalizado.isEmpty ? tipoPersonalizado : tipo.etiqueta
    }
}

@Model
final class PaginaEscaneada {
    var id: UUID = UUID()
    var documento: Documento?
    var orden: Int = 0
    /// Imagen original recortada por VisionKit, sin filtro. Se conserva para
    /// poder cambiar de filtro sin re-escanear.
    var rutaOriginal: String = ""
    var filtro: FiltroEscaneo = FiltroEscaneo.documento
    var rotacion: Int = 0   // 0, 90, 180, 270

    init(orden: Int = 0, rutaOriginal: String = "") {
        self.orden = orden
        self.rutaOriginal = rutaOriginal
    }
}

// MARK: - Envío

@Model
final class Envio {
    var id: UUID = UUID()
    var reclamo: Reclamo?
    var fecha: Date = Date()
    var asunto: String = ""
    var cuerpo: String = ""
    var destinatariosTo: [String] = []
    var destinatariosCc: [String] = []
    var adjuntos: [String] = []      // rutas de los PDFs tal como se enviaron
    var tamanoTotalBytes: Int = 0

    /// Message-ID generado por la app. Base del hilo.
    var messageID: String = ""
    /// Message-ID al que este envío responde (nil en el primer envío).
    var inReplyTo: String?
    var references: [String] = []

    var metodo: MetodoEnvio = MetodoEnvio.smtp
    var estado: EstadoEnvio = EstadoEnvio.pendiente
    var errorDescripcion: String = ""
    var intentos: Int = 0

    init() {}
}

// MARK: - Plantilla

@Model
final class PlantillaCorreo {
    var id: UUID = UUID()
    var nombre: String = ""
    var asunto: String = ""
    var cuerpo: String = ""
    var esGlobalPorDefecto: Bool = false

    init(nombre: String = "", asunto: String = "", cuerpo: String = "") {
        self.nombre = nombre
        self.asunto = asunto
        self.cuerpo = cuerpo
    }
}

// MARK: - Medicación / recetas (alarmas de toma)

/// Una pauta de medicación de un paciente. Genera alarmas cada `cadaHoras` desde
/// `fechaInicio` durante `duracionDias` (0 = indefinido).
@Model
final class Medicamento {
    var id: UUID = UUID()
    var paciente: Paciente?
    var nombre: String = ""            // "Amoxicilina 500mg"
    var dosis: String = ""             // "1 pastilla"
    var instrucciones: String = ""     // "con comida", "no acostarse después"
    var cadaHoras: Int = 8
    var fechaInicio: Date = Date()     // incluye la hora de la primera toma
    var duracionDias: Int = 0          // 0 = indefinido
    /// Nº total de tomas (cuando la receta da cantidad de pastillas, no días).
    /// 0 = usar duracionDias. Tiene prioridad sobre duracionDias.
    var dosisTotales: Int = 0
    var activa: Bool = true
    /// Usar sonido de alarma fuerte en vez del sonido de notificación normal.
    var sonarComoAlarma: Bool = true
    /// Enlace opcional a la receta escaneada (documento del reclamo).
    var documentoRutaPDF: String = ""

    @Relationship(deleteRule: .cascade, inverse: \TomaMedicamento.medicamento)
    var tomas: [TomaMedicamento] = []

    init(nombre: String = "", cadaHoras: Int = 8) {
        self.nombre = nombre
        self.cadaHoras = cadaHoras
    }

    /// Tomas realmente confirmadas por el usuario.
    var tomasConfirmadas: Int { tomas.filter { $0.estado == .tomada }.count }

    /// Adherencia: confirmadas / esperadas hasta ahora (0–1). nil si aún no toca ninguna.
    var adherencia: Double? {
        let esperadas = tomasDadas
        guard esperadas > 0 else { return nil }
        return min(1, Double(tomasConfirmadas) / Double(esperadas))
    }

    var fechaFin: Date? {
        // Por cantidad de tomas: última toma = inicio + (n-1) intervalos.
        if dosisTotales > 0, cadaHoras > 0 {
            let seg = TimeInterval((dosisTotales - 1) * cadaHoras) * 3600
            return fechaInicio.addingTimeInterval(seg)
        }
        guard duracionDias > 0 else { return nil }
        return Calendar.current.date(byAdding: .day, value: duracionDias, to: fechaInicio)
    }

    var tomasPorDia: Int { cadaHoras > 0 ? max(1, 24 / cadaHoras) : 1 }

    /// Total de tomas del tratamiento (por cantidad o por días). nil = indefinido.
    var totalTomas: Int? {
        if dosisTotales > 0 { return dosisTotales }
        if duracionDias > 0 { return duracionDias * tomasPorDia }
        return nil
    }

    /// Tomas que ya deberían haberse dado hasta ahora.
    var tomasDadas: Int {
        let ahora = Date()
        guard ahora >= fechaInicio, cadaHoras > 0 else { return 0 }
        let intervalo = TimeInterval(cadaHoras) * 3600
        let n = Int(ahora.timeIntervalSince(fechaInicio) / intervalo) + 1
        if let t = totalTomas { return min(n, t) }
        return n
    }

    var tomasRestantes: Int? {
        guard let t = totalTomas else { return nil }
        return max(0, t - tomasDadas)
    }

    /// Próxima toma futura (nil si terminó o está pausada).
    var proximaToma: Date? {
        guard activa, cadaHoras > 0 else { return nil }
        let ahora = Date()
        if ahora < fechaInicio { return fechaInicio }
        let intervalo = TimeInterval(cadaHoras) * 3600
        let saltos = (ahora.timeIntervalSince(fechaInicio) / intervalo).rounded(.down) + 1
        let siguiente = fechaInicio.addingTimeInterval(saltos * intervalo)
        if let fin = fechaFin, siguiente > fin { return nil }
        return siguiente
    }

    var terminado: Bool {
        if let fin = fechaFin { return Date() > fin }
        return false
    }

    /// En curso ahora mismo (activa, ya empezó y no terminó).
    var enCurso: Bool { activa && !terminado && Date() >= fechaInicio }

    /// Programada para el futuro.
    var programada: Bool { activa && Date() < fechaInicio }

    var resumen: String {
        var s = dosis.isEmpty ? nombre : "\(dosis) de \(nombre)"
        s += " cada \(cadaHoras)h"
        if dosisTotales > 0 { s += " · \(dosisTotales) tomas" }
        else if duracionDias > 0 { s += " · \(duracionDias) días" }
        if !instrucciones.isEmpty { s += " · \(instrucciones)" }
        return s
    }
}

// MARK: - Directorio de contactos (§11)

/// Médicos y prestadores. Se alimenta de los nombres usados en los reclamos
/// (autocompletado) y guarda especialidad/teléfono cuando se conocen.
@Model
final class Contacto {
    var id: UUID = UUID()
    var nombre: String = ""
    var tipoRaw: String = TipoContacto.medico.rawValue
    var especialidad: String = ""
    var telefono: String = ""
    var notas: String = ""

    init(nombre: String = "", tipo: TipoContacto = .medico) {
        self.nombre = nombre
        self.tipoRaw = tipo.rawValue
    }

    var tipo: TipoContacto {
        get { TipoContacto(rawValue: tipoRaw) ?? .medico }
        set { tipoRaw = newValue.rawValue }
    }
}

/// Registro de una toma (adherencia).
@Model
final class TomaMedicamento {
    var id: UUID = UUID()
    var medicamento: Medicamento?
    var fecha: Date = Date()
    var estadoRaw: String = EstadoToma.tomada.rawValue

    init(estado: EstadoToma = .tomada, fecha: Date = Date()) {
        self.estadoRaw = estado.rawValue
        self.fecha = fecha
    }

    var estado: EstadoToma {
        get { EstadoToma(rawValue: estadoRaw) ?? .tomada }
        set { estadoRaw = newValue.rawValue }
    }
}

enum EstadoToma: String, Codable, CaseIterable {
    case tomada, pospuesta, saltada
    var etiqueta: String {
        switch self {
        case .tomada: return "Tomada"
        case .pospuesta: return "Pospuesta"
        case .saltada: return "Saltada"
        }
    }
}

enum TipoContacto: String, Codable, CaseIterable {
    case medico, prestador
    var etiqueta: String { self == .medico ? "Médico" : "Prestador" }
    var simbolo: String { self == .medico ? "stethoscope" : "building.2" }
}

// MARK: - Historial médico

@Model
final class EventoMedico {
    var id: UUID = UUID()
    var paciente: Paciente?
    var fecha: Date = Date()
    var titulo: String = ""
    var descripcion: String = ""
    var medico: String = ""
    var especialidad: String = ""
    var diagnostico: String = ""
    /// Si nació de un reclamo, se enlaza para poder ver los documentos.
    var reclamoRelacionado: Reclamo?
    var creadoAutomaticamente: Bool = false

    init(titulo: String = "") {
        self.titulo = titulo
    }
}
