import Foundation
import Observation
import SenseCore

enum ProviderMode: String, CaseIterable, Identifiable {
    case onDevice
    case openAICompatible

    var id: String { rawValue }
}

@MainActor
@Observable
final class AppSettings {
    private enum Key {
        static let onboarding = "settings.onboardingCompleted"
        static let attachLocation = "settings.attachLocation"
        static let onDeviceSpeech = "settings.onDeviceSpeechOnly"
        static let providerMode = "settings.providerMode"
        static let providerBaseURL = "settings.providerBaseURL"
        static let providerModel = "settings.providerModel"
        static let apiKeyAccount = "provider.apiKey"
    }

    private let defaults: UserDefaults

    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Key.onboarding) }
    }

    var attachLocation: Bool {
        didSet { defaults.set(attachLocation, forKey: Key.attachLocation) }
    }

    var onDeviceSpeechOnly: Bool {
        didSet { defaults.set(onDeviceSpeechOnly, forKey: Key.onDeviceSpeech) }
    }

    var providerMode: ProviderMode {
        didSet { defaults.set(providerMode.rawValue, forKey: Key.providerMode) }
    }

    var providerBaseURL: String {
        didSet { defaults.set(providerBaseURL, forKey: Key.providerBaseURL) }
    }

    var providerModel: String {
        didSet { defaults.set(providerModel, forKey: Key.providerModel) }
    }

    private(set) var hasAPIKey: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hasCompletedOnboarding = defaults.bool(forKey: Key.onboarding)
        attachLocation = defaults.bool(forKey: Key.attachLocation)
        onDeviceSpeechOnly = defaults.object(forKey: Key.onDeviceSpeech) as? Bool ?? true
        providerMode = ProviderMode(rawValue: defaults.string(forKey: Key.providerMode) ?? "") ?? .onDevice
        providerBaseURL = defaults.string(forKey: Key.providerBaseURL) ?? ""
        providerModel = defaults.string(forKey: Key.providerModel) ?? ""
        hasAPIKey = Keychain.read(account: Key.apiKeyAccount) != nil
    }

    func setAPIKey(_ key: String?) throws {
        let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines)
        try Keychain.write(trimmed?.isEmpty == false ? trimmed : nil, account: Key.apiKeyAccount)
        hasAPIKey = Keychain.read(account: Key.apiKeyAccount) != nil
    }

    var remoteConfiguration: RemoteProviderConfiguration? {
        guard providerMode == .openAICompatible else { return nil }
        let model = providerModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty,
              let url = URL(string: providerBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              url.host != nil else { return nil }
        return RemoteProviderConfiguration(baseURL: url, model: model, apiKey: Keychain.read(account: Key.apiKeyAccount))
    }

    func resetProvider() throws {
        providerMode = .onDevice
        providerBaseURL = ""
        providerModel = ""
        try setAPIKey(nil)
    }
}
