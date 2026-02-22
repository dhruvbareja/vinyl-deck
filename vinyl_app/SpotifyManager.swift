import Foundation
import UIKit
import SpotifyiOS
import Combine

final class SpotifyManager: NSObject, ObservableObject {
    static let shared = SpotifyManager()

    private let clientID = "3dcb9fbd5f01403f8e64faa975c312e4"
    private let redirectURI = URL(string: "vinylplayer://callback")!

    @Published var isConnected = false
    @Published var isPlaying   = false
    @Published var trackName   = ""
    @Published var artistName  = ""
    @Published var albumArt: UIImage?

    private lazy var configuration: SPTConfiguration = {
        SPTConfiguration(clientID: clientID, redirectURL: redirectURI)
    }()

    private lazy var appRemote: SPTAppRemote = {
        let r = SPTAppRemote(configuration: configuration, logLevel: .debug)
        r.delegate = self
        return r
    }()

    // Throttle waking Spotify app
    private var lastSpotifyWake: Date?
    private let spotifyWakeCooldown: TimeInterval = 8.0

    private var reconnectWorkItem: DispatchWorkItem?
    private(set) var accessToken: String?
    private var pendingActionAfterConnect: (() -> Void)?

    // MARK: - Init / lifecycle
    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.reconnectIfPossible() }
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    // MARK: - Public helpers
    func reconnectIfPossible() {
        guard !appRemote.isConnected, let token = accessToken else { return }
        appRemote.connectionParameters.accessToken = token
        appRemote.connect()
    }

    private func scheduleSilentReconnect(delay: TimeInterval = 0.6) {
        reconnectWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard let token = self.accessToken ?? SpotifyWebAuth.shared.webAPIToken else { return }
            self.appRemote.connectionParameters.accessToken = token
            self.appRemote.connect()
            print("🔁 Silent reconnect attempt…")
        }
        reconnectWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }
    private var heartbeatTimer: Timer?

    func startHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 25, repeats: true) { [weak self] _ in
            guard let self = self, self.appRemote.isConnected else { return }
            self.appRemote.playerAPI?.getPlayerState { _, _ in }
        }
    }

    func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    // MARK: - Authorization / App Remote
    func authorize() {
        if let token = SpotifyWebAuth.shared.webAPIToken {
            accessToken = token
            appRemote.connectionParameters.accessToken = token
            appRemote.connect() // silent
            print("🔑 Authorized → silent connect")
        } else {
            SpotifyWebAuth.shared.login() // app-switch once for OAuth
            print("🌐 Starting OAuth login")
        }
    }

    /// Called from App.onOpenURL after WebAuth redirects back
    func handleURL(_ url: URL) {
        SpotifyWebAuth.shared.handleRedirectURL(url)

        if let token = SpotifyWebAuth.shared.webAPIToken {
            accessToken = token
            appRemote.connectionParameters.accessToken = token
            appRemote.connect() // ⛔️ no bouncing to Spotify here
            print("✅ Got web token; connecting App Remote silently")
        } else {
            print("❌ Redirect handled, but no token present")
        }
    }

    /// Wake Spotify app (used only before starting *playback* contexts)
    private func openSpotifyIfNeeded(completion: @escaping () -> Void) {
        if let last = lastSpotifyWake, Date().timeIntervalSince(last) < spotifyWakeCooldown {
            DispatchQueue.main.async { completion() }
            return
        }
        lastSpotifyWake = Date()

        let spotifyURL = URL(string: "spotify://")!
        if UIApplication.shared.canOpenURL(spotifyURL) {
            UIApplication.shared.open(spotifyURL, options: [:]) { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: completion)
            }
        } else if let store = URL(string: "https://apps.apple.com/app/spotify-music-and-podcasts/id324684580") {
            UIApplication.shared.open(store)
        }
    }

    // MARK: - Minimal Web API helpers
    private func webAPI(_ method: String, _ path: String, body: [String:Any]? = nil, completion: ((Int?, Error?) -> Void)? = nil) {
        guard let token = SpotifyWebAuth.shared.webAPIToken else {
            completion?(nil, NSError(domain: "Spotify", code: -1, userInfo: [NSLocalizedDescriptionKey: "No Web API token"]))
            return
        }
        var req = URLRequest(url: URL(string: "https://api.spotify.com\(path)")!)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        URLSession.shared.dataTask(with: req) { _, res, err in
            completion?((res as? HTTPURLResponse)?.statusCode, err)
        }.resume()
    }

    private func webAPIRequest(
        method: String,
        path: String,
        body: [String: Any]? = nil,
        bearer: String,
        completion: ((HTTPURLResponse?, Data?, Error?) -> Void)? = nil
    ) {
        var req = URLRequest(url: URL(string: "https://api.spotify.com\(path)")!)
        req.httpMethod = method
        req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        URLSession.shared.dataTask(with: req) { data, res, err in
            completion?(res as? HTTPURLResponse, data, err)
        }.resume()
    }

    // MARK: - Start contexts with Web API (playlists/albums)
    func playPlaylist(_ playlistID: String) {
        guard SpotifyWebAuth.shared.webAPIToken != nil else { print("❌ No Web API token"); return }
        // Wake Spotify once to spin up AppRemote server, then start context
        openSpotifyIfNeeded { [weak self] in
            self?.webAPI("PUT", "/v1/me/player/play", body: ["context_uri": "spotify:playlist:\(playlistID)"])
            self?.scheduleSilentReconnect()
        }
    }

    func playAlbum(_ albumID: String) {
        guard SpotifyWebAuth.shared.webAPIToken != nil else { print("❌ No Web API token"); return }
        openSpotifyIfNeeded { [weak self] in
            self?.webAPI("PUT", "/v1/me/player/play", body: ["context_uri": "spotify:album:\(albumID)"])
            self?.scheduleSilentReconnect()
        }
    }

    private func transferPlaybackToAnyDevice(bearer token: String, completion: @escaping (Bool) -> Void) {
        webAPIRequest(method: "GET", path: "/v1/me/player/devices", bearer: token) { [weak self] _, data, _ in
            guard
                let data,
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let devices = json["devices"] as? [[String: Any]],
                let first = devices.first,
                let id = first["id"] as? String
            else { completion(false); return }

            let body: [String: Any] = ["device_ids": [id], "play": true]
            self?.webAPIRequest(method: "PUT", path: "/v1/me/player", body: body, bearer: token) { http, _, _ in
                completion(http?.statusCode == 204)
            }
        }
    }

    // MARK: - Manual connect/disconnect (buttons)
    func connect() {
        guard let token = accessToken ?? SpotifyWebAuth.shared.webAPIToken else {
            print("❌ connect(): No token. Tap Authorize first.")
            return
        }
        accessToken = token
        appRemote.connectionParameters.accessToken = token
        appRemote.connect()
        print("🔌 connect(): Silent connect requested")
    }

    func disconnect() {
        reconnectWorkItem?.cancel()
        if appRemote.isConnected { appRemote.disconnect() }
        isConnected = false
        print("🔌 disconnect(): App Remote disconnected")
    }

    // MARK: - Playback controls (with fallback)
    func playTrackURI(_ trackURI: String) {
        ensureAppRemoteReady { [weak self] in
            self?.appRemote.playerAPI?.play(trackURI, callback: { _, error in
                if let error = error { print("playTrackURI error:", error) }
            })
        }
    }

    func pause() {
        if appRemote.isConnected {
            appRemote.playerAPI?.pause { [weak self] _, e in
                if let e = e { print("pause(AppRemote) error:", e); self?.pauseViaWebAPI() }
            }
        } else {
            pauseViaWebAPI()
            scheduleSilentReconnect()
        }
    }

    func resume() {
        if appRemote.isConnected {
            appRemote.playerAPI?.resume { [weak self] _, e in
                if let e = e { print("resume(AppRemote) error:", e); self?.resumeViaWebAPI() }
            }
        } else {
            resumeViaWebAPI()
            scheduleSilentReconnect()
        }
    }

    func next() {
        if appRemote.isConnected {
            appRemote.playerAPI?.skip(toNext: { [weak self] _, e in if let e = e { print("next(AppRemote) error:", e); self?.webAPI("POST", "/v1/me/player/next") } })
        } else {
            webAPI("POST", "/v1/me/player/next")
            scheduleSilentReconnect()
        }
    }

    func previous() {
        if appRemote.isConnected {
            appRemote.playerAPI?.skip(toPrevious: { [weak self] _, e in if let e = e { print("previous(AppRemote) error:", e); self?.webAPI("POST", "/v1/me/player/previous") } })
        } else {
            webAPI("POST", "/v1/me/player/previous")
            scheduleSilentReconnect()
        }
    }

    func seek(to ms: Int) {
        if appRemote.isConnected {
            appRemote.playerAPI?.seek(toPosition: ms) { [weak self] _, e in if let e = e { print("seek(AppRemote) error:", e); self?.webAPI("PUT", "/v1/me/player/seek?position_ms=\(ms)") } }
        } else {
            webAPI("PUT", "/v1/me/player/seek?position_ms=\(ms)")
            scheduleSilentReconnect()
        }
    }

    private func pauseViaWebAPI() {
        guard let token = SpotifyWebAuth.shared.webAPIToken else { return }
        webAPIRequest(method: "PUT", path: "/v1/me/player/pause", bearer: token)
    }

    private func resumeViaWebAPI() {
        guard let token = SpotifyWebAuth.shared.webAPIToken else { return }
        webAPIRequest(method: "PUT", path: "/v1/me/player/play", bearer: token)
    }

    /// Try a silent connect and run `action` once connected. No app-switch here.
    private func ensureAppRemoteReady(then action: @escaping () -> Void) {
        if appRemote.isConnected { action(); return }
        guard let token = accessToken ?? SpotifyWebAuth.shared.webAPIToken else {
            print("⚠️ No token — authorize first"); return
        }
        accessToken = token
        appRemote.connectionParameters.accessToken = token
        pendingActionAfterConnect = action
        appRemote.connect() // silent
    }

    private func runPendingActionIfAny() {
        let act = pendingActionAfterConnect
        pendingActionAfterConnect = nil
        act?()
    }

    // Debug helper
    private func logCanOpenSpotify() {
        let ok = UIApplication.shared.canOpenURL(URL(string: "spotify://")!)
        print("🔎 canOpenURL(spotify://) =", ok)
    }
}

