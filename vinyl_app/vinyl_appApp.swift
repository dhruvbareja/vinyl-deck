import SwiftUI

@main
struct VinylApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                // 👇 attach onOpenURL to ContentView (root view)
                .onOpenURL { url in
                    print("🔗 onOpenURL →", url.absoluteString)
                    SpotifyManager.shared.handleURL(url)
                }
        }
    }
}
