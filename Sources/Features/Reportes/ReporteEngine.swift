import Foundation

// Motor de reportes: lógica pura, sin SwiftUI. Todo el dinero en Decimal.
// Se evitan divisiones por cero con guardas explícitas.

/// Resumen agregado de un conjunto de reclamos (global, por año o por póliza).
struct ResumenPeriodo: Identifiable {
    var id = UUID()
    var titulo: String            // "2026" o "2026 · Salud SA — Corporativa"
    var totalReclamado: Decimal
    var totalReembolsado: Decimal
    var pendiente: Decimal
    var cantidadReclamos: Int
    var aprobadosOPagados: Int
    var rechazados: Int
    var tasaAprobacion: Double     // 0..1
    var diasPromedioRespuesta: Double
}

/// Estado del deducible anual de una cobertura.
struct DeducibleInfo: Identifiable {
    var id = UUID()
    var poliza: String
    var consumido: Decimal
    var anual: Decimal?
    var progreso: Double           // 0..1, 0 si `anual` es nil
}

enum ReporteEngine {

    // MARK: - API pública

    /// Un resumen por cada año (según `fechaEvento`), ordenados descendente.
    static func porAnio(_ reclamos: [Reclamo]) -> [ResumenPeriodo] {
        let cal = Calendar.current
        let grupos = Dictionary(grouping: reclamos) { r in
            cal.component(.year, from: r.fechaEvento)
        }
        return grupos.keys.sorted(by: >).map { anio in
            resumen(titulo: "\(anio)", grupos[anio] ?? [])
        }
    }

    /// Agrupado por póliza. Si `anio` no es nil, filtra por año de `fechaEvento`.
    static func porPoliza(_ reclamos: [Reclamo], anio: Int?) -> [ResumenPeriodo] {
        let cal = Calendar.current
        let filtrados: [Reclamo]
        if let anio {
            filtrados = reclamos.filter { cal.component(.year, from: $0.fechaEvento) == anio }
        } else {
            filtrados = reclamos
        }

        // Se agrupa por el id de la póliza (o "sin" cuando no hay).
        let grupos = Dictionary(grouping: filtrados) { r -> String in
            r.cobertura?.poliza?.id.uuidString ?? "sin"
        }

        var resultado: [ResumenPeriodo] = []
        for (_, rs) in grupos {
            let poliza = rs.first?.cobertura?.poliza
            let nombre = nombrePoliza(poliza)
            let titulo = anio != nil ? "\(anio!) · \(nombre)" : nombre
            resultado.append(resumen(titulo: titulo, rs))
        }
        // Orden estable: mayor monto reclamado primero.
        return resultado.sorted { $0.totalReclamado > $1.totalReclamado }
    }

    /// Estado de deducible por cobertura.
    static func deducibles(_ coberturas: [Cobertura]) -> [DeducibleInfo] {
        coberturas.map { cob in
            let consumido = cob.deducibleConsumido
            let anual = cob.poliza?.deducibleAnual
            let progreso: Double
            if let anual, anual > 0 {
                let ratio = (consumido as NSDecimalNumber).doubleValue
                    / (anual as NSDecimalNumber).doubleValue
                progreso = min(max(ratio, 0), 1)
            } else {
                progreso = 0
            }
            return DeducibleInfo(
                poliza: cob.poliza?.nombreVisible ?? "Sin póliza",
                consumido: consumido,
                anual: anual,
                progreso: progreso
            )
        }
    }

    /// Resumen global sobre todos los reclamos.
    static func global(_ reclamos: [Reclamo]) -> ResumenPeriodo {
        resumen(titulo: "Global", reclamos)
    }

    // MARK: - Interno

    private static func nombrePoliza(_ poliza: Poliza?) -> String {
        guard let poliza else { return "Sin póliza" }
        if let aseguradora = poliza.aseguradora?.nombre, !aseguradora.isEmpty {
            return "\(aseguradora) — \(poliza.nombreVisible)"
        }
        return poliza.nombreVisible
    }

    /// Construye un `ResumenPeriodo` a partir de una lista de reclamos.
    private static func resumen(titulo: String, _ reclamos: [Reclamo]) -> ResumenPeriodo {
        var totalReclamado: Decimal = 0
        var totalReembolsado: Decimal = 0
        var pendiente: Decimal = 0
        var aprobadosOPagados = 0
        var pagados = 0
        var aprobados = 0
        var rechazados = 0

        for r in reclamos {
            totalReclamado += r.montoReclamado
            totalReembolsado += (r.montoReembolsado ?? 0)
            pendiente += r.pendiente
            switch r.estado {
            case .pagado:
                pagados += 1
                aprobadosOPagados += 1
            case .aprobado:
                aprobados += 1
                aprobadosOPagados += 1
            case .rechazado:
                rechazados += 1
            default:
                break
            }
        }

        // Tasa de aprobación: (pagado+aprobado) / (pagado+aprobado+rechazado).
        let baseTasa = pagados + aprobados + rechazados
        let tasa = baseTasa > 0 ? Double(pagados + aprobados) / Double(baseTasa) : 0

        // Días promedio: solo reclamos con reembolso y al menos un envío.
        let cal = Calendar.current
        var sumaDias = 0.0
        var conDato = 0
        for r in reclamos {
            guard let fechaReembolso = r.fechaReembolso,
                  let primerEnvio = r.envios.map({ $0.fecha }).min() else { continue }
            let dias = cal.dateComponents([.day], from: primerEnvio, to: fechaReembolso).day ?? 0
            sumaDias += Double(dias)
            conDato += 1
        }
        let diasPromedio = conDato > 0 ? sumaDias / Double(conDato) : 0

        return ResumenPeriodo(
            titulo: titulo,
            totalReclamado: totalReclamado,
            totalReembolsado: totalReembolsado,
            pendiente: pendiente,
            cantidadReclamos: reclamos.count,
            aprobadosOPagados: aprobadosOPagados,
            rechazados: rechazados,
            tasaAprobacion: tasa,
            diasPromedioRespuesta: diasPromedio
        )
    }
}
