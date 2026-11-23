import SwiftUI
import UIKit

// MARK: - Vehicle switcher (tap the car's name)

struct VehiclesView: View {
    @EnvironmentObject private var car: CarController
    @Environment(\.dismiss) private var dismiss
    @State private var editing: Vehicle?
    @State private var adding = false

    var body: some View {
        NavigationStack {
            ZStack {
                EmberBackground(running: false)
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(car.vehicles) { v in
                            VehicleRow(vehicle: v,
                                       selected: v.id == car.selectedVehicleID,
                                       hasKey: car.hasKey(for: v),
                                       onSelect: {
                                           car.selectVehicle(v.id)
                                           dismiss()
                                       },
                                       onEdit: { editing = v })
                        }

                        Button { adding = true } label: {
                            Label(car.canAddVehicle ? "Add a vehicle" : "You have the maximum of \(Vehicle.maxCount)",
                                  systemImage: car.canAddVehicle ? "plus.circle.fill" : "checkmark.circle")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .glassCard(20, tint: car.canAddVehicle ? Palette.accent.opacity(0.3) : nil, interactive: true)
                        }
                        .buttonStyle(.plain)
                        .disabled(!car.canAddVehicle)
                        .opacity(car.canAddVehicle ? 1 : 0.5)

                        Text("\(car.vehicles.count) of \(Vehicle.maxCount) · Each vehicle has its own bridge, key, connection and parking spot.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("My vehicles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(item: $editing) { v in VehicleEditView(original: v).environmentObject(car) }
            .sheet(isPresented: $adding) { VehicleEditView(original: nil).environmentObject(car) }
        }
    }
}

private struct VehicleRow: View {
    let vehicle: Vehicle
    let selected: Bool
    let hasKey: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onSelect) {
                HStack(spacing: 14) {
                    CarTopView(lowTires: [false, false, false, false], bodyColor: vehicle.color.swatch)
                        .frame(width: 30, height: 60)
                        .rotationEffect(.degrees(90))
                        .frame(width: 60, height: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(vehicle.name).font(.headline).lineLimit(1)
                        Text(subtitle).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                        HStack(spacing: 6) {
                            Label(vehicle.connection.title, systemImage: vehicle.connection == .bluetooth
                                  ? "dot.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right")
                            if !hasKey {
                                Label("No key", systemImage: "key.slash").foregroundStyle(.orange)
                            }
                        }
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Palette.accent)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 36, height: 36)
                    .glass(Circle(), interactive: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit \(vehicle.name)")
        }
        .padding(14)
        .glassCard(22, tint: selected ? Palette.accent.opacity(0.18) : nil)
    }

    private var subtitle: String {
        let parts = [vehicle.description, vehicle.plate.isEmpty ? "" : "Plate \(vehicle.plate)"].filter { !$0.isEmpty }
        return parts.isEmpty ? "Tap the pencil to add details" : parts.joined(separator: " · ")
    }
}

// MARK: - Add / edit a vehicle

struct VehicleEditView: View {
    @EnvironmentObject private var car: CarController
    @Environment(\.dismiss) private var dismiss

    let original: Vehicle?
    @State private var draft: Vehicle
    @State private var keyText = ""
    @State private var error: String?
    @State private var lookingUp = false
    @State private var lookupNote: String?
    @State private var confirmDelete = false

    init(original: Vehicle?) {
        self.original = original
        _draft = State(initialValue: original ?? Vehicle(name: ""))
    }

    private var isNew: Bool { original == nil }
    private var vinClean: String { VIN.clean(draft.vin) }

