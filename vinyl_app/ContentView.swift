import SwiftUI
import Combine
import UIKit

struct ContentView: View {
    @StateObject private var spotify = SpotifyManager.shared
    @ObservedObject private var auth = SpotifyWebAuth.shared

    private enum Screen { case login,coverflow, player }
    @State private var screen: Screen = .login
    

    @State private var playing = false
    @Namespace private var ns
    @State private var selectedImage: UIImage?
    @State private var selectedAlbum: SPAlbum?
    
    
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
                        selectedAlbum = album
                        if SpotifyWebAuth.shared.webAPIToken != nil {
                            SpotifyManager.shared.playAlbum(album.id)
                        }
                        selectedImage = ui
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                            screen = .player
                        }
                    }
                    .transition(.move(edge: .trailing).combined(with: .opacity))

                case .player:
                    PlayerScreen(
                        selectedAlbum: selectedAlbum,
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
        AlbumCoverFlowView(ns: ns, onSelect: onSelect)
    }
}

// MARK: - Player Screen ROUTER
private struct PlayerScreen: View {
    let selectedAlbum: SPAlbum?
    let selectedImage: UIImage?
    @Binding var playing: Bool
    var onClose: () -> Void

    var body: some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            PadPlayerScreen(selectedAlbum: selectedAlbum, selectedImage: selectedImage, playing: $playing, onClose: onClose)
        } else {
            PhonePlayerScreen(selectedAlbum: selectedAlbum, selectedImage: selectedImage, playing: $playing, onClose: onClose)
        }
    }
}

// MARK: - iPHONE Dedicated Player (Vertical Unboxing Animation)
private struct PhonePlayerScreen: View {
    let selectedAlbum: SPAlbum?
    let selectedImage: UIImage?
    @Binding var playing: Bool
    var onClose: () -> Void

    @StateObject private var spotify = SpotifyManager.shared
    @State private var dockedIntoSleeve: Bool = true // Starts docked so animation triggers!

    var body: some View {
        ZStack {
            // Background: blurred album art
            if let bg = spotify.albumArt ?? selectedImage {
                Image(uiImage: bg)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 50)
                    .saturation(0.9)
                    .ignoresSafeArea()
                    .overlay(Color.black.opacity(0.40))
            } else {
                Color(red: 0.1, green: 0.1, blue: 0.12).ignoresSafeArea()
            }

            VStack(spacing: 0) {
                GeometryReader { geo in
                    let W = geo.size.width
                    let coverWidth = W * 0.65
                    let discWidth = W * 0.70
                    
                    // Zooms out slightly when unboxing so nothing hits the edges
                    let assemblyScale = dockedIntoSleeve ? 1.0 : 0.85

                    ZStack(alignment: .center) {
                        // THE DISC (Slides DOWN on Phone)
                        MDVinylDeckView(
                            cover: (spotify.albumArt ?? selectedImage).map { Image(uiImage: $0) },
                            playing: $playing,
                            showCoverCard: false,
                            recordSlide: 0 // Physics handled by Y offset below
                        )
                        .frame(width: discWidth, height: discWidth)
                        .scaleEffect(dockedIntoSleeve ? 0.98 : 1.0)
                        .shadow(color: .black.opacity(dockedIntoSleeve ? 0.15 : 0.40), radius: dockedIntoSleeve ? 10 : 25, x: 0, y: dockedIntoSleeve ? 6 : 15)
                        .offset(y: dockedIntoSleeve ? 0 : discWidth * 0.65) // SLIDES DOWN
                        .zIndex(1)

                        // THE SLEEVE (Slides UP on Phone)
                        CoverCard(image: spotify.albumArt ?? selectedImage)
                            .frame(width: coverWidth)
                            .zIndex(2)
                            .offset(y: dockedIntoSleeve ? 0 : -discWidth * 0.45) // SLIDES UP
                            .onTapGesture {
                                withAnimation(.interpolatingSpring(stiffness: 150, damping: 12)) {
                                    dockedIntoSleeve.toggle()
                                }
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            }
                    }
                    .scaleEffect(assemblyScale)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
                .frame(height: UIScreen.main.bounds.height * 0.55)
                .zIndex(2)

                Spacer()

                // Titles & Controls
                VStack(spacing: 8) {
                    Text(playerTitle)
                        .font(.system(size: 18, weight: .bold))
                        .lineLimit(1)
                        .foregroundStyle(.white)
                    
                    Text(playerArtist)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                    
                    HStack(spacing: 24) {
                        Button(action: { spotify.previous() }) {
                            Image(systemName: "backward.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(width: 48, height: 48)
                                .background(Color.white.opacity(0.1))
                                .clipShape(Circle())
                        }
                        
                        Button(action: { playing ? spotify.pause() : spotify.resume() }) {
                            Image(systemName: playing ? "pause.fill" : "play.fill")
                                .font(.system(size: 20, weight: .bold))
                                .frame(width: 64, height: 64)
                                .background(LinearGradient(colors: [Color.white.opacity(0.2), Color.white.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1))
                        }
                        
                        Button(action: { spotify.next() }) {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(width: 48, height: 48)
                                .background(Color.white.opacity(0.1))
                                .clipShape(Circle())
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.top, 16)
                }
                .padding(.horizontal, 24)
                .zIndex(3)

                Spacer()

                Button(action: { onClose() }) {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.down").font(.system(size: 13, weight: .semibold))
                        Text("Close").font(.system(size: 14, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.12), lineWidth: 1))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.interpolatingSpring(stiffness: 120, damping: 14)) { dockedIntoSleeve = false }
            }
        }
    }

    private var playerTitle: String {
        if spotify.trackName.isEmpty == false { return spotify.trackName }
        return selectedAlbum?.name ?? "Not Playing"
    }

    private var playerArtist: String {
        if spotify.artistName.isEmpty == false { return spotify.artistName }
        let fallback = selectedAlbum?.artists?.map(\.name).joined(separator: ", ")
        return fallback ?? ""
    }
}


// MARK: - iPAD Dedicated Player (Your Unaltered Original Logic)
private struct PadPlayerScreen: View {
    let selectedAlbum: SPAlbum?
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
                                    Text(playerTitle)
                                        .font(.system(size: 18, weight: .semibold))
                                        .lineLimit(1)
                                        .foregroundStyle(.white)
                                    
                                    Text(playerArtist)
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

    private var playerTitle: String {
        if spotify.trackName.isEmpty == false { return spotify.trackName }
        return selectedAlbum?.name ?? "Not Playing"
    }

    private var playerArtist: String {
        if spotify.artistName.isEmpty == false { return spotify.artistName }
        let fallback = selectedAlbum?.artists?.map(\.name).joined(separator: ", ")
        return fallback ?? ""
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
