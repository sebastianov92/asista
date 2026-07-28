import Foundation

/// Campos candidatos extraídos por OCR de una factura del SRI (Ecuador).
/// El OCR NUNCA decide solo: el llamador muestra una tarjeta editable
/// "Detectamos esto" con estos valores. `monto` es nil si la confianza es baja
/// (spec §7.2: jamás autocompletar un número equivocado).
struct CamposDetectados {
    var textoCompleto: String = ""
    var ruc: String = ""
    var numeroFactura: String = ""
    var fecha: Date? = nil
    var monto: Decimal? = nil          // nil si baja confianza
    var montoConfianza: Double = 0     // 0.0–1.0
    var emisor: String = ""
    var autorizacionSRI: String = ""
    var tipoSugerido: TipoDocumento? = nil
    var medicoSugerido: String = ""
}
