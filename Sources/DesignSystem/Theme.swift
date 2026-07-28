import SwiftUI

// Tokens de diseño. Paleta sobria, acento azul médico.

enum Tema {
    static let acento = Color.accentColor
    static let fondo = Color(.systemGroupedBackground)
    static let tarjeta = Color(.secondarySystemGroupedBackground)

    static let radio: CGFloat = 14
    static let espacio: CGFloat = 16
}

extension EstadoReclamo {
    var color: Color {
        switch self {
        case .borrador: return .gray
        case .enviado: return .blue
        case .enRevision: return .orange
        case .aprobado: return .teal
        case .pagado: return .green
        case .rechazado: return .red
        case .requiereDocumentos: return .yellow
        }
    }
}

// Color del peso total del correo (§13.2): verde <10MB, ámbar 10–20, rojo >20.
enum PesoColor {
    static func color(bytes: Int) -> Color {
        let mb = Double(bytes) / (1024 * 1024)
        if mb < 10 { return .green }
        if mb <= 20 { return .orange }
        return .red
    }
}

// Color desde hex "#RRGGBB" para logos/aseguradoras.
extension Color {
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = Int(s, radix: 16) else { return nil }
        self.init(
            red: Double((v >> 16) & 0xFF) / 255,
            green: Double((v >> 8) & 0xFF) / 255,
            blue: Double(v & 0xFF) / 255
        )
    }
}
