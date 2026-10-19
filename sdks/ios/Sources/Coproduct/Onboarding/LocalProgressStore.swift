import Foundation

/// Persisted onboarding progress for one flow.
public struct FlowProgress: Codable, Equatable, Sendable {
    public let version: Int
    public let screenId: String
    public let answers: [String: [String]]

    public init(version: Int, screenId: String, answers: [String: [String]]) {
        self.version = version
        self.screenId = screenId
        self.answers = answers
    }
}

/// Persists onboarding progress to local device storage, keyed by flowId, so
/// an app crash or restart resumes on the last known screen rather than
/// restarting from `startScreenId`. Not Keychain: this is non-sensitive
/// UI-resume state, the same tier RN's AsyncStorage and Flutter's
/// SharedPreferences occupy.
final class LocalProgressStore: @unchecked Sendable {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func key(_ flowId: String) -> String {
        "coproduct_onboarding_progress_\(flowId)"
    }

    func save(flowId: String, version: Int, screenId: String, answers: [String: [String]]) {
        let progress = FlowProgress(version: version, screenId: screenId, answers: answers)
        guard let data = try? JSONEncoder().encode(progress) else { return }
        defaults.set(data, forKey: key(flowId))
    }

    func load(flowId: String) -> FlowProgress? {
        guard let data = defaults.data(forKey: key(flowId)) else { return nil }
        return try? JSONDecoder().decode(FlowProgress.self, from: data)
    }

    func clear(flowId: String) {
        defaults.removeObject(forKey: key(flowId))
    }
}
