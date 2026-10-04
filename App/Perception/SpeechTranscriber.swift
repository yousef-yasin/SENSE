import AVFoundation
import Observation
import Speech

@MainActor
@Observable
final class SpeechTranscriber {
    private(set) var transcript = ""
    private(set) var isRecording = false
    private(set) var level: Float = 0
    private(set) var error: Error?

    private let engine = AVAudioEngine()
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?

    func start(onDeviceOnly: Bool, locale: Locale = .current) throws {
        guard !isRecording else { return }
        transcript = ""
        error = nil

        guard let recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.isAvailable else {
            throw SenseError.speechUnavailable
        }
        if onDeviceOnly && !recognizer.supportsOnDeviceRecognition {
            throw SenseError.onDeviceSpeechUnsupported
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = onDeviceOnly
        request.addsPunctuation = true
        self.request = request

        Self.installTap(on: engine.inputNode, feeding: request) { [weak self] level in
            Task { @MainActor in self?.level = level }
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            self.request = nil
            throw error
        }

        task = Self.recognize(with: recognizer, request: request) { [weak self] text, isFinal, failure in
            Task { @MainActor in self?.handle(text: text, isFinal: isFinal, failure: failure) }
        }
        isRecording = true
    }

    func stop() {
        guard isRecording else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        isRecording = false
        level = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func cancel() {
        stop()
        task?.cancel()
        task = nil
        request = nil
    }

    func finish() async -> String {
        stop()
        var attempts = 0
        while task != nil, task?.state != .completed, attempts < 15 {
            try? await Task.sleep(for: .milliseconds(100))
            attempts += 1
        }
        task = nil
        request = nil
        return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func handle(text: String?, isFinal: Bool, failure: Error?) {
        if let text {
            transcript = text
        }
        if let failure, transcript.isEmpty {
            error = failure
        }
        if isFinal || failure != nil {
            task = nil
            if isRecording { stop() }
        }
    }

    private nonisolated static func installTap(
        on node: AVAudioInputNode,
        feeding request: SFSpeechAudioBufferRecognitionRequest,
        level: @escaping @Sendable (Float) -> Void
    ) {
        let format = node.outputFormat(forBus: 0)
        node.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
            guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
            var sum: Float = 0
            for index in 0..<Int(buffer.frameLength) {
                sum += channel[index] * channel[index]
            }
            let rms = (sum / Float(buffer.frameLength)).squareRoot()
            level(min(1, rms * 12))
        }
    }

    private nonisolated static func recognize(
        with recognizer: SFSpeechRecognizer,
        request: SFSpeechAudioBufferRecognitionRequest,
        handler: @escaping @Sendable (String?, Bool, Error?) -> Void
    ) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            handler(result?.bestTranscription.formattedString, result?.isFinal ?? false, error)
        }
    }
}