// MARK: - SPTAppRemoteDelegate
extension SpotifyManager: SPTAppRemoteDelegate {
    func appRemoteDidEstablishConnection(_ appRemote: SPTAppRemote) {
        isConnected = true
        print("✅ Connected to Spotify")
        subscribeToPlayerState()
        // Fetch current state once after connect
        appRemote.playerAPI?.getPlayerState { [weak self] result, error in
            if let state = result as? SPTAppRemotePlayerState { self?.handleState(state) }
            if let error = error { print("getPlayerState error:", error) }
        }
        runPendingActionIfAny()
    }

    func appRemote(_ appRemote: SPTAppRemote, didDisconnectWithError error: Error?) {
        isConnected = false
        print("🔌 Disconnected:", error?.localizedDescription ?? "")
        // Only silent reconnect; never app-switch here
        scheduleSilentReconnect(delay: 0.8)
    }

    func appRemote(_ appRemote: SPTAppRemote, didFailConnectionAttemptWithError error: Error?) {
        isConnected = false
        print("⚠️ Connect failed:", error?.localizedDescription ?? "")
        // If token expired, WebAuth delegate should renew; then we reconnect silently
        scheduleSilentReconnect(delay: 1.2)
    }
}

// MARK: - Player state
extension SpotifyManager: SPTAppRemotePlayerStateDelegate {
    func playerStateDidChange(_ playerState: SPTAppRemotePlayerState) {
        print("🎵 Now playing:", playerState.track.name)
        handleState(playerState)
    }

    private func subscribeToPlayerState() {
        appRemote.playerAPI?.delegate = self
        appRemote.playerAPI?.subscribe(toPlayerState: { [weak self] _, error in
            if let error = error {
                print("Subscribe error:", error)
            } else {
                print("🔔 Subscribed to player state updates")
            }
        })
    }

    private func handleState(_ state: SPTAppRemotePlayerState) {
        DispatchQueue.main.async {
            self.isPlaying  = !state.isPaused
            self.trackName  = state.track.name
            self.artistName = state.track.artist.name
        }
        fetchAlbumImage(for: state.track)
    }

    private func fetchAlbumImage(for track: SPTAppRemoteTrack) {
        appRemote.imageAPI?.fetchImage(forItem: track, with: CGSize(width: 600, height: 600)) { [weak self] image, error in
            if let error = error { print("Image fetch error:", error); return }
            guard let img = image as? UIImage else { return }
            DispatchQueue.main.async { self?.albumArt = img }
        }
    }
}
