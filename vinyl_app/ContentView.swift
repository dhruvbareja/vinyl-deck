import SwiftUI

struct ContentView: View {
    @StateObject private var spotify = SpotifyManager.shared
    @ObservedObject private var auth = SpotifyWebAuth.shared

    private enum Screen { case login,coverflow, player }
    @State private var screen: Screen = .login
    

    @State private var playing = false
    @Namespace private var ns
    @State private var selectedImage: UIImage?
    
    
    // LoginLandingView.swift (new file or add to ContentView.swift)
    

    struct LoginLandingView: View {
        @ObservedObject var auth = SpotifyWebAuth.shared
        var onConnect: () -> Void

        @State private var isLoggingIn = false

        var body: some View {
            ZStack {
                LinearGradient(colors: [Color.black, Color(.darkGray)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                VStack(spacing: 24) {
                    Text("Welcome to Vinyl")
                        .font(.largeTitle).bold()
                        .foregroundStyle(.white)

                    Text("Browse your album collection in a beautiful 3D coverflow. Connect your Spotify account to load albums.")
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 36)

                    Button(action: {
                        guard !isLoggingIn else { return }
                        isLoggingIn = true
                        SpotifyWebAuth.shared.login()
                    }) {
                        HStack {
                            if isLoggingIn {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            }
                            Text(isLoggingIn ? "Signing in…" : "Login with Spotify")
                                .font(.headline)
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 26)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.blue))
                        .foregroundStyle(.white)
                    }
                    .disabled(isLoggingIn)

                    Button(action: {
                        onConnect()
                    }) {
                        Text("Continue without login")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .opacity(0.86)
                    .padding(.top, 8)
                }
                .padding()
                .frame(maxWidth: 720)
            }
            // When the token changes, auto-advance to albums if token present.
            .onReceive(auth.$webAPIToken) { token in
                if token != nil {
                    // small dispatch to let UI settle (optional)
                    DispatchQueue.main.async {
                        onConnect()
                    }
                }
            }
        }
    }

    var body: some View {
            ZStack {
                switch screen {
                case .login:
                    LoginLandingView(auth: auth) {
                        // called after successful login or "continue without login"
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                            screen = .coverflow
                        }
                    }
                    .transition(.move(edge: .trailing).combined(with: .opacity))

                case .coverflow:
                    CoverflowScreen(ns: ns) { album, ui in
                        SpotifyManager.shared.playAlbum(album.id)
                        selectedImage = ui
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                            screen = .player
                        }
                    }
                    .transition(.move(edge: .trailing).combined(with: .opacity))

                case .player:
                    PlayerScreen(
                        selectedImage: selectedImage,
                        playing: $playing,
                        onClose: {
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                                screen = .coverflow
                            }
                        }
                    )
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            .onChange(of: spotify.isPlaying) { _, now in playing = now }
        // ✅ Jump to Vinyl Player when notification received
        .onReceive(NotificationCenter.default.publisher(for: .goToVinylPage)) { _ in
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                screen = .player   // Switch TO vinyl player page
            }
        }
    }
}

private struct CoverflowScreen: View {
    let ns: Namespace.ID
    var onSelect: (SPAlbum, UIImage?) -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Spacer()
                Text("Pick an album")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            HStack(spacing: 12) {
                Button("Authorize Spotify") {
                    SpotifyManager.shared.authorize()
                }
                .buttonStyle(.bordered)

                Button("Connect") {
                    SpotifyManager.shared.connect()
                }
                .buttonStyle(.borderedProminent)

                Button("Disconnect") {
                    SpotifyManager.shared.disconnect()
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 4)

            if SpotifyWebAuth.shared.webAPIToken == nil {
                Button("Login for Albums (Web API)") {
                    SpotifyWebAuth.shared.login()
                }
                .buttonStyle(.borderedProminent)
            }

            GeometryReader { geo in
                AlbumCoverFlowView(ns: ns, onSelect: onSelect)
                    .frame(height: max(360, geo.size.height * 0.75))
                    .frame(maxWidth: .infinity,
                           maxHeight: .infinity,
                           alignment: .center)
            }
        }
        .padding()
        .background(
            LinearGradient(colors: [.black, .gray.opacity(0.7)],
                           startPoint: .top,
                           endPoint: .bottom)
            .ignoresSafeArea()
        )
    }
}
private struct PlayerScreen: View {
    let selectedImage: UIImage?
    @Binding var playing: Bool
    var onClose: () -> Void

