import SwiftUI
import SwiftData

/// Raíz de la pestaña Seguros. Alterna entre aseguradoras y pólizas.
struct SegurosView: View {
    private enum Modo: String, CaseIterable {
        case aseguradoras, polizas
        var etiqueta: String {
            switch self {
            case .aseguradoras: return "Aseguradoras"
            case .polizas: return "Pólizas"
            }
        }
    }

    @State private var modo: Modo = .aseguradoras

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Vista", selection: $modo) {
                    ForEach(Modo.allCases, id: \.self) { m in
                        Text(m.etiqueta).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)

                switch modo {
                case .aseguradoras: AseguradorasListView()
                case .polizas: PolizasListView()
                }
            }
            .navigationTitle("Seguros")
        }
    }
}
