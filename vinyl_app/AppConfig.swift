import Foundation

enum AppConfig {
    private enum Key {
        static let spotifyClientID = "SPOTIFY_CLIENT_ID"
        static let spotifyRedirectURI = "SPOTIFY_REDIRECT_URI"
        static let geminiAPIKey = "GEMINI_API_KEY"
    }

    static let spotifyClientID: String = requiredString(for: Key.spotifyClientID)
    static let spotifyRedirectURI: URL = requiredURL(for: Key.spotifyRedirectURI)
    static let geminiAPIKey: String? = optionalString(for: Key.geminiAPIKey)

    private static func requiredString(for key: String) -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            fatalError("Missing required Info.plist value for \(key)")
        }
        return value
    }

    private static func requiredURL(for key: String) -> URL {
        guard let url = URL(string: requiredString(for: key)) else {
            fatalError("Invalid URL configured for \(key)")
        }
        return url
    }

    private static func optionalString(for key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
