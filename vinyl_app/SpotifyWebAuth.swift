import Foundation
import SpotifyiOS
import UIKit
import Combine

final class SpotifyWebAuth: NSObject, ObservableObject, SPTSessionManagerDelegate {
    static let shared = SpotifyWebAuth()

    @Published private(set) var webAPIToken: String?

    // 👉 Make sure this is your real client ID and your registered redirect URI.
    private let clientID = "3dcb9fbd5f01403f8e64faa975c312e4"
    private let redirectURI = URL(string: "vinylplayer://callback")!

    private lazy var configuration: SPTConfiguration = {
        let c = SPTConfiguration(clientID: clientID, redirectURL: redirectURI)
        // If you add swap/refresh endpoints later:
        // c.tokenSwapURL = URL(string: "https://yourserver.com/swap")
        // c.tokenRefreshURL = URL(string: "https://yourserver.com/refresh")
        return c
    }()

    private lazy var sessionManager: SPTSessionManager = {
        SPTSessionManager(configuration: configuration, delegate: self)
    }()

    // Scopes you need for playlists (add more if needed)
    private let scopes: SPTScope = [.playlistReadPrivate, .userReadEmail]

    func login() {
        // New signature: with:options:campaign:
        // Pass nil for campaign unless you use Spotify attribution.
        sessionManager.initiateSession(with: scopes, options: .default, campaign: nil)
    }

    // Forward from App.onOpenURL
    func handleRedirectURL(_ url: URL) {
        sessionManager.application(UIApplication.shared, open: url, options: [:])
    }

    // MARK: - SPTSessionManagerDelegate
    func sessionManager(manager: SPTSessionManager, didFailWith error: Error) {
        print("Web API auth failed:", error.localizedDescription)
    }

    func sessionManager(manager: SPTSessionManager, didInitiate session: SPTSession) {
        DispatchQueue.main.async {
            self.webAPIToken = session.accessToken
            print("✅ Web API token received")
        }
    }

    func sessionManager(manager: SPTSessionManager, didRenew session: SPTSession) {
        DispatchQueue.main.async {
            self.webAPIToken = session.accessToken
            print("🔄 Web API token renewed")
        }
    }
}
