# Spec: App de Reclamos de Seguros Médicos (iOS)

> Nombre provisional: **Reclamos**. Cambiar antes de crear el proyecto Xcode.
> Público: uso personal/familiar. Ecuador. Moneda USD.
> Documento destinado a implementación con Claude Code.

---

## 1. Objetivo

Reducir a minutos el proceso de armar y enviar un reclamo de seguro médico: escanear los documentos físicos con la cámara, convertirlos en PDFs livianos y bien nombrados, y enviarlos en **un solo correo** a los destinatarios correctos, manteniendo todo el seguimiento en un mismo hilo de conversación.

Principios de diseño:

- **Local-first**: sin backend. Todo vive en el dispositivo. Son datos médicos.
- **Un correo, no varios**: todos los destinatarios en el mismo mensaje (To/Cc) para que la conversación sea única.
- **Continuidad de hilo**: los envíos posteriores de un mismo reclamo responden al hilo original.
- **Cero fricción en el caso común**: escanear → confirmar → enviar.

---

## 2. Stack técnico

| Área | Tecnología |
|---|---|
| UI | SwiftUI, iOS 17+ |
| Persistencia | SwiftData |
| Escaneo | VisionKit (`VNDocumentCameraViewController`) |
| OCR | Vision (`VNRecognizeTextRequest`) |
| Filtros de imagen | Core Image |
| PDF | PDFKit |
| Red / SMTP | Network.framework (`NWConnection` + TLS) |
| Credenciales | Keychain (`kSecClassGenericPassword`) |
| Autenticación local | LocalAuthentication (Face ID / Touch ID) |
| Notificaciones | UserNotifications |

Archivos PDF y páginas escaneadas en el contenedor de la app con `FileProtectionType.complete`. Nada en `UserDefaults` salvo preferencias no sensibles.

**Arquitectura**: MVVM ligero. Capas separadas para `Scanning`, `PDFBuilding`, `OCR`, `Mail`. Cada una detrás de un protocolo para poder testear sin dispositivo.

---

## 3. Modelo de datos

### 3.1 Diagrama

```
Aseguradora
    └── Poliza (1:N)
            ├── Destinatario[] (1:N)
            ├── PlantillaCorreo (1:1, opcional)
            ├── TipoDocumentoRequerido[] (checklist)
            └── Cobertura (1:N)  ◄──── Paciente (1:N)
                                            └── EventoMedico[] (historial)

Reclamo
    ├── → Cobertura (paciente + póliza resueltos)
    ├── → reclamoOrigen (opcional, para reclamos secundarios)
    ├── Documento[] (1:N)
    │       └── PaginaEscaneada[] (1:N)
    └── Envio[] (1:N)
```

### 3.2 Modelos SwiftData

```swift
import SwiftData
import Foundation

// MARK: - Aseguradora

@Model
final class Aseguradora {
    var id: UUID = UUID()
    var nombre: String = ""
    var colorHex: String?
    var logoData: Data?
    /// Formularios en blanco que la aseguradora exige (PDF).
    var formulariosEnBlanco: [FormularioEnBlanco] = []
    var notas: String = ""

    /// Plantilla de correo a nivel de aseguradora. Aplica a todas sus pólizas
    /// salvo que una póliza defina la suya. Ver §9.
    @Relationship(deleteRule: .cascade)
    var plantilla: PlantillaCorreo?

    @Relationship(deleteRule: .cascade, inverse: \Poliza.aseguradora)
    var polizas: [Poliza] = []
}

@Model
final class FormularioEnBlanco {
    var id: UUID = UUID()
    var nombre: String = ""          // "Formulario de reembolso 2026"
    var rutaArchivo: String = ""     // relativa al contenedor
    var requiereFirmaMedico: Bool = true
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
}

@Model
final class Destinatario {
    var id: UUID = UUID()
    var nombre: String = ""
    var email: String = ""
    var tipo: TipoDestinatario = TipoDestinatario.to
    var activo: Bool = true
}

enum TipoDestinatario: String, Codable, CaseIterable {
    case to, cc, bcc
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

    var nombreCompleto: String { "\(nombres) \(apellidos)".trimmingCharacters(in: .whitespaces) }
    var edad: Int? { /* calcular desde fechaNacimiento */ nil }
}

enum Parentesco: String, Codable, CaseIterable {
    case titular, conyuge, hijo, hija, padre, madre, otro
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

    /// Si no está vacío, REEMPLAZA a los destinatarios de la póliza.
    @Relationship(deleteRule: .cascade)
    var destinatariosOverride: [Destinatario] = []

    var deducibleConsumido: Decimal = 0
}

// MARK: - Reclamo

@Model
final class Reclamo {
    var id: UUID = UUID()
    var numero: Int = 0              // consecutivo local, para referencia humana
    var cobertura: Cobertura?

    var fechaEvento: Date = Date()
    var fechaCreacion: Date = Date()
    var diagnostico: String = ""
    var codigoCIE10: String = ""
    var prestador: String = ""       // clínica, laboratorio, farmacia
    var medico: String = ""

    var estado: EstadoReclamo = EstadoReclamo.borrador
    var montoReclamado: Decimal = 0
    var montoReembolsado: Decimal?
    var fechaReembolso: Date?
    var motivoRechazo: String = ""

    /// Para reclamos secundarios (coordinación de beneficios).
    var reclamoOrigen: Reclamo?

    /// Overrides puntuales de este reclamo.
    var destinatariosExtra: [String] = []
    var asuntoOverride: String?
    var cuerpoOverride: String?

    @Relationship(deleteRule: .cascade, inverse: \Documento.reclamo)
    var documentos: [Documento] = []

    @Relationship(deleteRule: .cascade, inverse: \Envio.reclamo)
    var envios: [Envio] = []

    var notas: String = ""
}

enum EstadoReclamo: String, Codable, CaseIterable {
    case borrador, enviado, enRevision, aprobado, pagado, rechazado, requiereDocumentos

    var etiqueta: String { /* localizado en español */ rawValue }
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
}

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

    /// Nombre corto usado en el nombre de archivo (sin tildes ni espacios).
    var slug: String { /* p.ej. "Factura-Medico" */ "" }
    var etiqueta: String { /* "Factura del médico" */ "" }
    /// Si true, se intenta extraer monto por OCR.
    var esFacturable: Bool { /* true para las facturas */ false }
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
}

enum FiltroEscaneo: String, Codable, CaseIterable {
    case original       // color tal cual
    case documento      // realce de contraste, fondo blanco (por defecto)
    case escalaGrises
    case blancoYNegro
}

enum PreajusteCalidad: String, Codable, CaseIterable {
    case alta, media, baja
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
}

enum MetodoEnvio: String, Codable { case smtp, composer }
enum EstadoEnvio: String, Codable { case pendiente, enviando, enviado, fallido }

// MARK: - Plantilla

@Model
final class PlantillaCorreo {
    var id: UUID = UUID()
    var nombre: String = ""
    var asunto: String = ""
    var cuerpo: String = ""
    var esGlobalPorDefecto: Bool = false
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
}
```

