import SwiftUI

struct MainTabView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var inbox: [URL] = []
    @State private var mostrarImport = false

    var body: some View {
        TabView {
            ReclamosListView()
                .tabItem { Label("Reclamos", systemImage: "doc.text.fill") }
            PacientesListView()
                .tabItem { Label("Pacientes", systemImage: "person.2.fill") }
            RecetasView()
                .tabItem { Label("Recetas", systemImage: "pills.fill") }
            SegurosView()
                .tabItem { Label("Seguros", systemImage: "shield.lefthalf.filled") }
            AjustesView()
                .tabItem { Label("Ajustes", systemImage: "gearshape.fill") }
        }
        .onAppear(perform: revisarInbox)
        .onChange(of: scenePhase) { _, fase in
            if fase == .active { revisarInbox() }
        }
        .sheet(isPresented: $mostrarImport) {
            ImportarInboxView(archivos: inbox)
        }
    }

    private func revisarInbox() {
        let pend = AppGroup.pendientes()
        guard !pend.isEmpty else { return }
        inbox = pend
        mostrarImport = true
    }
}
