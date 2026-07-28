import SwiftUI

// Pantalla de alarma a pantalla completa cuando llega la hora de la toma.
// Mientras está visible, AlarmaCoordinator reproduce el sonido en loop.

struct AlarmaView: View {
    @EnvironmentObject private var coordinator: AlarmaCoordinator
    let info: AlarmaCoordinator.AlarmaInfo
    @State private var pulso = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Tema.acento, Tema.acento.opacity(0.7)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "pills.fill")
                    .font(.system(size: 90))
                    .foregroundStyle(.white)
                    .scaleEffect(pulso ? 1.12 : 0.92)
                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: pulso)

                Text("Hora de tu medicamento")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))

                VStack(spacing: 6) {
                    Text(info.dosis.isEmpty ? info.nombre : "\(info.dosis) — \(info.nombre)")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                    if !info.instrucciones.isEmpty {
                        Text(info.instrucciones)
                            .font(.headline)
                            .foregroundStyle(.white.opacity(0.9))
                            .multilineTextAlignment(.center)
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal)

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        coordinator.tome()
                    } label: {
                        Text("Ya la tomé")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.white, in: Capsule())
                            .foregroundStyle(Tema.acento)
                    }
                    Button {
                        coordinator.posponer()
                    } label: {
                        Text("Posponer 10 min")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .overlay(Capsule().stroke(.white, lineWidth: 1.5))
                            .foregroundStyle(.white)
                    }
                    Button { coordinator.saltar() } label: {
                        Text("Saltar esta toma")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .padding(.top, 2)
                }
                .padding()
            }
        }
        .onAppear { pulso = true }
    }
}