### 3.3 Reglas de negocio del modelo

- **Un `Reclamo` siempre apunta a una `Cobertura`**, nunca directamente a Paciente o Póliza. De ahí se derivan ambos.
- Al crear un reclamo secundario, se **copian** las referencias a los documentos del reclamo origen (no se duplican archivos, solo se referencian) y se exige un documento de tipo `.liquidacionAseguradora`.
- `Reclamo.numero` es un consecutivo local que arranca en 1. Sirve para decir "el reclamo 23" por teléfono.
- Un `EventoMedico` se crea automáticamente cuando un reclamo pasa a estado `.enviado`, con `creadoAutomaticamente = true`. El usuario puede editarlo o crear eventos manuales (una consulta que no generó reclamo).

---

## 4. Resolución de destinatarios (crítico)

Los destinatarios de un reclamo se resuelven con esta cascada, en orden:

```swift
func destinatarios(para reclamo: Reclamo) -> (to: [String], cc: [String], bcc: [String]) {
    guard let cobertura = reclamo.cobertura else { return ([], [], []) }

    // 1. Base: la Cobertura si tiene override, si no la Póliza.
    let base = cobertura.destinatariosOverride.isEmpty
        ? (cobertura.poliza?.destinatarios ?? [])
        : cobertura.destinatariosOverride

    var to  = base.filter { $0.activo && $0.tipo == .to  }.map(\.email)
    var cc  = base.filter { $0.activo && $0.tipo == .cc  }.map(\.email)
    let bcc = base.filter { $0.activo && $0.tipo == .bcc }.map(\.email)

    // 2. Extras puntuales del reclamo, siempre en Cc.
    cc.append(contentsOf: reclamo.destinatariosExtra)

    // 3. Copia a sí mismo, si está activada en ajustes.
    // (ver §8.6)

    return (to.deduplicado(), cc.deduplicado(), bcc.deduplicado())
}
```

**En la UI**: la pantalla de envío muestra siempre los destinatarios resueltos como chips editables, con indicación del origen (`de la póliza` / `override` / `agregado`). Nunca enviar sin que el usuario los vea.

**Todos los destinatarios van en un solo mensaje.** Nunca hacer un envío por destinatario.

---

## 5. Escaneo

### 5.1 Captura

Envolver `VNDocumentCameraViewController` en un `UIViewControllerRepresentable`. Ya resuelve detección de bordes, corrección de perspectiva, recorte y captura multipágina. No reimplementar nada de eso.

```swift
struct DocumentScannerView: UIViewControllerRepresentable {
    var onFinish: ([UIImage]) -> Void
    var onCancel: () -> Void
    // VNDocumentCameraViewControllerDelegate → scan.pageCount / scan.imageOfPage(at:)
}
```

Guardar cada imagen resultante **sin filtro** como `rutaOriginal` en JPEG calidad 0.9. Esto permite cambiar el filtro después sin volver a escanear. Estos originales se pueden purgar (ver §5.4).

### 5.2 Filtros

Aplicar con Core Image sobre el original, en un pipeline:

