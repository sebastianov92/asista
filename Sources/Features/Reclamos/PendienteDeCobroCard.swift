import SwiftUI

// Panel "Pendiente de cobro" (§15.1). Primera cosa que se ve en la pestaña.

struct PendienteDeCobroCard: View {
    let reclamos: [Reclamo]
    var onFiltrar: (EstadoReclamo) -> Void

    private var p: PendienteDeCobro { MoneyCalc.pendiente(reclamos) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pendiente de cobro")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(Formato.montoUSD(p.total))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(Tema.acento)
            Text("en \(p.cantidad) \(p.cantidad == 1 ? "reclamo" : "reclamos")")
                .font(.footnote)
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                linea(.enviado, p.enviados)
                linea(.enRevision, p.enRevision)
                linea(.aprobado, p.aprobados)
                if p.requiereDocumentos > 0 { linea(.requiereDocumentos, p.requiereDocumentos) }
            }
            .padding(.top, 2)

            if let atrasado = p.reclamoMasAtrasado, p.diasAtraso > 0 {
                Divider()
                Button {
                    onFiltrar(atrasado.estado)
                } label: {
                    Label("1 reclamo sin respuesta hace \(p.diasAtraso) d",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Tema.espacio)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tema.tarjeta, in: RoundedRectangle(cornerRadius: Tema.radio))
        .padding(.horizontal)
        .padding(.top, 4)
    }

    @ViewBuilder
    private func linea(_ estado: EstadoReclamo, _ monto: Decimal) -> some View {
        Button {
            onFiltrar(estado)
        } label: {
            HStack {
                Circle().fill(estado.color).frame(width: 8, height: 8)
                Text(estado.etiqueta).font(.footnote)
                Spacer()
                Text(Formato.montoUSD(monto)).font(.footnote.monospacedDigit())
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }
}
