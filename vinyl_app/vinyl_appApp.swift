import SwiftUI

@main
struct vinyl_appApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    // App Remote (you already use this for playback)
                    SpotifyManager.shared.handleURL(url)
                    // Web API (playlists/auth via PKCE)
                    SpotifyWebAuth.shared.handleRedirectURL(url)
                }
        }
    }
}
