import Foundation

// Seguimiento de montos (§15). Panel "Pendiente de cobro" y desgloses.

struct PendienteDeCobro {
    var total: Decimal = 0
    var cantidad: Int = 0
    var enviados: Decimal = 0
    var enRevision: Decimal = 0
    var aprobados: Decimal = 0
    var requiereDocumentos: Decimal = 0
    /// Reclamo más atrasado (más días sin cambiar de estado enviado/en revisión).
    var reclamoMasAtrasado: Reclamo?
    var diasAtraso: Int = 0
}

enum MoneyCalc {

    /// Pendiente = suma de (montoReclamado − reembolsado) de reclamos en estados
    /// no terminales (enviado, en revisión, aprobado, requiere documentos). §15.1
    static func pendiente(_ reclamos: [Reclamo]) -> PendienteDeCobro {
        var r = PendienteDeCobro()
        var atrasoMax = -1

        for reclamo in reclamos where reclamo.estado.cuentaEnPendiente {
            let saldo = reclamo.pendiente
            r.total += saldo
            r.cantidad += 1
            switch reclamo.estado {
            case .enviado: r.enviados += saldo
            case .enRevision: r.enRevision += saldo
            case .aprobado: r.aprobados += saldo
            case .requiereDocumentos: r.requiereDocumentos += saldo
            default: break
            }

            // "Sin respuesta hace N días": tomamos el último envío como referencia.
            if reclamo.estado == .enviado || reclamo.estado == .enRevision {
                let ref = reclamo.envios.map(\.fecha).max() ?? reclamo.fechaCreacion
                let dias = Formato.diasDesde(ref)
                if dias > atrasoMax {
                    atrasoMax = dias
                    r.reclamoMasAtrasado = reclamo
                    r.diasAtraso = dias
                }
            }
        }
        return r
    }

    /// Monto reclamado = suma de montos de documentos facturables (§7.2), salvo
    /// que el usuario lo haya fijado a mano.
    static func montoReclamadoAuto(_ reclamo: Reclamo) -> Decimal {
        reclamo.documentos
            .filter { $0.tipo.esFacturable }
            .reduce(Decimal(0)) { $0 + ($1.monto ?? 0) }
    }

    /// Recalcula y asigna el monto si el reclamo no está en modo manual.
    static func recalcularMonto(_ reclamo: Reclamo) {
        guard !reclamo.montoManual else { return }
        reclamo.montoReclamado = montoReclamadoAuto(reclamo)
    }
}
