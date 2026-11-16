import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var car: CarController
    @Environment(\.dismiss) private var dismiss
    @State private var keyText = ""
    @State private var keyError: String?
    @State private var confirmRemove = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Car") {
                    TextField("Name", text: $car.carName)
                }

                Section {
                    Toggle("Demo mode", isOn: $car.demoMode)
                } footer: {
                    Text("Demo mode uses a pretend car so you can try the app without the bridge. Turn it off to connect to your car over Bluetooth.")
                }

                Section {
                    if car.hasKey {
                        Label("Key saved on this iPhone", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                        Button("Remove key", role: .destructive) { confirmRemove = true }
                    } else {
                        TextField("64 hex characters", text: $keyText, axis: .vertical)
                            .font(.system(.footnote, design: .monospaced))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Save key") {
                            if car.saveKey(hex: keyText) {
                                keyText = ""
                                keyError = nil
                            } else {
                                keyError = "That isn't a 64-character hex key. Copy the exact EMBER_SECRET_HEX value from config.h."
                            }
                        }
                        .disabled(keyText.isEmpty)
                        if let keyError {
                            Text(keyError).font(.footnote).foregroundStyle(.red)
                        }
                    }
                } header: {
                    Text("Bridge key")
                } footer: {
                    Text("This must match EMBER_SECRET_HEX in the bridge firmware. It's stored in the iPhone Keychain and never leaves this phone.")
                }

                Section("Pairing help") {
                    Text("The first time you connect, iOS asks for a 6-digit passkey. Enter the EMBER_PASSKEY value from config.h.")
                    Text("If you re-flash the bridge, go to iPhone Settings › Bluetooth, tap ⓘ next to Ember Bridge, and choose Forget This Device. Then reopen the app.")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .confirmationDialog("Remove the bridge key from this iPhone?",
                                isPresented: $confirmRemove, titleVisibility: .visible) {
                Button("Remove key", role: .destructive) { car.removeKey() }
            }
        }
    }
}
