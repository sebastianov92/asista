import SwiftUI
import UIKit

// Envoltura de UIActivityViewController para compartir archivos generados al vuelo.

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

/// URL identificable para usar en `.sheet(item:)`.
struct URLItem: Identifiable {
    let id = UUID()
    let url: URL
}
