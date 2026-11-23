import SwiftUI

@main
struct EmberApp: App {
    @StateObject private var car = CarController.shared
    @StateObject private var locator = CarLocator()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            AppearanceRoot {
                ContentView()
                    .environmentObject(car)
                    .environmentObject(locator)
                    .tint(Palette.accent)
            }
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
