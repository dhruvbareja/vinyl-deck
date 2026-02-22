//
//  VinylNowPlayingView.swift
//  vinyl_app
//
//  Created by Dhruv bareja on 27/10/25.
//

import SwiftUI

struct VinylNowPlayingView: View {
    @Binding var album: SPAlbum?
    @Binding var cover: UIImage?
    let ns: Namespace.ID
    var onClose: () -> Void

    var body: some View {
        ZStack {
            // Reuse your gradient/blurred bg if you want
            LinearGradient(colors: [.black, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar
                HStack {
                    Button(action: onClose) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(.ultraThinMaterial))
                    }
                    Spacer()
                    Text("Now Playing")
                        .foregroundStyle(.white.opacity(0.85))
                        .font(.headline)
                    Spacer()
                    // placeholder to balance layout
                    Color.clear.frame(width: 40, height: 40)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                Spacer(minLength: 0)

                // Your vinyl/turntable/SceneKit view here.
                // If you want a matchedGeometryEffect for the cover art, use the same `ns` and `album.id`.
                if let album {
                    VinylSceneView(
                        album: album,
                        cover: cover // use in your SCNMaterial
                    )
                    .frame(maxWidth: 700, maxHeight: 700) // tune for iPad/iPhone
                    .padding(.horizontal, 24)
                    .transition(.asymmetric(insertion: .scale.combined(with: .opacity),
                                            removal: .opacity))
                } else {
                    Text("Pick an album")
                        .foregroundStyle(.white.opacity(0.6))
                        .padding()
                }

                Spacer(minLength: 0)

                // Minimal transport area (hook into Spotify/Apple Music controls)
                TransportBar()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
            }
        }
    }
}

// Stub views – replace with your real ones.
private struct VinylSceneView: View {
    let album: SPAlbum
    let cover: UIImage?
    var body: some View {
        // Embed your SceneKit/Metal/SwiftUI 3D here
        // e.g., AlbumCase3DView(album: album, cover: cover)
        RoundedRectangle(cornerRadius: 24).fill(.black.opacity(0.2))
            .overlay(
                Group {
                    if let cover {
                        Image(uiImage: cover).resizable().scaledToFit().padding(24)
                    } else {
                        Image(systemName: "opticaldisc").font(.system(size: 80)).foregroundStyle(.white.opacity(0.2))
                    }
                }
            )
    }
}

private struct TransportBar: View {
    var onPrev: () -> Void = {}
    var onPlayPause: () -> Void = {}
    var onNext: () -> Void = {}
    var isPlaying: Bool = false

    var body: some View {
        HStack(spacing: 18) {
            Button(action: onPrev) {
                Image(systemName: "backward.fill")
            }
            Button(action: onPlayPause) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
            }
            Button(action: onNext) {
                Image(systemName: "forward.fill")
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .font(.system(size: 20, weight: .semibold))
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
    }
}