    @StateObject private var spotify = SpotifyManager.shared
    
    // ✅ State for the slide-in/slide-out animation
    @State private var dockedIntoSleeve: Bool = false

    var body: some View {
        ZStack {
            // Background: blurred album art
            if let bg = spotify.albumArt ?? selectedImage {
                Image(uiImage: bg)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 40)
                    .saturation(0.95)
                    .ignoresSafeArea()
                    .overlay(Color.black.opacity(0.30))
            } else {
                LinearGradient(colors: [.black, .gray.opacity(0.7)],
                               startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            }

            VStack(spacing: 20) {
                GeometryReader { geo in
                    let W = geo.size.width
                    let H = geo.size.height
                    let isLandscape = W > H
                    let isPad = UIDevice.current.userInterfaceIdiom == .pad

                    // Target sizes
                    let coverWidth  = isLandscape ? W * (isPad ? 0.48 : 0.50) : min(W, H) * 0.70
                    let discWidth   = isLandscape ? W * (isPad ? 0.52 : 0.52) : min(W, H) * 0.72

                    // base overlap: ~14% of the disc sits over the cover
                    let overlapX = -(discWidth * 0.14)
                    let baseOverlap = discWidth * 0.22
                    let dockExtra   = discWidth * 0.30 // smaller overlap so record is more visible
                    let seamFudge: CGFloat = 0           // no extra left push           // ⬅️ small negative value removes visible gap
                    Group {
                        if isLandscape {
                            // NOTE: tiny negative spacing removes any invisible gutter
                            HStack(alignment: .center, spacing: -4) {
                                // LEFT — Cover
                                CoverCard(image: spotify.albumArt ?? selectedImage)
                                    .frame(width: coverWidth)
                                    .frame(maxHeight: .infinity, alignment: .center)
                                    // ensure cover appears above the disc when docked, otherwise below
                                    .zIndex(dockedIntoSleeve ? 3 : 2)
                                    .offset(x: dockedIntoSleeve ? discWidth * 0.26 : 0)
                                    .animation(.spring(response: 0.50, dampingFraction: 0.80, blendDuration: 0.1), value: dockedIntoSleeve)
                                    .onTapGesture {
                                        // stronger, nicer spring + short haptic click
                                        withAnimation(.interpolatingSpring(stiffness: 150, damping: 9)) {
                                            dockedIntoSleeve.toggle()
                                        }
                                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                    }

                                // RIGHT: deck (disc slides only, arm stays)
                                // RIGHT — Deck (disc + arm)
                                // RIGHT — Deck: pass only recordSlide (tonearm does not move with disc)
                                    MDVinylDeckView(
                                        cover: (spotify.albumArt ?? selectedImage).map { Image(uiImage: $0) },
                                        playing: $playing,
                                        showCoverCard: false,
                                        recordSlide: -(baseOverlap) + (dockedIntoSleeve ? -discWidth * 0.26 : 0) - seamFudge
                                    )
                                    .frame(width: discWidth, height: discWidth)
                                    .scaleEffect(dockedIntoSleeve ? 0.985 : 1.0)
                                    .shadow(color: .black.opacity(dockedIntoSleeve ? 0.15 : 0.30),
                                            radius: dockedIntoSleeve ? 10 : 20,
                                            x: 10, y: dockedIntoSleeve ? 6 : 12)
                                    .padding(.trailing, dockedIntoSleeve ? 32 : 12)
                                    .zIndex(dockedIntoSleeve ? 1 : 2) // ensure layering is consistent
                                
                                            .zIndex(1)
                                
                                        }
                                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        } else {
                               // Portrait — keep your current logic, but add the seamFudge the same way:
                               VStack(spacing: 0) {
                                   CoverCard(image: spotify.albumArt ?? selectedImage)
                                       .frame(width: min(W, H) * 0.78)
                                       .zIndex(2)
                                       .onTapGesture {
                                           // stronger, nicer spring + short haptic click
                                           withAnimation(.interpolatingSpring(stiffness: 150, damping: 9)) {
                                               dockedIntoSleeve.toggle()
                                           }
                                           UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                       }
                                MDVinylDeckView(
                                    cover: (spotify.albumArt ?? selectedImage).map { Image(uiImage: $0) },
                                    playing: $playing,
                                    showCoverCard: false,
                                    recordSlide: -(baseOverlap * 0.88) + (dockedIntoSleeve ? -discWidth * 0.23 : 0)
                                )
                                .frame(width: min(W, H) * 0.86, height: min(W, H) * 0.86)
                                .offset(y: -min(W, H) * 0.06)
                                .scaleEffect(dockedIntoSleeve ? 0.985 : 1.0)
                                .shadow(color: .black.opacity(dockedIntoSleeve ? 0.15 : 0.30),
                                        radius: dockedIntoSleeve ? 10 : 20,
                                        x: 0, y: dockedIntoSleeve ? 6 : 12)
                                .zIndex(1)
                            }
                        }
                    }
                }
                .frame(height: UIScreen.main.bounds.height * 0.70)

                // Title + controls
                VStack(spacing: 4) {
                                    Text(spotify.trackName.isEmpty ? "Not Playing" : spotify.trackName)
                                        .font(.system(size: 18, weight: .semibold))
                                        .lineLimit(1)
                                        .foregroundStyle(.white)
                                    
                                    Text(spotify.artistName)
                                        .font(.system(size: 14, weight: .regular))
                                        .foregroundStyle(.white.opacity(0.7))
                                        .lineLimit(1)
                    HStack(spacing: 16) {
                                            // Prev button
                                            Button(action: { spotify.previous() }) {
                                                Image(systemName: "backward.fill")
                                                    .font(.system(size: 14, weight: .semibold))
                                                    .frame(width: 40, height: 40)
                                                    .background(Color.white.opacity(0.1))
                                                    .clipShape(Circle())
                                            }
                                            
                                            // Play/Pause button (prominent)
                                            Button(action: {
                                                playing ? spotify.pause() : spotify.resume()
                                            }) {
                                                Image(systemName: playing ? "pause.fill" : "play.fill")
                                                    .font(.system(size: 18, weight: .semibold))
                                                    .frame(width: 56, height: 56)
                                                    .background(
                                                        LinearGradient(
                                                            colors: [Color.white.opacity(0.15), Color.white.opacity(0.08)],
                                                            startPoint: .topLeading,
                                                            endPoint: .bottomTrailing
                                                        )
                                                    )
                                                    .clipShape(Circle())
                                                    .overlay(
                                                        Circle().stroke(Color.white.opacity(0.2), lineWidth: 1.2)
                                                    )
                                            }
                                            
                                            // Next button
                                            Button(action: { spotify.next() }) {
                                                Image(systemName: "forward.fill")
                                                    .font(.system(size: 14, weight: .semibold))
                                                    .frame(width: 40, height: 40)
                                                    .background(Color.white.opacity(0.1))
                                                    .clipShape(Circle())
                                            }
                                        }
                                        .foregroundStyle(.white)
                }

                Button(action: { onClose() }) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "chevron.down")
                                            .font(.system(size: 13, weight: .semibold))
                                        Text("Close")
                                            .font(.system(size: 14, weight: .semibold))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44)
                                    .background(Color.white.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                                    )
                                }
                                .foregroundStyle(.white)
                                .padding(.top, 12)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
    }
}

/// A simple 3D cover card with soft shadow & depth, like MD-Vinyl’s left pane.
private struct CoverCard: View {
    let image: UIImage?

    var body: some View {
        let img = image.map { Image(uiImage: $0) }

        ZStack {
            if let img {
                img
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    
                    // gentle 3D-ish lift
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    )
                    .rotation3DEffect(.degrees(6), axis: (x: 0, y: -1, z: 0), perspective: 0.8)
            } else {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.gray.opacity(0.25))
                    .overlay(Text("No Cover").foregroundColor(.secondary))
                    .frame(height: 320)
            }
        }
    }
}
extension Notification.Name {
    static let goToVinylPage = Notification.Name("goToVinylPage")
}
