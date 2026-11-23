import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var car: CarController
    @Environment(\.dismiss) private var dismiss
    @State private var keyText = ""
    @State private var keyError: String?
    @State private var confirmRemoveKey = false
    @State private var confirmForget = false
    @State private var showPairingHelp = false

    var body: some View {
        NavigationStack {
            ZStack {
                EmberBackground(running: car.status.engineRunning)

                ScrollView {
                    VStack(spacing: 22) {
                        carSection
                        connectionSection
                        if !car.demoMode || !car.hasKey { keySection }
                        securitySection
                        startSection
                        aboutSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { car.relayHostChanged(); dismiss() } }
            }
            .confirmationDialog("Remove the bridge key from this iPhone?",
                                isPresented: $confirmRemoveKey, titleVisibility: .visible) {
                Button("Remove key", role: .destructive) { car.removeKey() }
            } message: {
                Text("You'll need to paste it again before the app can control the car.")
            }
            .confirmationDialog("Search for a different bridge?",
                                isPresented: $confirmForget, titleVisibility: .visible) {
                Button("Forget and search again", role: .destructive) { car.forgetBridge() }
            } message: {
                Text("Use this after replacing the board in your car.")
            }
            .sheet(isPresented: $showPairingHelp) { PairingHelpView() }
        }
    }

    // MARK: Sections

    private var carSection: some View {
        SettingsSection("Car") {
            HStack(spacing: 14) {
                RowIcon("car.fill", Palette.accent)
                TextField("Car name", text: $car.carName)
                    .font(.body.weight(.medium))
                    .submitLabel(.done)
                    .onChange(of: car.carName) { _, name in
                        if name.count > 40 { car.carName = String(name.prefix(40)) }
                    }
            }
        }
    }

    private var connectionSection: some View {
        SettingsSection("Connection",
                        footer: car.demoMode
                            ? "Demo mode uses a pretend car so you can try everything without the bridge."
                            : "Bluetooth and cellular both use the same bridge key, and every command is signed with it.") {
            ToggleRow(icon: "sparkles", color: Palette.accentSoft,
                      title: "Demo mode", subtitle: "Practice with a pretend car",
                      isOn: $car.demoMode)
            if !car.demoMode {
                Divider().overlay(Palette.stroke)
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 14) {
                        RowIcon(car.connectionMode == .bluetooth ? "dot.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right",
                                Palette.cool)
                        Text("Connect using").font(.body.weight(.medium))
                    }
                    Picker("Connect using", selection: $car.connectionMode) {
                        ForEach(ConnectionMode.allCases) { mode in Text(mode.title).tag(mode) }
                    }
                    .pickerStyle(.segmented)
                    Text(car.connectionMode.explanation)
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if car.connectionMode != .bluetooth {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Relay server").font(.subheadline.weight(.medium))
                        TextField("ember-relay.yourname.workers.dev", text: $car.relayHost)
                            .font(.system(.footnote, design: .monospaced))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .submitLabel(.done)
                            .onSubmit { car.relayHostChanged() }
                            .padding(12)
                            .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
                        Text("Shown at the end of the server deploy on GitHub (see README, \"Cellular\").")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }
            Divider().overlay(Palette.stroke)
            HStack(spacing: 14) {
                RowIcon("antenna.radiowaves.left.and.right", car.link.isUsable ? Palette.good : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Status").font(.body.weight(.medium))
                    Text(car.link.label).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
            }
            if !car.demoMode {
                Divider().overlay(Palette.stroke)
                ButtonRow(icon: "arrow.triangle.2.circlepath", color: Palette.cool,
                          title: "Find my bridge again") { confirmForget = true }
                Divider().overlay(Palette.stroke)
                ButtonRow(icon: "questionmark.circle", color: Palette.cool,
                          title: "Pairing help") { showPairingHelp = true }
            }
        }
    }

    private var keySection: some View {
        SettingsSection("Bridge key",
                        footer: "Must match EMBER_SECRET_HEX in the bridge firmware. It's kept in the iPhone Keychain and never leaves this phone.") {
            if car.hasKey {
                HStack(spacing: 14) {
                    RowIcon("checkmark.seal.fill", Palette.good)
                    Text("Key saved on this iPhone").font(.body.weight(.medium))
                    Spacer()
                }
                Divider().overlay(Palette.stroke)
                ButtonRow(icon: "trash", color: .red, title: "Remove key", destructive: true) {
                    confirmRemoveKey = true
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 14) {
                        RowIcon("key.fill", Palette.accent)
                        Text("Paste your 64-character key").font(.body.weight(.medium))
                    }
                    TextField("Paste key here", text: $keyText, axis: .vertical)
                        .font(.system(.footnote, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(12)
                        .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
                        .onChange(of: keyText) { _, _ in keyError = nil }
                    if let keyError {
                        Text(keyError).font(.footnote).foregroundStyle(.red)
                    }
                    Button {
                        if car.saveKey(hex: keyText) { keyText = "" }
                        else { keyError = "That isn't a 64-character key. Copy the exact EMBER_SECRET_HEX value from config.h." }
                    } label: {
                        Text("Save key")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .glassCard(14, tint: Palette.accent.opacity(0.45), interactive: true)
                    }
                    .buttonStyle(.plain)
                    .disabled(keyText.isEmpty)
                    .opacity(keyText.isEmpty ? 0.5 : 1)
                }
            }
        }
    }

    private var securitySection: some View {
        SettingsSection("Security",
                        footer: "When on, Unlock and Start ask for Face ID (or your passcode) first. Lock and Stop never ask.") {
            ToggleRow(icon: "faceid", color: Palette.good,
                      title: "Face ID for Unlock and Start", subtitle: "Stops anyone else using your unlocked phone",
                      isOn: $car.requireFaceID)
        }
    }

    private var startSection: some View {
        SettingsSection("Remote start") {
            ToggleRow(icon: "windshield.rear.and.heat.waves", color: Palette.cool,
                      title: "Rear defrost with every start", subtitle: "Turns on once the engine is running",
                      isOn: $car.defrostOnStart)
            Divider().overlay(Palette.stroke)
            ToggleRow(icon: "iphone.radiowaves.left.and.right", color: Palette.accentSoft,
                      title: "Vibration feedback", subtitle: "Buzz when a command goes through",
                      isOn: $car.hapticsOn)
        }
    }

    private var aboutSection: some View {
        SettingsSection("About") {
            HStack(spacing: 14) {
                RowIcon("flame.fill", Palette.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ember").font(.body.weight(.medium))
                    Text("Version \(car.appVersion)").font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }
}

// MARK: - Building blocks

struct SettingsSection<Content: View>: View {
    let title: String
    let footer: String?
    let content: Content

    init(_ title: String, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 6)
            VStack(alignment: .leading, spacing: 12) { content }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard(24)
            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
            }
        }
    }
}

struct RowIcon: View {
    let name: String
    let color: Color
    init(_ name: String, _ color: Color) { self.name = name; self.color = color }

    var body: some View {
        Image(systemName: name)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 32, height: 32)
            .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

struct ToggleRow: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 14) {
                RowIcon(icon, color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.medium))
                    Text(subtitle).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .tint(color)
    }
}

struct ButtonRow: View {
    let icon: String
    let color: Color
    let title: String
    var destructive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                RowIcon(icon, color)
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(destructive ? Color.red : Color.primary)
                Spacer()
                Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Pairing help

struct PairingHelpView: View {
    @Environment(\.dismiss) private var dismiss

    private let steps: [(String, String)] = [
        ("1.circle.fill", "Turn off Demo mode and stand within about 30 feet of the car."),
        ("2.circle.fill", "When iPhone asks for a passkey, enter the 6-digit EMBER_PASSKEY from config.h."),
        ("3.circle.fill", "Wait for the status to say Connected. The app reconnects by itself after that."),
        ("arrow.counterclockwise.circle.fill", "Re-flashed the bridge? In iPhone Settings › Bluetooth, tap ⓘ next to Ember Bridge, choose Forget This Device, then reopen Ember."),
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                EmberBackground(running: false)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(steps.indices, id: \.self) { i in
                            let step = steps[i]
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: step.0)
                                    .font(.title2)
                                    .foregroundStyle(Palette.accent)
                                Text(step.1).font(.body)
                                Spacer(minLength: 0)
                            }
                            .padding(16)
                            .glassCard(20)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Pairing help")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
