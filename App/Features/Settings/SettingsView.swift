import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @State private var memoryCount = 0
    @State private var confirmErase = false
    @State private var error: Error?

    var body: some View {
        @Bindable var settings = app.settings

        List {
            Section {
                Toggle(isOn: Binding(
                    get: { settings.attachLocation },
                    set: { enable in toggleLocationTagging(enable) }
                )) {
                    Label(String(localized: "Tag memories with location"), systemImage: "mappin.and.ellipse")
                }
                Toggle(isOn: $settings.onDeviceSpeechOnly) {
                    Label(String(localized: "Transcribe on this iPhone only"), systemImage: "waveform")
                }
            } header: {
                Text("Privacy")
            } footer: {
                Text("When location tagging is on, SENSE records where a memory was captured so you can ask things like “What did I capture at the university?”. On-device transcription keeps your voice on this iPhone; turning it off may send audio to Apple for recognition.")
            }

            Section {
                ForEach(PermissionKind.allCases) { kind in
                    PermissionRow(kind: kind)
                }
            } header: {
                Text("Permissions")
            } footer: {
                Text("SENSE only asks for access when you use a feature that needs it.")
            }

            Section(String(localized: "Intelligence")) {
                NavigationLink {
                    ProviderSettingsView()
                } label: {
                    LabeledContent {
                        Text(settings.providerMode == .onDevice ? String(localized: "On this iPhone") : String(localized: "Custom provider"))
                    } label: {
                        Label(String(localized: "Understanding"), systemImage: "sparkles")
                    }
                }
            }

            Section(String(localized: "Places")) {
                NavigationLink {
                    PlacesView()
                } label: {
                    Label(String(localized: "Saved Places"), systemImage: "mappin.circle")
                }
            }

            Section {
                LabeledContent(String(localized: "Memories on this iPhone"), value: memoryCount.formatted())
                Button(role: .destructive) {
                    confirmErase = true
                } label: {
                    Label(String(localized: "Erase All SENSE Data"), systemImage: "trash")
                }
            } header: {
                Text("Data")
            } footer: {
                Text("Memories, photos, reminders and places are stored only on this iPhone and protected by iOS data protection. Photos are encrypted whenever your iPhone is locked.")
            }

            Section(String(localized: "About")) {
                LabeledContent(String(localized: "Version"), value: Bundle.main.versionDescription)
            }
        }
        .navigationTitle(String(localized: "Settings"))
        .task { memoryCount = app.memories.count() }
        .confirmationDialog(String(localized: "Erase all SENSE data?"), isPresented: $confirmErase, titleVisibility: .visible) {
            Button(String(localized: "Erase Everything"), role: .destructive) {
                do {
                    try app.eraseAllData()
                    memoryCount = app.memories.count()
                } catch {
                    self.error = error
                }
            }
        } message: {
            Text("All memories, photos, reminders and saved places will be permanently deleted from this iPhone.")
        }
        .errorAlert($error)
    }

    private func toggleLocationTagging(_ enable: Bool) {
        guard enable else {
            app.settings.attachLocation = false
            return
        }
        Task {
            do {
                try await app.permissions.ensure(.location)
                app.settings.attachLocation = true
            } catch {
                app.settings.attachLocation = false
                self.error = error
            }
        }
    }
}

private struct PermissionRow: View {
    let kind: PermissionKind
    @Environment(AppModel.self) private var app

    var body: some View {
        let state = app.permissions.state(of: kind)
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: kind.symbol)
                .foregroundStyle(.tint)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.title)
                Text(kind.purpose)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            switch state {
            case .notDetermined:
                Button(String(localized: "Allow")) {
                    Task { await app.permissions.request(kind) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            case .denied:
                Button(String(localized: "Settings")) { app.permissions.openSystemSettings() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            case .granted, .restricted:
                Text(state.label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

extension Bundle {
    var versionDescription: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }
}