    var body: some View {
        NavigationStack {
            ZStack {
                EmberBackground(running: false)
                ScrollView {
                    VStack(spacing: 22) {
                        CarTopView(lowTires: [false, false, false, false], bodyColor: draft.color.swatch)
                            .frame(width: 70, height: 140)
                            .rotationEffect(.degrees(90))
                            .frame(height: 90)
                            .padding(.top, 4)

                        SettingsSection("Name") {
                            TextField("e.g. Mazda3, Work truck", text: $draft.name)
                                .font(.body.weight(.medium))
                                .onChange(of: draft.name) { _, n in if n.count > 40 { draft.name = String(n.prefix(40)) } }
                        }

                        identificationSection
                        colorSection

                        SettingsSection("Connection", footer: draft.connection.explanation) {
                            Picker("Connect using", selection: $draft.connection) {
                                ForEach(ConnectionMode.allCases) { Text($0.title).tag($0) }
                            }
                            .pickerStyle(.segmented)
                        }

                        keySection

                        if !isNew && car.vehicles.count > 1 {
                            Button(role: .destructive) { confirmDelete = true } label: {
                                Label("Remove this vehicle", systemImage: "trash")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.red)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .glassCard(18, interactive: true)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle(isNew ? "Add a vehicle" : "Edit vehicle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Add" : "Save") { save() }
                        .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let error {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .glassCard(14)
                        .padding(.horizontal, 20)
                }
            }
            .confirmationDialog("Remove \(draft.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Remove vehicle", role: .destructive) {
                    car.deleteVehicle(draft.id)
                    dismiss()
                }
            } message: {
                Text("Its key, remembered bridge and parking spot are deleted from this iPhone.")
            }
        }
    }

    // MARK: Identification

    private var identificationSection: some View {
        SettingsSection("Identification",
                        footer: "Look up fills in the details from the VIN using NHTSA's free public vehicle database. The VIN stays on this iPhone; only the lookup is sent to NHTSA.") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    TextField("VIN (17 characters)", text: $draft.vin)
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .onChange(of: draft.vin) { _, v in
                            let c = VIN.clean(v)
                            if c != v { draft.vin = String(c.prefix(17)) }
                            lookupNote = nil
                        }
                    Button { lookUp() } label: {
                        Group {
                            if lookingUp { ProgressView().tint(.white) }
                            else { Text("Look up").font(.subheadline.weight(.semibold)) }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .glass(Capsule(), tint: Palette.accent.opacity(0.4), interactive: true)
                    }
                    .buttonStyle(.plain)
                    .disabled(!VIN.isWellFormed(vinClean) || lookingUp)
                    .opacity(VIN.isWellFormed(vinClean) ? 1 : 0.5)
                }
                if let note = vinNote {
                    Label(note.text, systemImage: note.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(note.ok ? Palette.good : .orange)
                }
                Divider().overlay(Palette.stroke)
                HStack(spacing: 10) {
                    field("Year", $draft.year).frame(width: 70)
                    field("Make", $draft.make)
                }
                HStack(spacing: 10) {
                    field("Model", $draft.model)
                    field("Trim", $draft.trim)
                }
                field("License plate", $draft.plate)
                    .textInputAutocapitalization(.characters)
            }
        }
    }

    private func field(_ title: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField(title, text: text)
                .autocorrectionDisabled()
                .padding(10)
                .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var vinNote: (text: String, ok: Bool)? {
        if let lookupNote { return (lookupNote, !lookupNote.hasPrefix("No") && !lookupNote.hasPrefix("Couldn")) }
        guard !vinClean.isEmpty else { return nil }
        if vinClean.count < 17 { return ("\(vinClean.count) of 17 characters", false) }
        if !VIN.isWellFormed(vinClean) { return ("VINs never use the letters I, O or Q", false) }
        if VIN.checkDigitMatches(vinClean) == false { return ("Check digit doesn't match. Double-check the VIN (fine for non-US cars).", false) }
        return ("Looks like a valid VIN", true)
    }

    private func lookUp() {
        lookingUp = true
        Task {
            defer { lookingUp = false }
            do {
                let d = try await VIN.lookUp(vinClean)
                draft.year = d.year; draft.make = d.make.capitalized; draft.model = d.model
                draft.trim = d.trim; draft.body = d.body
                if draft.name.isEmpty { draft.name = d.model.isEmpty ? d.make.capitalized : d.model }
                lookupNote = "Found: \(draft.description)\(d.trim.isEmpty ? "" : " \(d.trim)")"
            } catch {
                lookupNote = error.localizedDescription
            }
        }
    }

    // MARK: Color

    private var colorSection: some View {
        SettingsSection("Color") {
            HStack(spacing: 10) {
                ForEach(VehicleColor.allCases) { c in
                    Button { draft.color = c } label: {
                        Circle()
                            .fill(c.swatch)
                            .frame(width: 30, height: 30)
                            .overlay(Circle().stroke(Color.white.opacity(draft.color == c ? 1 : 0.25),
                                                     lineWidth: draft.color == c ? 3 : 1))
                            .padding(2)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(c.title)
                    .accessibilityAddTraits(draft.color == c ? .isSelected : [])
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Key

    private var keySection: some View {
        SettingsSection("Bridge key",
                        footer: "Each car's bridge has its own key (EMBER_SECRET_HEX in that car's config.h). It's kept in the iPhone Keychain.") {
            VStack(alignment: .leading, spacing: 8) {
                if !isNew && car.hasKey(for: draft) {
                    Label("Key saved", systemImage: "checkmark.seal.fill").foregroundStyle(Palette.good)
                    Text("Paste a new key below only to replace it.").font(.caption).foregroundStyle(.secondary)
                }
                TextField(isNew ? "Paste key (you can add it later)" : "Paste new key", text: $keyText, axis: .vertical)
                    .font(.system(.footnote, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func save() {
        draft.name = draft.name.trimmingCharacters(in: .whitespaces)
        draft.vin = vinClean
        draft.plate = draft.plate.uppercased().trimmingCharacters(in: .whitespaces)
        let result = isNew ? car.addVehicle(draft, keyHex: keyText) : car.updateVehicle(draft, keyHex: keyText)
        if let result { error = result } else { dismiss() }
    }
}

// MARK: - Identification card (Vehicle tab)

struct IdentificationCard: View {
    let vehicle: Vehicle
    let onEdit: () -> Void
    @State private var showVIN = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(vehicle.description.isEmpty ? vehicle.name : vehicle.description)
                        .font(.title3.weight(.bold))
                    if !vehicle.trim.isEmpty || !vehicle.body.isEmpty {
                        Text([vehicle.trim, vehicle.body].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 34, height: 34)
                        .glass(Circle(), interactive: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit vehicle details")
            }

            HStack(spacing: 10) {
                infoPill(icon: "paintpalette.fill", text: vehicle.color.title, dot: vehicle.color.swatch)
                if !vehicle.plate.isEmpty { infoPill(icon: "rectangle.and.text.magnifyingglass", text: vehicle.plate, dot: nil) }
            }

            if vehicle.vin.isEmpty {
                Button(action: onEdit) {
                    Label("Add the VIN to fill in the details", systemImage: "barcode.viewfinder")
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.accentSoft)
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("VIN").font(.caption).foregroundStyle(.secondary)
                        Text(showVIN ? vehicle.vin : VIN.masked(vehicle.vin))
                            .font(.system(.subheadline, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    Spacer()
                    Button { showVIN.toggle() } label: {
                        Image(systemName: showVIN ? "eye.slash" : "eye")
                            .frame(width: 34, height: 34).glass(Circle(), interactive: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(showVIN ? "Hide VIN" : "Show VIN")
                    Button {
                        UIPasteboard.general.string = vehicle.vin
                        Haptics.success()
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .frame(width: 34, height: 34).glass(Circle(), interactive: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Copy VIN")
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(24)
    }

    private func infoPill(icon: String, text: String, dot: Color?) -> some View {
        HStack(spacing: 6) {
            if let dot { Circle().fill(dot).frame(width: 10, height: 10).overlay(Circle().stroke(.white.opacity(0.4))) }
            else { Image(systemName: icon).font(.caption) }
            Text(text).font(.footnote.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glass(Capsule())
    }
}
