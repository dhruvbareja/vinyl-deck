import Foundation
import UIKit
import SpotifyiOS
import Combine

final class SpotifyManager: NSObject, ObservableObject {
    static let shared = SpotifyManager()

    // TODO: keep your real client id and redirect
    private let clientID = "3dcb9fbd5f01403f8e64faa975c312e4"
    private let redirectURI = URL(string: "vinylplayer://callback")!

    @Published var isConnected = false
    @Published var isPlaying   = false
    @Published var trackName   = ""
    @Published var artistName  = ""
    @Published var albumArt: UIImage?

    private lazy var configuration: SPTConfiguration = {
        let c = SPTConfiguration(clientID: clientID, redirectURL: redirectURI)
        return c
    }()

    private lazy var appRemote: SPTAppRemote = {
        let r = SPTAppRemote(configuration: configuration, logLevel: .debug)
        r.delegate = self
        return r
    }()

    private(set) var accessToken: String?
    private var lastDesiredPlayState: Bool?

    // MARK: - Auth
    func authorize() {
        // Triggers App Remote auth and ensures Spotify wakes up
        appRemote.authorizeAndPlayURI("") { installed in
            if !installed {
                if let url = URL(string: "https://apps.apple.com/app/spotify-music-and-podcasts/id324684580") {
                    UIApplication.shared.open(url)
                }
            }
        }
    }

    func handleURL(_ url: URL) {
        let params = appRemote.authorizationParameters(from: url)
        if let token = params?[SPTAppRemoteAccessTokenKey] {
            accessToken = token
            appRemote.connectionParameters.accessToken = token
            connect()
        } else if let err = params?[SPTAppRemoteErrorDescriptionKey] {
            print("Auth error:", err)
        }
    }

    func connect() {
        guard let token = accessToken else {
            print("❌ No access token. Run authorize() first.")
            return
        }
        appRemote.connectionParameters.accessToken = token
        appRemote.connect()
    }

    func disconnect() {
        if appRemote.isConnected { appRemote.disconnect() }
        isConnected = false
    }

    // MARK: - Playback helpers
    func setPlaying(_ shouldPlay: Bool) {
        // Prevent flooding the remote with the same request
        if lastDesiredPlayState == shouldPlay { return }
        lastDesiredPlayState = shouldPlay

        guard appRemote.isConnected else {
            print("Not connected; ignoring setPlaying(\(shouldPlay))")
            lastDesiredPlayState = nil
            return
        }

        if shouldPlay {
            appRemote.playerAPI?.resume { [weak self] _, error in
                if let error = error { print("resume error:", error) }
                self?.lastDesiredPlayState = nil
            }
        } else {
            appRemote.playerAPI?.pause { [weak self] _, error in
                if let error = error { print("pause error:", error) }
                self?.lastDesiredPlayState = nil
            }
        }
    }

    func play(uri: String) {
        guard appRemote.isConnected else { print("Not connected"); return }
        appRemote.playerAPI?.play(uri, callback: nil)
    }
    func pause()  { guard appRemote.isConnected else { return }; appRemote.playerAPI?.pause(nil) }
    func resume() { guard appRemote.isConnected else { return }; appRemote.playerAPI?.resume(nil) }
    // SpotifyManager.swift
    func next() { appRemote.playerAPI?.skip(toNext: nil) }
    func previous() { appRemote.playerAPI?.skip(toPrevious: nil) }
    func seek(to ms: Int) { appRemote.playerAPI?.seek(toPosition: ms, callback: nil) } // optional

    // MARK: - State/image
    private func handleState(_ state: SPTAppRemotePlayerState) {
        DispatchQueue.main.async {
            self.isPlaying  = !state.isPaused
            self.trackName  = state.track.name
            self.artistName = state.track.artist.name
        }
        fetchAlbumImage(for: state.track)
    }

    private func fetchAlbumImage(for track: SPTAppRemoteTrack) {
        appRemote.imageAPI?.fetchImage(
            forItem: track,
            with: CGSize(width: 600, height: 600),
            callback: { [weak self] image, error in
                if let error = error {
                    print("Image fetch error:", error)
                    return
                }
                guard let img = image as? UIImage else { return }
                DispatchQueue.main.async {
                    self?.albumArt = img
                }
            }
        )
    }
}

// MARK: - Delegates
extension SpotifyManager: SPTAppRemoteDelegate {
    func appRemoteDidEstablishConnection(_ appRemote: SPTAppRemote) {
        isConnected = true
        print("✅ Connected to Spotify")

        // Delegate + subscribe + get initial snapshot
        appRemote.playerAPI?.delegate = self
        appRemote.playerAPI?.subscribe(toPlayerState: { [weak self] _, error in
            if let error = error { print("Subscribe error:", error) }
            self?.appRemote.playerAPI?.getPlayerState { result, error in
                if let state = result as? SPTAppRemotePlayerState {
                    self?.handleState(state)
                } else if let error = error {
                    print("getPlayerState error:", error)
                }
            }
        })
    }

    func appRemote(_ appRemote: SPTAppRemote, didFailConnectionAttemptWithError error: Error?) {
        isConnected = false
        print("Connect failed:", error?.localizedDescription ?? "")
        // If session is stale, a fresh authorize often fixes it
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.authorize() }
    }

    func appRemote(_ appRemote: SPTAppRemote, didDisconnectWithError error: Error?) {
        isConnected = false
        print("Disconnected:", error?.localizedDescription ?? "")
    }
}

extension SpotifyManager: SPTAppRemotePlayerStateDelegate {
    func playerStateDidChange(_ playerState: SPTAppRemotePlayerState) {
        print("🎵 Now playing:", playerState.track.name)
        handleState(playerState)
    }
}

extension SpotifyManager {
    var hasToken: Bool { accessToken != nil }
}
