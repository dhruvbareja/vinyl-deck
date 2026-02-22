//
//  SpotifyWebAuth.swift
//  vinyl_app
//

import Foundation
import SpotifyiOS
import UIKit
import Combine

final class SpotifyWebAuth: NSObject, ObservableObject, SPTSessionManagerDelegate {
    static let shared = SpotifyWebAuth()

    @Published private(set) var webAPIToken: String?

    private let clientID = "3dcb9fbd5f01403f8e64faa975c312e4"
    private let redirectURI = URL(string: "vinylplayer://callback")!

    private lazy var configuration: SPTConfiguration = {
        let c = SPTConfiguration(clientID: clientID, redirectURL: redirectURI)
        return c
    }()

    private lazy var sessionManager: SPTSessionManager = {
        SPTSessionManager(configuration: configuration, delegate: self)
    }()

    private let scopes: SPTScope = [
        .appRemoteControl,
        .userModifyPlaybackState,
        .userReadPlaybackState,
        .userReadCurrentlyPlaying,
        .userLibraryRead,
        .playlistReadPrivate
    ]

    // MARK: - Public API
    func login() {
        sessionManager.initiateSession(with: scopes, options: .default, campaign: nil)
    }

    func handleRedirectURL(_ url: URL) {
        sessionManager.application(UIApplication.shared, open: url, options: [:])
    }

    // MARK: - SPTSessionManagerDelegate
    func sessionManager(manager: SPTSessionManager, didFailWith error: Error) {
        print("❌ Web API auth failed:", error.localizedDescription)
    }
    func sessionManager(manager: SPTSessionManager, didInitiate session: SPTSession) {
        print("✅ Web API token received. Scope:", session.scope)
        DispatchQueue.main.async {
            self.webAPIToken = session.accessToken
            // This is where your code is calling:
            SpotifyManager.shared.connect()  // now exists
        }
    }

    func sessionManager(manager: SPTSessionManager, didRenew session: SPTSession) {
        print("🔄 Web API token renewed. Scope:", session.scope)
        DispatchQueue.main.async {
            self.webAPIToken = session.accessToken
        }
    }
}
