import SwiftUI

/// Shown when there are no vehicles: on first launch, or after the last one is removed.
struct WelcomeView: View {
    @EnvironmentObject private var car: CarController
    @Binding var showSettings: Bool
    @State private var adding = false

    var body: some View {
        ZStack {
            EmberBackground(running: false)

            ScrollView {
                VStack(spacing: 22) {
                    HStack {
                        Spacer()
                        SettingsButton { showSettings = true }
                    }
                    .padding(.top, 8)

                    // Three silhouettes, back to front
                    ZStack {
                        VehicleSilhouette(type: .truck, color: Color(white: 0.35))
                            .frame(height: 70)
                            .offset(x: 70, y: -26)
                            .opacity(0.55)
                        VehicleSilhouette(type: .suv, color: VehicleColor.blue.swatch)
                            .frame(height: 78)
                            .offset(x: -64, y: -14)
                            .opacity(0.75)
                        VehicleSilhouette(type: .hatchback, color: VehicleColor.red.swatch, running: true)
                            .frame(height: 96)
                            .offset(y: 26)
                    }
                    .frame(height: 190)
                    .padding(.top, 4)
                    .accessibilityHidden(true)

                    VStack(spacing: 8) {
                        Text("Add your first vehicle")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .multilineTextAlignment(.center)
                        Text("Ember locks, unlocks and starts your car through a small Bluetooth bridge wired to its remote starter. Add the car now and pair the bridge whenever it's ready.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 6)

                    VStack(spacing: 10) {
                        Button { adding = true } label: {
                            Label("Add a vehicle", systemImage: "plus")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .glassCard(20, tint: Palette.accent.opacity(0.55), interactive: true)
                        }
                        .buttonStyle(.plain)

                        Button { car.addDemoVehicle() } label: {
                            Label("Try the demo car", systemImage: "sparkles")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .glassCard(20, interactive: true)
                        }
                        .buttonStyle(.plain)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        Text("What you'll need").font(.headline)
                        need("bolt.car.fill", "A remote starter in the car",
                             "A Fortin module, installed by a shop. It does the starting and locking.")
                        need("cpu", "The Ember bridge",
                             "A small ESP32 board wired to the remote starter. Ember talks to it over Bluetooth.")
                        need("key.fill", "The bridge's key",
                             "Made with the key generator. Scan its QR code when you add the car, or later in Settings.")
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard(24)

                    Text("You can add up to \(Vehicle.maxCount) vehicles. The demo car is pretend, so nothing is sent anywhere.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
        }
        .sheet(isPresented: $adding) { VehicleEditView(original: nil).environmentObject(car) }
    }

    private func need(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            RowIcon(symbol, Palette.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(text).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}
