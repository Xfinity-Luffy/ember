import SwiftUI

@main
struct EmberApp: App {
    @StateObject private var car = CarController()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(car)
                .preferredColorScheme(.dark)
                .tint(Palette.accent)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { car.appBecameActive() }
        }
    }
}