| Filtro | Pipeline |
|---|---|
| `.original` | sin cambios |
| `.documento` | `CIDocumentEnhancer` (amount ≈ 1.0). Si no da buen resultado: `CIColorControls` contraste 1.35, brillo 0.08, saturación 0.6 + `CIUnsharpMask` radius 1.5 intensity 0.5 |
| `.escalaGrises` | `CIPhotoEffectMono` + `CIColorControls` contraste 1.3 |
| `.blancoYNegro` | escala de grises + umbral adaptativo. `CIColorControls` saturación 0 + contraste 3.0 + brillo ajustado, o umbral manual sobre el buffer |

Por defecto: `.documento`. Sugerir `.escalaGrises` automáticamente si el análisis de saturación media de la imagen es bajo (documento en blanco y negro).

Vista previa del filtro en tiempo real sobre una miniatura, no sobre la imagen completa.

### 5.3 Edición de páginas

Dentro de un documento se debe poder:

- Reordenar por drag & drop
- Eliminar una página
- Rotar 90°
- Re-escanear una página individual (reemplaza la imagen, conserva la posición)
- Agregar páginas al final
- Cambiar el filtro de una página o de todas a la vez
- Recortar manualmente (ajuste fino sobre el recorte de VisionKit)

### 5.4 Importación

Además de la cámara:

- Importar imágenes desde Fotos
- Importar un PDF desde Archivos → se convierte en un `Documento` con `rutaPDF` directa (sin páginas escaneadas). Muy usado para resultados de laboratorio que ya llegan en PDF.
- **Share Extension**: recibir PDFs e imágenes desde Mail, WhatsApp o Safari y asignarlos a un reclamo existente o a uno nuevo.

Los PDFs importados también pasan por el compresor (§6.2) si superan el umbral.

**Purga de originales**: en ajustes, opción "liberar espacio" que elimina los `rutaOriginal` de reclamos ya pagados o rechazados hace más de N días, conservando los PDFs finales.

---

## 6. Generación de PDF

### 6.1 Construcción

Un PDF **por documento** (no uno combinado), con PDFKit:

```swift
let pdf = PDFDocument()
for (i, imagen) in imagenesProcesadas.enumerated() {
    guard let page = PDFPage(image: imagen) else { continue }
    pdf.insert(page, at: i)
}
pdf.write(to: url)
```

Metadatos del PDF: `title` = nombre del documento, `creator` = nombre de la app. **No incluir datos del paciente en metadatos** (el PDF viaja por correo).

### 6.2 Compresión — objetivo de peso

Este es el punto que más afecta la usabilidad. Parámetros por preajuste:

| Preajuste | Lado largo | Calidad JPEG | Peso aprox./página |
|---|---|---|---|
| Alta | 2400 px | 0.75 | 400–700 KB |
| **Media (por defecto)** | 1800 px | 0.60 | 150–300 KB |
| Baja | 1200 px | 0.45 | 60–120 KB |

1800 px en el lado largo equivale a ~150 DPI en A4: suficiente para leer letra chica, sellos y firmas.

Convertir a escala de grises reduce ~40% adicional sin pérdida útil en recetas y facturas.

**Algoritmo de ajuste automático**: si el total de adjuntos del reclamo supera el umbral configurado (por defecto 15 MB, con el techo real de Gmail en 25 MB), bajar iterativamente el preajuste de los documentos más pesados y recomprimir, avisando al usuario qué se ajustó. Nunca bajar por debajo de `.baja` sin confirmación explícita.

### 6.3 Nomenclatura de archivos

Formato: `{fecha}_{Paciente}_{NN}-{TipoDocumento}.pdf`

Ejemplo: `2026-07-27_JuanPerez_02-Factura-Medico.pdf`

Reglas:
- Fecha en `yyyy-MM-dd` (fecha del evento, no de creación) para que ordene solo.
- Nombre del paciente sin espacios ni tildes, formato PascalCase.
- `NN` = `Documento.orden` con dos dígitos.
- Tipo desde `TipoDocumento.slug`, sin tildes ni espacios.
- **Filenames siempre ASCII**: normalizar quitando diacríticos. Evita problemas en clientes de correo antiguos.
- El patrón debe ser configurable en ajustes con tokens: `{fecha}`, `{paciente}`, `{orden}`, `{tipo}`, `{aseguradora}`, `{poliza}`, `{reclamo}`.

---

## 7. OCR

Al terminar de generar un documento, correr `VNRecognizeTextRequest` en background sobre las páginas:

```swift
let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.recognitionLanguages = ["es-EC", "es-ES", "en-US"]
request.usesLanguageCorrection = true
```

### 7.1 Extracción de campos (facturas ecuatorianas)

Las facturas del SRI tienen estructura regular. Aplicar sobre `textoOCR`:

