import SwiftUI

struct LauncherView: View {
    @State private var mode: Mode? = nil

    enum Mode {
        case swiftUI
        case uiKit
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Choose UI Mode")
                    .font(.largeTitle)
                    .padding(.top, 40)

                Button(action: { mode = .swiftUI }) {
                    Text("Use SwiftUI Demo")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)

                Button(action: { mode = .uiKit }) {
                    Text("Use UIKit Demo")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .padding(.horizontal)

                Spacer()
            }
            .navigationTitle("Demo Launcher")
            .background(
                // Navigation to chosen mode
                NavigationLink(destination: destinationView(), isActive: Binding(get: { mode != nil }, set: { active in if !active { mode = nil } })) {
                    EmptyView()
                }
                .hidden()
            )
        }
    }

    @ViewBuilder
    private func destinationView() -> some View {
        switch mode {
        case .swiftUI:
            ContentView()
        case .uiKit:
            UIKitContainer()
        case .none:
            EmptyView()
        }
    }
}

#Preview {
    LauncherView()
}
