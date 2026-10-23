import Foundation

/// Fetches an onboarding flow's graph directly from the content CDN.
/// Always degrades to `nil` on any failure -- not deployed to this
/// environment yet (404), a transport failure, or an unparseable body --
/// leaving the fallback decision to the caller.
final class HttpOnboardingClient: @unchecked Sendable {
    private let envSlug: String
    private let contentBaseUrl: String
    private let session: URLSession

    init(envSlug: String, contentBaseUrl: String = "https://content.coproduct.app", session: URLSession = .shared) {
        self.envSlug = envSlug
        self.contentBaseUrl = contentBaseUrl
        self.session = session
    }

    func fetchOnboardingFlow(_ flowId: String) async -> OnboardingFlowGraph? {
        guard let url = URL(string: "\(contentBaseUrl)/onboarding/\(flowId)/\(envSlug)/latest.json") else { return nil }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            return nil
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
        return try? JSONDecoder().decode(OnboardingFlowGraph.self, from: data)
    }
}