| Campo | Estrategia |
|---|---|
| RUC | Regex `\b\d{13}\b` terminado en `001` |
| Nº de factura | Regex `\b\d{3}-\d{3}-\d{9}\b` |
| Fecha | Regex `\d{2}[/-]\d{2}[/-]\d{4}` cerca de "FECHA" o "EMISIÓN" |
| Monto total | Buscar líneas con `TOTAL`, `VALOR TOTAL`, `IMPORTE TOTAL`; tomar el último número decimal de la línea. Ignorar `SUBTOTAL`, `IVA`, `DESCUENTO` |
| Emisor | Primeras 2–3 líneas del bloque superior, o la línea que precede al RUC |
| Autorización SRI | Regex de 10, 37 o 49 dígitos |

Priorizar el candidato de monto con mayor valor cuando haya empate — el total nunca es menor que sus componentes.

### 7.2 Presentación

**El OCR nunca decide solo.** Al terminar, se muestra una tarjeta "Detectamos esto" con los campos rellenados y editables, y un botón de confirmar que marca `ocrConfirmadoPorUsuario = true`. Si la extracción del monto tiene baja confianza, dejar el campo vacío en vez de poner un número equivocado.

El `montoReclamado` del reclamo es la suma de los montos de los documentos con `tipo.esFacturable`, recalculada al confirmar cada uno, y editable manualmente (marca el reclamo como monto manual y deja de recalcular).

También usar el OCR para sugerir el `TipoDocumento` (buscar "RECETA", "ORDEN DE EXÁMENES", "FACTURA", "INFORME") y el nombre del médico.

---

## 8. Envío de correo

### 8.1 Abstracción

```swift
protocol MailSender {
    var puedeEnviarSilenciosamente: Bool { get }
    func send(_ mail: OutgoingMail) async throws -> SentReceipt
}

struct OutgoingMail {
    var from: EmailAddress
    var to: [EmailAddress]
    var cc: [EmailAddress]
    var bcc: [EmailAddress]
    var subject: String
    var body: String              // texto plano
    var attachments: [Attachment] // url, filename, mimeType
    var messageID: String         // generado por la app
    var inReplyTo: String?
    var references: [String]
}

struct SentReceipt {
    var messageID: String
    var fecha: Date
    var metodo: MetodoEnvio
}
```

Dos implementaciones: `SMTPMailSender` (principal) y `ComposerMailSender` (respaldo).

### 8.2 SMTPMailSender

**Servidor**: `smtp.gmail.com`, **puerto 465 con TLS implícito**. Preferir 465 sobre 587/STARTTLS: evita la negociación en texto plano y es menos código.

**Autenticación**: la contraseña normal de Gmail **no funciona**. Google eliminó definitivamente el acceso de aplicaciones menos seguras (proceso terminado el 1 de mayo de 2025). Se requiere una **App Password** de 16 caracteres, que a su vez exige tener activada la verificación en 2 pasos. No requiere Google Cloud ni OAuth.

Secuencia del protocolo:

```
S: 220 smtp.gmail.com ESMTP ...
C: EHLO reclamos.local
S: 250-smtp.gmail.com ... (multilínea)
C: AUTH LOGIN
S: 334 VXNlcm5hbWU6
C: <base64(usuario)>
S: 334 UGFzc3dvcmQ6
C: <base64(app password)>
S: 235 2.7.0 Accepted
C: MAIL FROM:<usuario@gmail.com>
S: 250 2.1.0 OK
C: RCPT TO:<destino1@x.com>      ← una línea por CADA destinatario,
S: 250 2.1.5 OK                     incluidos los de Cc y Bcc
C: DATA
S: 354 Go ahead
C: <headers + cuerpo MIME>
C: .
S: 250 2.0.0 OK <id>
C: QUIT
```

**Detalles que rompen implementaciones ingenuas:**

1. **CRLF (`\r\n`) en absolutamente todas las líneas.** No `\n`.
2. **Dot-stuffing**: cualquier línea del cuerpo que empiece con `.` debe duplicarse a `..`. Si no, el mensaje se corta ahí.
3. **Base64 en líneas de máximo 76 caracteres**, separadas por CRLF.
4. **Asunto con tildes** debe ir codificado RFC 2047: `=?UTF-8?B?<base64>?=`. Un asunto sin codificar con "médico" llega roto.
5. **Nombres de archivo con caracteres no ASCII** requieren RFC 2231 (`filename*=UTF-8''...`). Se evita normalizando los filenames a ASCII (§6.3).
6. **La app password se muestra en 4 grupos de 4 caracteres**: hay que quitar los espacios antes de usarla.
7. Las respuestas del servidor son multilínea cuando el 4º carácter es `-` (`250-`) y terminan cuando es un espacio (`250 `). El parser debe manejarlo.
8. `Bcc` **no va en los headers**, solo en los `RCPT TO`.

**Estructura MIME**:

