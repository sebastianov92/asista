import SwiftUI
import SwiftData

// Reclamos secundarios / coordinación de beneficios (§3.3, §15.2).
// Se crea un reclamo nuevo apuntando a OTRA póliza del mismo paciente, enlazado al
// origen. Se referencian (no se duplican) los PDFs del origen y se exige adjuntar
// la liquidación de la primera aseguradora.

enum ReclamoSecundario {
    @MainActor
    static func crear(origen: Reclamo, coberturaDestino: Cobertura, siguienteNumero: Int, ctx: ModelContext) -> Reclamo {
        let sec = Reclamo(cobertura: coberturaDestino)
        sec.numero = siguienteNumero
        sec.reclamoOrigen = origen
        sec.fechaEvento = origen.fechaEvento
        sec.prestador = origen.prestador
        sec.medico = origen.medico
        sec.diagnostico = origen.diagnostico
        sec.codigoCIE10 = origen.codigoCIE10
        // El monto a reclamar es el saldo no cubierto por la primera póliza.
        sec.montoManual = true
        sec.montoReclamado = origen.pendiente
        sec.tomarSnapshot()
        ctx.insert(sec)

        // Referenciar los PDFs del origen (mismo archivo, sin duplicar), como
        // documentos del secundario para que viajen en el correo.
        for doc in origen.documentos.sorted(by: { $0.orden < $1.orden }) where !doc.rutaPDF.isEmpty {
            let ref = Documento(tipo: doc.tipo, orden: doc.orden)
            ref.tipoPersonalizado = doc.tipoPersonalizado
            ref.rutaPDF = doc.rutaPDF
            ref.tamanoBytes = doc.tamanoBytes
            ref.preajusteCalidad = doc.preajusteCalidad
            ctx.insert(ref)
            ref.reclamo = sec
        }

        // Checklist = el del origen + la liquidación de la aseguradora (obligatoria).
        var checklist = origen.checklist
        if !checklist.contains(.liquidacionAseguradora) { checklist.append(.liquidacionAseguradora) }
        sec.checklist = checklist

        try? ctx.save()
        return sec
    }
}

struct CrearSecundarioView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    let origen: Reclamo
    @Query private var todosReclamos: [Reclamo]

    @State private var coberturaDestino: Cobertura?
    @State private var creado: Reclamo?

    /// Coberturas activas del mismo paciente, distintas a la del origen.
    private var opciones: [Cobertura] {
        let pac = origen.cobertura?.paciente
        return (pac?.coberturas ?? [])
            .filter { $0.activa && $0.id != origen.cobertura?.id }
            .sorted { ($0.poliza?.prioridad ?? 0) < ($1.poliza?.prioridad ?? 0) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Saldo a reclamar", value: Formato.montoUSD(origen.pendiente))
                } footer: {
                    Text("Se reclamará a una segunda póliza el saldo que la primera no cubrió. Los documentos del reclamo original se adjuntan automáticamente; deberás agregar la liquidación de la primera aseguradora.")
                }

                Section("Segunda póliza") {
                    if opciones.isEmpty {
                        Text("Este paciente no tiene otra cobertura activa. Agrégala en su perfil.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Póliza destino", selection: $coberturaDestino) {
                            Text("Selecciona…").tag(Cobertura?.none)
                            ForEach(opciones) { c in
                                Text(c.poliza?.nombreVisible ?? "Póliza").tag(Cobertura?.some(c))
                            }
                        }
                    }
                }
            }
            .navigationTitle("Reclamo secundario")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Crear") { crear() }.disabled(coberturaDestino == nil)
                }
            }
            .navigationDestination(item: $creado) { r in
                ReclamoDetailView(reclamo: r)
            }
        }
    }

    private func crear() {
        guard let destino = coberturaDestino else { return }
        let siguiente = (todosReclamos.map(\.numero).max() ?? 0) + 1
        creado = ReclamoSecundario.crear(origen: origen, coberturaDestino: destino, siguienteNumero: siguiente, ctx: ctx)
    }
}
