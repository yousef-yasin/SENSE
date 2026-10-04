import SwiftUI

struct VoiceCaptureView: View {
    let onFinish: (String) -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var error: Error?
    @State private var isPreparing = true

    private var speech: SpeechTranscriber { app.speech }

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                ScrollView {
                    Text(transcriptText)
                        .font(.title2.weight(.medium))
                        .foregroundStyle(speech.transcript.isEmpty ? Color.secondary : Color.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                        .accessibilityLabel(speech.transcript.isEmpty ? String(localized: "Waiting for speech") : speech.transcript)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Try saying")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("“Remind me about this when I get to the university.”")
                    Text("“What did I capture yesterday?”")
                    Text("“Have I seen this before?”")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(speech.transcript.isEmpty ? 1 : 0)

                micButton
            }
            .padding(24)
            .navigationTitle(String(localized: "Voice"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) {
                        speech.cancel()
                        dismiss()
                    }
                }
            }
        }
        .task { await begin() }
        .onDisappear { speech.cancel() }
        .errorAlert($error)
        .onChange(of: error == nil) { _, cleared in
            if cleared && !speech.isRecording && speech.transcript.isEmpty && !isPreparing {
                dismiss()
            }
        }
    }

    private var transcriptText: String {
        if !speech.transcript.isEmpty { return speech.transcript }
        if isPreparing { return String(localized: "Getting ready…") }
        return speech.isRecording ? String(localized: "Listening…") : String(localized: "Tap the microphone to speak")
    }

    private var micButton: some View {
        Button {
            if speech.isRecording {
                finish()
            } else {
                Task { await begin() }
            }
        } label: {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.18))
                    .frame(width: 120, height: 120)
                    .scaleEffect(1 + CGFloat(speech.level) * 0.35)
                    .animation(.easeOut(duration: 0.12), value: speech.level)
                Circle()
                    .fill(speech.isRecording ? Color.red : Color.accentColor)
                    .frame(width: 84, height: 84)
                Image(systemName: speech.isRecording ? "stop.fill" : "mic.fill")
                    .font(.title)
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .disabled(isPreparing)
        .accessibilityLabel(speech.isRecording ? String(localized: "Stop and understand") : String(localized: "Start listening"))
    }

    private func begin() async {
        isPreparing = true
        defer { isPreparing = false }
        do {
            try await app.permissions.ensure(.microphone)
            try await app.permissions.ensure(.speech)
            try speech.start(onDeviceOnly: app.settings.onDeviceSpeechOnly)
        } catch {
            self.error = error
        }
    }

    private func finish() {
        Task {
            let text = await speech.finish()
            if let failure = speech.error, text.isEmpty {
                error = failure
                return
            }
            if text.isEmpty {
                dismiss()
            } else {
                onFinish(text)
            }
        }
    }
}