```
From: Sebastian <usuario@gmail.com>
To: Reclamos <reclamos@aseguradora.com>, Asesor <asesor@corredora.com>
Cc: rrhh@empresa.com
Subject: =?UTF-8?B?UmVjbGFtbyDigJQgSnVhbiBQw6lyZXo=?=
Date: Mon, 27 Jul 2026 14:32:10 -0500
Message-ID: <a1b2c3d4-...@reclamos.app>
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="----=_Part_7F3A9C"

------=_Part_7F3A9C
Content-Type: text/plain; charset=UTF-8
Content-Transfer-Encoding: quoted-printable

<cuerpo del mensaje>

------=_Part_7F3A9C
Content-Type: application/pdf; name="2026-07-27_JuanPerez_01-Receta.pdf"
Content-Transfer-Encoding: base64
Content-Disposition: attachment; filename="2026-07-27_JuanPerez_01-Receta.pdf"

JVBERi0xLjQKJcfsj6IKNSAwIG9iago8PC9MZW5ndGggNiAwIFIvRmlsdGVy...

------=_Part_7F3A9C--
```

En envíos de seguimiento se agregan:

```
In-Reply-To: <messageID-del-primer-envio>
References: <messageID-1> <messageID-2>
```

**Manejo de errores** con mensajes accionables en español:

| Código | Mensaje al usuario |
|---|---|
| `535 5.7.8` | "Credenciales rechazadas. Verifica que estés usando una contraseña de aplicación de 16 caracteres, no tu contraseña de Gmail." |
| `534 5.7.9` | "Gmail exige contraseña de aplicación. Activa la verificación en 2 pasos y genera una." |
| `552` / `523` | "El correo excede el límite de tamaño. Reduce la calidad de los escaneos." |
| Timeout | "No se pudo conectar. El correo quedó en la cola y se reintentará." |

**Límites de Gmail**: 25 MB por mensaje, ~100 destinatarios por mensaje, ~500 mensajes por día. Ninguno es problema para este uso, pero validar el de 25 MB antes de intentar el envío.

**Streaming de adjuntos**: no cargar todos los PDFs en memoria a la vez. Ir escribiendo por chunks al `NWConnection`, codificando base64 por bloques de 57 bytes (que dan exactamente 76 caracteres).

### 8.3 ComposerMailSender (respaldo)

`MFMailComposeViewController` con todo prellenado: destinatarios, asunto, cuerpo y adjuntos. El usuario solo pulsa Enviar.

Se usa cuando:
- No hay credenciales SMTP configuradas todavía
- El SMTP falló y el usuario elige "enviar de otra forma"
- El usuario lo prefiere explícitamente (ajuste)

**Limitación importante**: no permite fijar `Message-ID` ni `In-Reply-To`, así que se pierde el control del hilo. Mitigación: mantener **exactamente el mismo asunto** en los envíos de seguimiento, que es como Gmail y Apple Mail agrupan por defecto. Registrar el `Envio` con `messageID = ""` y marcarlo para que la UI advierta que el hilo puede no encadenarse.

### 8.4 Continuidad de hilo

1. La app genera el `Message-ID` (`<UUID@reclamos.app>`) **antes** de enviar y lo guarda en el `Envio`.
2. Envíos posteriores del mismo reclamo usan `In-Reply-To` = messageID del primer envío, y `References` = todos los messageIDs previos en orden.
3. El asunto de seguimiento antepone `Re: ` al asunto original, sin modificarlo.

> **Verificar empíricamente**: Gmail puede reescribir el `Message-ID` de mensajes enviados por SMTP. Hacer una prueba real de dos envíos encadenados antes de dar la funcionalidad por buena. Si Gmail lo reescribe, el encadenamiento por asunto idéntico + mismos participantes sigue funcionando en la práctica, y esa debe ser la garantía mínima.

### 8.5 Cola de envío

Los envíos van a una cola persistente (`Envio` con estado `.pendiente`):

- Si no hay red, quedan encolados y se reintentan al recuperar conectividad (`NWPathMonitor`).
- Backoff exponencial: 30 s, 2 min, 10 min, 1 h. Máximo 5 intentos.
- Usar `BGProcessingTask` para reintentar en segundo plano.
- La UI muestra un indicador claro de "pendiente de envío" en el reclamo.

### 8.6 Copia propia

Ajuste "Guardarme copia" (activo por defecto): agrega la propia dirección en Bcc.

> Gmail normalmente guarda en "Enviados" los mensajes que salen por su SMTP, pero conviene verificarlo en la primera prueba. Si no lo hace, el Bcc a sí mismo garantiza el respaldo.

### 8.7 Otros canales

Además del correo, botón de compartir estándar (`ShareLink`) con todos los PDFs del reclamo, para WhatsApp o AirDrop cuando el asesor lo pide por ahí. También impresión con `UIPrintInteractionController`.

---

## 9. Plantillas de correo

Cascada de resolución, de menor a mayor precedencia. Gana la primera que exista, empezando por abajo:

```
1. Plantilla global por defecto     (PlantillaCorreo.esGlobalPorDefecto)
2. Plantilla de la aseguradora      (Aseguradora.plantilla)
3. Plantilla de la póliza           (Poliza.plantilla)
4. Override puntual del reclamo     (Reclamo.asuntoOverride / cuerpoOverride)
```

```swift
func plantilla(para reclamo: Reclamo) -> (asunto: String, cuerpo: String) {
    let poliza = reclamo.cobertura?.poliza
    let base = poliza?.plantilla
        ?? poliza?.aseguradora?.plantilla
        ?? plantillaGlobal
    return (
        reclamo.asuntoOverride ?? base.asunto,
        reclamo.cuerpoOverride ?? base.cuerpo
    )
}
```

