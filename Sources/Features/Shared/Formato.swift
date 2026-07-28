import Foundation

// Formateo consistente de dinero y fechas. Ecuador, USD.

enum Formato {
    private static let monedaFmt: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        f.locale = Locale(identifier: "es_EC")
        return f
    }()

    /// "1,847.30" (sin símbolo; la UI antepone "USD").
    static func monto(_ d: Decimal) -> String {
        monedaFmt.string(from: d as NSDecimalNumber) ?? "0.00"
    }

    static func montoUSD(_ d: Decimal) -> String { "USD \(monto(d))" }

    private static let fechaLarga: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_EC")
        f.dateFormat = "d 'de' MMMM 'de' yyyy"
        return f
    }()

    private static let fechaCorta: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_EC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func fecha(_ d: Date) -> String { fechaLarga.string(from: d) }
    static func fechaISO(_ d: Date) -> String { fechaCorta.string(from: d) }

    /// Peso de archivo legible: "1.4 MB", "320 KB".
    static func peso(_ bytes: Int) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: Int64(bytes))
    }

    static func diasDesde(_ d: Date) -> Int {
        Calendar.current.dateComponents([.day], from: d, to: Date()).day ?? 0
    }
}
