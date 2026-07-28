import SwiftUI
import SwiftData
import Foundation

// Pantalla de reportes: resumen global, desglose por año y por póliza,
// estado de deducibles y exportación CSV. UI en español (Ecuador, USD).

struct ReportesView: View {
    @Query private var reclamos: [Reclamo]
    @Query private var coberturas: [Cobertura]

    @State private var csvURL: URL?
    @State private var errorExport: String?

    private var global: ResumenPeriodo { ReporteEngine.global(reclamos) }
    private var porAnio: [ResumenPeriodo] { ReporteEngine.porAnio(reclamos) }
    private var porPoliza: [ResumenPeriodo] { ReporteEngine.porPoliza(reclamos, anio: nil) }
    private var deducibles: [DeducibleInfo] { ReporteEngine.deducibles(coberturas) }

    var body: some View {
        NavigationStack {
            List {
                seccionGlobal
                seccionPorAnio
                seccionPorPoliza
                seccionDeducibles
                seccionExportar
            }
            .navigationTitle("Reportes")
        }
    }

    // MARK: - Global

    private var seccionGlobal: some View {
        Section("Resumen global") {
            VStack(alignment: .leading, spacing: Tema.espacio) {
                filaMonto("Total reclamado", global.totalReclamado)
                filaMonto("Total reembolsado", global.totalReembolsado)
                filaMonto("Pendiente", global.pendiente)
                Divider()
                HStack {
                    Text("Tasa de aprobación")
                    Spacer()
                    Text(porcentaje(global.tasaAprobacion))
                        .fontWeight(.semibold)
                }
                HStack {
                    Text("Días promedio de respuesta")
                    Spacer()
                    Text(dias(global.diasPromedioRespuesta))
                        .fontWeight(.semibold)
                }
                HStack {
                    Text("Reclamos")
                    Spacer()
                    Text("\(global.cantidadReclamos)")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Por año

    private var seccionPorAnio: some View {
        Section("Por año") {
            if porAnio.isEmpty {
                Text("Sin datos").foregroundStyle(.secondary)
            } else {
                ForEach(porAnio) { filaResumen($0) }
            }
        }
    }

    // MARK: - Por póliza

    private var seccionPorPoliza: some View {
        Section("Por póliza") {
            if porPoliza.isEmpty {
                Text("Sin datos").foregroundStyle(.secondary)
            } else {
                ForEach(porPoliza) { filaResumen($0) }
            }
        }
    }

    // MARK: - Deducibles

    private var seccionDeducibles: some View {
        Section("Deducibles") {
            if deducibles.isEmpty {
                Text("Sin coberturas").foregroundStyle(.secondary)
            } else {
                ForEach(deducibles) { info in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(info.poliza).font(.subheadline).fontWeight(.medium)
                        if let anual = info.anual, anual > 0 {
                            ProgressView(value: info.progreso)
                                .tint(Tema.acento)
                            HStack {
                                Text("\(Formato.montoUSD(info.consumido)) consumido")
                                Spacer()
                                Text("de \(Formato.montoUSD(anual))")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        } else {
                            Text("Sin tope definido")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - Exportar

    private var seccionExportar: some View {
        Section("Exportar") {
            Button {
                exportarCSV()
            } label: {
                Label("Exportar CSV", systemImage: "square.and.arrow.up")
            }

            if let csvURL {
                ShareLink(item: csvURL) {
                    Label("Compartir archivo", systemImage: "paperplane")
                }
            }

            if let errorExport {
                Text(errorExport)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Text("La exportación ZIP de un reclamo (PDFs) está disponible desde el detalle del reclamo.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func exportarCSV() {
        do {
            csvURL = try Exportador.csvReclamos(reclamos)
            errorExport = nil
        } catch {
            csvURL = nil
            errorExport = "No se pudo generar el CSV: \(error.localizedDescription)"
        }
    }

    // MARK: - Componentes reutilizables

    @ViewBuilder
    private func filaResumen(_ r: ResumenPeriodo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(r.titulo).fontWeight(.semibold)
                Spacer()
                Text("\(r.cantidadReclamos) reclamos")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("Reclamado \(Formato.montoUSD(r.totalReclamado))")
                Spacer()
                Text("Reembolsado \(Formato.montoUSD(r.totalReembolsado))")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            HStack {
                Text("Pendiente \(Formato.montoUSD(r.pendiente))")
                Spacer()
                Text("Aprob. \(porcentaje(r.tasaAprobacion))")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func filaMonto(_ titulo: String, _ monto: Decimal) -> some View {
        HStack {
            Text(titulo)
            Spacer()
            Text(Formato.montoUSD(monto)).fontWeight(.semibold)
        }
    }

    private func porcentaje(_ valor: Double) -> String {
        "\(Int((valor * 100).rounded()))%"
    }

    private func dias(_ valor: Double) -> String {
        valor > 0 ? "\(Int(valor.rounded())) días" : "—"
    }
}
