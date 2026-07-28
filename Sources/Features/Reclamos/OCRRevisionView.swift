import SwiftUI
import SwiftData

// Tarjeta "Detectamos esto" (§7.2). El OCR NUNCA decide solo: se muestran los
// campos rellenados y editables, y el usuario confirma. Monto vacío si baja confianza.

struct OCRRevisionView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var documento: Documento
    let reclamo: Reclamo
    let campos: CamposDetectados
    var onListo: () -> Void

    @State private var tieneFecha: Bool = false
    @State private var fecha: Date = Date()
    @State private var montoTexto: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Image(systemName: "sparkles.rectangle.stack")
                            .foregroundStyle(Tema.acento)
                        Text("Detectamos esto en el documento. Revisa y corrige antes de confirmar.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }

                Section("Tipo") {
                    Picker("Tipo de documento", selection: $documento.tipo) {
                        ForEach(TipoDocumento.allCases, id: \.self) { t in
                            Label(t.etiqueta, systemImage: t.simbolo).tag(t)
                        }
                    }
                }

                if documento.tipo.esFacturable {
                    Section {
                        HStack {
                            Text("USD")
                            TextField("0.00", text: $montoTexto)
                                .keyboardType(.decimalPad)
                        }
                    } header: {
                        Text("Monto")
                    } footer: {
                        if campos.monto == nil && campos.montoConfianza > 0 {
                            Text("No detectamos el monto con confianza. Escríbelo tú.")
                                .foregroundStyle(.orange)
                        }
                    }
                }

                Section("Datos de la factura") {
                    Toggle("Tiene fecha", isOn: $tieneFecha)
                    if tieneFecha {
                        DatePicker("Fecha del documento", selection: $fecha, displayedComponents: .date)
                    }
                    TextField("Emisor", text: $documento.emisor)
                    TextField("RUC", text: $documento.ruc).keyboardType(.numbersAndPunctuation)
                    TextField("Nº de factura", text: $documento.numeroFactura)
                }

                if !campos.medicoSugerido.isEmpty && reclamo.medico.isEmpty {
                    Section {
                        Button {
                            reclamo.medico = campos.medicoSugerido
                        } label: {
                            Label("Usar médico detectado: \(campos.medicoSugerido)", systemImage: "stethoscope")
                        }
                    }
                }
            }
            .navigationTitle("Revisar OCR")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Omitir") { finalizar(confirmado: false) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirmar") { finalizar(confirmado: true) }
                }
            }
            .onAppear(perform: cargar)
        }
    }

    private func cargar() {
        if let f = documento.fechaDocumento { tieneFecha = true; fecha = f }
        if let m = documento.monto { montoTexto = Formato.monto(m) }
    }

    private func finalizar(confirmado: Bool) {
        documento.fechaDocumento = tieneFecha ? fecha : nil
        let limpio = montoTexto.replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        documento.monto = Decimal(string: limpio)
        documento.ocrConfirmadoPorUsuario = confirmado
        MoneyCalc.recalcularMonto(reclamo)
        onListo()
        dismiss()
    }
}
