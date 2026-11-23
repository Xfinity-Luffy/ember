import SwiftUI

@main
struct EmberApp: App {
    @StateObject private var car = CarController()
    @StateObject private var locator = CarLocator()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(car)
                .environmentObject(locator)
                .preferredColorScheme(.dark)
                .tint(Palette.accent)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                car.appBecameActive()
                locator.start()
            } else if phase == .background {
                locator.stop()
            }
        }
    }
}