En la práctica el nivel de aseguradora es el que más se usa (todas las pólizas de una misma aseguradora quieren el mismo formato); el de póliza queda para el caso de la póliza corporativa que pasa por RRHH y necesita un texto distinto. La UI del editor debe indicar de qué nivel viene la plantilla que se está aplicando y ofrecer "personalizar solo para esta póliza".

**Tokens disponibles**:

`{{paciente}}` `{{paciente_cedula}}` `{{parentesco}}` `{{aseguradora}}` `{{poliza}}` `{{certificado}}` `{{fecha_evento}}` `{{fecha_hoy}}` `{{diagnostico}}` `{{medico}}` `{{prestador}}` `{{monto_total}}` `{{numero_reclamo}}` `{{lista_documentos}}` `{{cantidad_documentos}}`

`{{lista_documentos}}` se expande a una lista con viñetas de los adjuntos con su tipo y monto cuando aplique.

**Plantilla por defecto sugerida**:

```
Asunto:
Reclamo médico — {{paciente}} — {{fecha_evento}} — Póliza {{poliza}}

Cuerpo:
Estimados,

Adjunto la documentación para el reclamo médico del siguiente paciente:

Paciente: {{paciente}} (C.I. {{paciente_cedula}})
Póliza: {{poliza}} — {{aseguradora}}
Certificado: {{certificado}}
Fecha de atención: {{fecha_evento}}
Prestador: {{prestador}}
Monto total: USD {{monto_total}}

Documentos adjuntos ({{cantidad_documentos}}):
{{lista_documentos}}

Quedo atento a cualquier información adicional que requieran.

Saludos cordiales,
```

Editor de plantilla con vista previa en vivo usando datos reales del reclamo actual, e inserción de tokens desde un menú (no escribirlos a mano).

---

## 10. Checklist de documentos

Cada póliza define su `checklistPorDefecto`. Al abrir un reclamo se muestra el progreso:

```
✓ Receta
✓ Factura del médico
✗ Orden de exámenes        ← falta
✓ Resultado de exámenes
✗ Formulario de la aseguradora  ← falta, requiere firma del médico
```

- El botón de enviar sigue habilitado si faltan documentos, pero muestra una confirmación: "Faltan 2 documentos requeridos. ¿Enviar de todas formas?"
- Los ítems marcados como `requiereFirmaMedico` muestran un aviso especial: hay que llevarlos impresos al consultorio.
- El checklist es editable por reclamo (a veces un caso concreto no necesita algo).

---

## 11. Historial médico

Dos capas:

**Estática** (en `Paciente`): tipo de sangre, alergias, condiciones crónicas, medicación habitual, notas. Editable directamente.

**Cronológica** (`EventoMedico`): línea de tiempo por paciente. Se alimenta automáticamente de los reclamos enviados y admite entradas manuales (una consulta que no generó reclamo, una vacuna, una cirugía).

Vista de historial: timeline con filtros por año, por especialidad y por médico. Cada evento enlaza a su reclamo, desde donde se ven los documentos.

**Directorio de médicos y prestadores**: se construye solo a partir de los nombres usados en los reclamos, con autocompletado. Guardar especialidad y teléfono cuando se conozcan.

**Búsqueda global**: un solo campo que busca en diagnósticos, médicos, prestadores, notas y texto OCR de los documentos. "¿Cuándo fue la última vez que Ana fue al alergólogo?" debe resolverse en un par de segundos.

---

## 12. Seguridad y privacidad

- **Face ID / Touch ID** obligatorio para abrir la app (desactivable en ajustes, activo por defecto). Bloqueo al pasar a segundo plano con un umbral configurable.
- Credenciales SMTP en **Keychain** con `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. Nunca en el modelo de datos, nunca en logs.
- PDFs e imágenes con `FileProtectionType.complete`.
- Excluir el directorio de archivos del backup de iCloud si el usuario lo prefiere (ajuste), aunque por defecto conviene incluirlo — perder los reclamos es peor.
- Screenshot blur: aplicar un overlay al pasar al app switcher.
- Sin analytics, sin crash reporting de terceros, sin red salvo el SMTP.

---

## 13. Pantallas

```
TabView
├── Reclamos
│   ├── Lista (agrupada por estado, filtro por paciente / póliza / año)
│   ├── Detalle del reclamo
│   │   ├── Cabecera: paciente, póliza, estado, montos
│   │   ├── Checklist de documentos
│   │   ├── Lista de documentos (grid con miniaturas, peso, monto)
│   │   ├── Historial de envíos
│   │   └── Acciones: escanear, importar, enviar, crear secundario
│   ├── Nuevo reclamo (paciente → póliza → datos del evento)
│   ├── Escáner (VisionKit)
│   ├── Editor de documento (páginas, filtros, tipo, OCR)
│   └── Pantalla de envío (destinatarios, asunto, cuerpo, adjuntos + peso total)
│
├── Pacientes
│   ├── Lista
│   ├── Perfil (datos, coberturas, historial médico)
│   └── Timeline de eventos médicos
│
├── Seguros
│   ├── Aseguradoras
│   ├── Pólizas (destinatarios, plantilla, checklist, deducible)
│   └── Formularios en blanco
│
└── Ajustes
    ├── Cuenta de correo (SMTP / probar conexión)
    ├── Plantilla global
    ├── Calidad de escaneo por defecto
    ├── Patrón de nombres de archivo
    ├── Recordatorios
    ├── Seguridad (Face ID)
    └── Almacenamiento (uso, purga de originales)
