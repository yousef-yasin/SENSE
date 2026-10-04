import SenseCore
import SwiftUI

struct ProviderSettingsView: View {
    @Environment(AppModel.self) private var app
    @State private var apiKey = ""
    @State private var testResult: String?
    @State private var isTesting = false
    @State private var error: Error?

    var body: some View {
        @Bindable var settings = app.settings

        Form {
            Section {
                Picker(String(localized: "Understanding"), selection: $settings.providerMode) {
                    Text("On this iPhone").tag(ProviderMode.onDevice)
                    Text("OpenAI-compatible server").tag(ProviderMode.openAICompatible)
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } footer: {
                Text("On-device understanding is free, works offline and never sends your captures anywhere. A server can write richer titles and summaries; dates, reminders and search always stay on this iPhone.")
            }

            if settings.providerMode == .openAICompatible {
                Section {
                    TextField(String(localized: "Base URL"), text: $settings.providerBaseURL, prompt: Text(verbatim: "http://192.168.1.20:11434/v1"))
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField(String(localized: "Model"), text: $settings.providerModel, prompt: Text(verbatim: "llama3.2"))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Server")
                } footer: {
                    Text("Works with Ollama, LM Studio, llama.cpp or any service that offers an OpenAI-compatible chat completions endpoint.")
                }

                Section {
                    SecureField(settings.hasAPIKey ? String(localized: "Saved in Keychain") : String(localized: "Optional"), text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button(String(localized: "Save Key")) { saveKey() }
                        .disabled(apiKey.isEmpty)
                    if settings.hasAPIKey {
                        Button(String(localized: "Remove Key"), role: .destructive) { removeKey() }
                    }
                } header: {
                    Text("API Key")
                } footer: {
                    Text("Stored in the iOS Keychain on this device only. Local servers usually don't need one.")
                }

                Section {
                    Button {
                        test()
                    } label: {
                        HStack {
                            Text("Test Connection")
                            if isTesting {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(settings.remoteConfiguration == nil || isTesting)
                    if let testResult {
                        Text(testResult)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("When a server is configured, the text SENSE recognizes in each capture is sent to it. Photos and audio are never sent. If the server can't be reached, SENSE falls back to on-device understanding.")
                }
            }
        }
        .navigationTitle(String(localized: "Understanding"))
        .navigationBarTitleDisplayMode(.inline)
        .errorAlert($error)
    }

    private func saveKey() {
        do {
            try app.settings.setAPIKey(apiKey)
            apiKey = ""
        } catch {
            self.error = error
        }
    }

    private func removeKey() {
        do {
            try app.settings.setAPIKey(nil)
        } catch {
            self.error = error
        }
    }

    private func test() {
        guard let configuration = app.settings.remoteConfiguration else { return }
        isTesting = true
        testResult = nil
        Task {
            defer { isTesting = false }
            let provider = OpenAICompatibleIntelligence(configuration: configuration)
            let sample = CaptureInput(source: .text, text: "Library notice: books borrowed this month are due back by Friday at 6 PM.")
            do {
                let result = try await provider.understand(sample)
                testResult = String(localized: "Connected. The server summarized a sample as: “\(result.title)”")
            } catch let failure as ProviderError {
                switch failure {
                case .httpStatus(let code):
                    testResult = String(localized: "The server responded with status \(code).")
                case .unreadableContent, .invalidResponse:
                    testResult = String(localized: "The server responded, but not in the expected format. Check the model name.")
                }
            } catch {
                testResult = error.localizedDescription
            }
        }
    }
}
