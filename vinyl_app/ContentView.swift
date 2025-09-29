import SwiftUI

struct ContentView: View {
    @StateObject private var spotify = SpotifyManager.shared
    @State private var playing = false

    @Namespace private var ns
    @State private var selectedImage: UIImage?
    @State private var showingPlayer = false

    var body: some View {
        ZStack {
            VStack(spacing: 12) {
                // App Remote controls
                HStack {
                    Button("Authorize") { spotify.authorize() }
                    Button(spotify.isConnected ? "Disconnect" : "Connect") {
                        spotify.isConnected ? spotify.disconnect() : spotify.connect()
                    }
                }

                // Web API login or cover-flow
                if SpotifyWebAuth.shared.webAPIToken == nil {
                    Button("Login for Playlists") { SpotifyWebAuth.shared.login() }
                } else {
                    PlaylistCoverFlowView (ns: ns){ playlist, ui in
                        // 1) start playing playlist context
                        if !spotify.isConnected { spotify.connect() }
                        SpotifyManager.shared.play(uri: "spotify:playlist:\(playlist.id)")

                        // 2) animate into player using the image we tapped
                        selectedImage = ui
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                            showingPlayer = true
                        }
                    }
                    .frame(height: 420)
                }

                Spacer(minLength: 0)
            }
            .padding()

            // Player overlay with matched-geometry morph
            if showingPlayer {
                ZStack {
                    // Background blur
                    if let bg = spotify.albumArt ?? selectedImage {
                        Image(uiImage: bg)
                            .resizable()
                            .scaledToFill()
                            .blur(radius: 30)
                            .saturation(0.9)
                            .ignoresSafeArea()
                            .overlay(Color.black.opacity(0.35))
                    }

                    VStack(spacing: 20) {
                        // Matched cover (optional)
                        if let img = spotify.albumArt ?? selectedImage {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 240, height: 240)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .matchedGeometryEffect(id: "cover", in: ns)
                        }

                        // Vinyl deck
                        MDVinylDeckView(
                            cover: spotify.albumArt.map { Image(uiImage: $0) },
                            playing: $playing
                        )
                        .frame(height: 360)

                        // Meta + transport
                        VStack(spacing: 8) {
                            Text(spotify.trackName.isEmpty ? "Not Playing" : spotify.trackName)
                                .font(.headline)
                                .lineLimit(1)

                            Text(spotify.artistName)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)

                            HStack(spacing: 20) {
                                Button("◀︎ Prev") { spotify.previous() }
                                Button(playing ? "Pause" : "Resume") {
                                    playing ? spotify.pause() : spotify.resume()
                                }
                                Button("Next ▶︎") { spotify.next() }
                            }

                            Button("Close") {
                                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                                    showingPlayer = false
                                }
                            }
                        }
                        .padding(.bottom, 10)
                    }
                    .padding()
                }
                .transition(.asymmetric(insertion: .opacity.combined(with: .scale),
                                        removal: .opacity))
            }
        }
        .onChange(of: spotify.isPlaying) { _, now in playing = now }
    }
}