```

### 13.1 Flujo principal (el que hay que optimizar)

```
[+] → Paciente → (Póliza, autoseleccionada si solo hay una)
    → Cámara abre inmediatamente
    → Escanear → elegir tipo de documento → guardar
    → "¿Otro documento?" → repetir
    → Revisar (checklist + montos detectados)
    → Enviar → confirmar destinatarios → listo
```

Meta: menos de 8 toques desde abrir la app hasta enviar un reclamo de 3 documentos, sin contar los escaneos.

### 13.2 Pantalla de envío

Debe mostrar, sin scroll, en la primera pantalla:

- Destinatarios como chips (con origen indicado)
- Asunto
- Lista de adjuntos con nombre y peso individual
- **Peso total, en grande, con color** (verde < 10 MB, ámbar 10–20 MB, rojo > 20 MB)
- Botón de bajar calidad si está en ámbar o rojo
- Botón de enviar

---

## 14. Recordatorios

- Notificación configurable a los N días (por defecto 15) si un reclamo sigue en `.enviado` o `.enRevision`.
- Notificación cuando un reclamo lleva más de N días en `.borrador` (documentos escaneados que nunca se enviaron).
- Recordatorio de vigencia de póliza próxima a vencer.
- Todas desactivables individualmente.

---

## 15. Seguimiento de montos y reportes

### 15.1 Panel "Pendiente de cobro"

Es la primera cosa que se ve al abrir la pestaña de Reclamos: una tarjeta fija arriba con la respuesta a **"¿cuánto me deben ahora mismo?"**

```
┌─────────────────────────────────────┐
│  Pendiente de cobro                 │
│                                     │
│  USD 1,847.30                       │
│  en 4 reclamos                      │
│                                     │
│  ├ Enviados          USD   920.00   │
│  ├ En revisión       USD   627.30   │
│  └ Aprobados         USD   300.00   │  ← ya aprobado, falta que paguen
│                                     │
│  ⚠ 1 reclamo sin respuesta hace 23d │
└─────────────────────────────────────┘
```

Cálculo:

```swift
// Pendiente = suma de montoReclamado de reclamos en estados no terminales,
// menos lo ya reembolsado parcialmente.
var pendienteDeCobro: Decimal {
    reclamos
        .filter { [.enviado, .enRevision, .aprobado, .requiereDocumentos].contains($0.estado) }
        .reduce(0) { $0 + ($1.montoReclamado - ($1.montoReembolsado ?? 0)) }
}
```

Los reclamos en `.borrador` **no** cuentan (no se han enviado). Los `.pagado` y `.rechazado` tampoco.

Tocar cualquier línea filtra la lista de reclamos por ese estado. Tocar el aviso de días sin respuesta lleva al reclamo más atrasado.

Desglose adicional filtrable por paciente y por póliza, porque con varios seguros el total agregado no siempre es la pregunta útil.

### 15.2 Reembolsos parciales

`montoReembolsado` puede ser menor que `montoReclamado` sin que el reclamo se cierre: es el caso normal cuando la póliza cubre un porcentaje. Al registrar un reembolso parcial, la app pregunta si el saldo se pasa a una segunda póliza y, si acepta, ofrece crear el **reclamo secundario** ya prellenado (ver §3.3).

### 15.3 Reportes

- Resumen por año y por póliza: total reclamado, total reembolsado, pendiente, tasa de aprobación, tiempo promedio de respuesta.
- Deducible consumido vs. deducible anual, con barra de progreso.
- Exportación CSV de reclamos (fecha, paciente, póliza, prestador, diagnóstico, monto reclamado, monto reembolsado, estado) para contabilidad o declaración de impuestos.
- Exportación de un reclamo completo como carpeta ZIP con sus PDFs.

---

## 16. Fases de implementación

El **modelo de datos completo (§3) se implementa en la Fase 1**, aunque la UI de algunas partes no exista todavía. Las migraciones de SwiftData son costosas; el esquema debe estar cerrado desde el inicio.

### Fase 1 — Núcleo utilizable
- Modelo de datos completo
- CRUD de Pacientes, Aseguradoras, Pólizas, Coberturas, Destinatarios
- Escaneo con VisionKit + filtros + edición de páginas
- Generación de PDF con compresión y nomenclatura
- Reclamos: crear, agregar documentos, listar
- Envío SMTP + ComposerMailSender como respaldo
- Plantilla global con tokens
- Face ID

*Al terminar la Fase 1 la app ya reemplaza el proceso manual completo.*

### Fase 2 — Inteligencia
- OCR y extracción de campos
- Montos y totales automáticos
- Checklist por póliza
- Estados del reclamo y seguimiento de reembolsos
- Cola de envío con reintentos
- Continuidad de hilo (In-Reply-To / References)

### Fase 3 — Contexto
- Historial médico y timeline por paciente
- Directorio de médicos y prestadores
- Búsqueda global (incluyendo texto OCR)
- Reclamos secundarios (coordinación de beneficios)
- Recordatorios

### Fase 4 — Pulido
- Reportes y exportación CSV/ZIP
- Share Extension
- Formularios en blanco por aseguradora
- Sincronización CloudKit
- App Intents / Atajos de Siri
- Gestión de almacenamiento y purga

---

## 17. Riesgos conocidos

| Riesgo | Mitigación |
|---|---|
| Google podría retirar las App Passwords (empuja hacia OAuth 2.0, sin fecha anunciada) | Toda la lógica de envío detrás del protocolo `MailSender`. Cambiar a OAuth sería una implementación nueva sin tocar el resto. |
| Gmail podría reescribir el `Message-ID` y romper el encadenamiento | Garantía mínima por asunto idéntico + mismos participantes. Verificar en la primera prueba real. |
| OCR con falsos positivos en montos | Nunca autocompletar sin confirmación del usuario. Campo vacío ante baja confianza. |
| Escaneos pesados que superan el límite de Gmail | Validación previa al envío + recompresión automática + indicador de peso siempre visible. |
| Aseguradoras que exigen documentos originales físicos | Fuera del alcance de la app. Documentarlo en las notas de la póliza. |

---

## 18. Criterios de aceptación de la Fase 1

1. Escanear un documento de 3 páginas y obtener un PDF legible de menos de 900 KB.
2. Crear un paciente con dos pólizas de aseguradoras distintas y verificar que al cambiar de póliza en un reclamo cambian los destinatarios resueltos.
3. Enviar un reclamo con 5 PDFs adjuntos a 3 destinatarios y confirmar que llega **un solo correo** con los 3 en el mismo mensaje.
4. Un asunto con tildes debe llegar correctamente a Gmail, Outlook y Apple Mail.
5. Los adjuntos deben abrirse sin corrupción en los tres clientes.
6. Sin credenciales configuradas, la app debe caer al composer sin errores.
7. La app debe pedir Face ID al volver del segundo plano tras el umbral configurado.

---

## Apéndice A — Mapa de requerimientos

Verificación cruzada: cada cosa pedida y dónde está especificada.

| Requerimiento | Sección | Fase |
|---|---|---|
| Escaneo con detección de bordes, recorte y enderezado | §5.1 | 1 |
| Filtros para mejorar legibilidad | §5.2 | 1 |
| Un PDF por documento | §6.1 | 1 |
| PDFs livianos para adjuntar | §6.2 | 1 |
| Nombre del archivo según el tipo de documento | §6.3 | 1 |
| **Reordenar, eliminar y re-escanear páginas individuales** | **§5.3** | **1** |
| Un solo correo a varios destinatarios (no uno por cada uno) | §4, §8.2 | 1 |
| Gmail con usuario y contraseña, sin Google Cloud | §8.2 (App Password) | 1 |
| Lista de destinatarios editable | §4 | 1 |
| **Plantillas de asunto y cuerpo con variables** | **§9** | **1** |
| **Plantilla global + override por aseguradora** | **§9 (cascada de 4 niveles)** | **1** |
| Múltiples pacientes | §3.2 `Paciente` | 1 |
| Varios seguros / varias pólizas | §3.2 `Poliza`, `Cobertura` | 1 |
| Perfil del paciente | §3.2, §13 | 1 |
| Número de póliza y de certificado | §3.2 `Poliza`, `Cobertura` | 1 |
| Los destinatarios cambian según paciente/póliza | §4 (cascada de 3 niveles) | 1 |
| **Compartir por WhatsApp / AirDrop** | **§8.7** | **1** |
| OCR de montos y fechas | §7 | 2 |
| Checklist por aseguradora | §10 | 2 |
| Estados del reclamo | §3.2 `EstadoReclamo` | 2 |
| **Cola de envío offline con reintentos** | **§8.5** | **2** |
| **Seguimiento de montos: reclamado / reembolsado / pendiente** | **§15.1, §15.2** | **2** |
| **Deducible anual consumido** | **§15.3** | **2** |
| Continuidad de hilo de correo | §8.4 | 2 |
| Historial médico guardado | §11 | 3 |
| Reclamos secundarios (coordinación de beneficios) | §3.3, §15.2 | 3 |
| **Recordatorio de seguimiento a los X días** | **§14** | **3** |
| Búsqueda global incluyendo texto OCR | §11 | 3 |
| **Exportar CSV para impuestos o contabilidad** | **§15.3** | **4** |
| **Share Extension para importar PDFs desde Mail o WhatsApp** | **§5.4** | **4** |
| Formularios en blanco por aseguradora | §3.2 `FormularioEnBlanco` | 4 |
