import SwiftUI
import Combine
import UIKit

fileprivate final class ImageCache {
    static let shared = ImageCache()
    private init() {}
    private let cache = NSCache<NSString, UIImage>()
    func image(forKey key: String) -> UIImage? { cache.object(forKey: key as NSString) }
    func setImage(_ image: UIImage, forKey key: String) { cache.setObject(image, forKey: key as NSString) }
}

private enum AlbumArtworkLoader {
    static func loadImage(for source: String) async -> UIImage? {
        if let cached = ImageCache.shared.image(forKey: source) {
            return cached
        }

        if let assetName = assetName(from: source),
           let image = UIImage(named: assetName) {
            ImageCache.shared.setImage(image, forKey: source)
            return image
        }

        guard let url = URL(string: source) else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = UIImage(data: data) else { return nil }
            ImageCache.shared.setImage(image, forKey: source)
            return image
        } catch {
            return nil
        }
    }

    static func assetName(from source: String) -> String? {
        guard source.hasPrefix("asset://") else { return nil }
        return String(source.dropFirst("asset://".count))
    }
}

private extension UIImage {
    func averageColor() -> UIColor? {
        guard let cgImage = self.cgImage else { return nil }
        let contextSize = CGSize(width: 1, height: 1)
        let bitsPerComponent = 8
        let bytesPerRow = 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixelData = [UInt8](repeating: 0, count: 4)
        guard let ctx = CGContext(
            data: &pixelData,
            width: Int(contextSize.width),
            height: Int(contextSize.height),
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
                      
        ctx.draw(cgImage, in: CGRect(origin: .zero, size: contextSize))
        let r = CGFloat(pixelData[0]) / 255.0
        let g = CGFloat(pixelData[1]) / 255.0
        let b = CGFloat(pixelData[2]) / 255.0
        let a = CGFloat(pixelData[3]) / 255.0
        return UIColor(red: r, green: g, blue: b, alpha: a)
    }
}

struct AlbumCoverFlowView: View {
    @ObservedObject var auth = SpotifyWebAuth.shared
    @StateObject var service = AlbumService()
    
    let ns: Namespace.ID
    var onSelect: (SPAlbum, UIImage?) -> Void

    @State private var index = 0
    
    var body: some View {
        let displayAlbums = auth.webAPIToken == nil ? DemoLibrary.albums : service.albums

        GeometryReader { screen in
            let screenW = screen.size.width
            let screenH = screen.size.height
            let isPad = UIDevice.current.userInterfaceIdiom == .pad
            // cellW fills most of the screen — no box padding subtracted
            let cellW = screenW * (isPad ? 0.30 : 0.72)
            let cellH = cellW * 1.20
            let galleryHeight = cellH * 1.65

            ZStack {
                // ── Full-screen ambient background ──────────────────
                BackgroundView(albums: displayAlbums, currentIndex: index)
                    .ignoresSafeArea()

                VStack(spacing: 0) {

                    // ── Floating header — no box ─────────────────────
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(auth.webAPIToken == nil ? "DEMO · COLLECTION" : "VINYL · COLLECTION")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .tracking(3)
                                .foregroundStyle(.white.opacity(0.45))
                            Text(auth.webAPIToken == nil ? "Record Room" : "Record Room")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                            if displayAlbums.count > 0 {
                                Text("\(index + 1) / \(displayAlbums.count)")
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.35))
                            }
                        }
                        Spacer()
                        // Now Playing button
                        Button {
                            NotificationCenter.default.post(name: .goToVinylPage, object: nil)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(.ultraThinMaterial)
                                Circle()
                                    .stroke(Color.white.opacity(0.20), lineWidth: 1)
                                VStack(spacing: 3) {
                                    Image(systemName: "record.circle.fill")
                                        .font(.system(size: 22))
                                        .foregroundStyle(.white)
                                    Text("PLAYER")
                                        .font(.system(size: 7, weight: .bold, design: .rounded))
                                        .tracking(1)
                                        .foregroundStyle(.white.opacity(0.55))
                                }
                            }
                            .frame(width: 56, height: 56)
                        }
                        .accessibilityLabel("Open vinyl player")
                    }
                    .padding(.top, screenH * 0.07)
                    .padding(.horizontal, 32)

                    if let err = service.errorMessage {
                        HStack {
                            Label(err, systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote)
                                .foregroundStyle(.white.opacity(0.75))
                            Spacer()
                        }
                        .padding(.horizontal, 32)
                        .padding(.top, 12)
                    }

                    Spacer()

                    // ── Album carousel — completely untouched ────────
                    AlbumCarousel(
                        albums: displayAlbums,
                        ns: ns,
                        index: $index,
                        tokenPresent: auth.webAPIToken != nil,
                        cellW: cellW,
                        cellH: cellH
                    ) { album, image in onSelect(album, image) }
                    .frame(height: galleryHeight)

                    // ── Shelf ────────────────────────────────────────
                    ShelfSurface()

                    Spacer().frame(height: screenH * 0.06)
                }
                .frame(width: screenW, height: screenH)
            }
        }
        .onReceive(auth.$webAPIToken) { token in
            if let token { service.loadMyAlbums(bearer: token) }
        }
        .onAppear {
            if let token = auth.webAPIToken, service.albums.isEmpty {
                service.loadMyAlbums(bearer: token)
            }
        }
    }
}

// MARK: - Carousel List
private struct AlbumCarousel: View {
    let albums: [SPAlbum]
    let ns: Namespace.ID
    @Binding var index: Int
    let tokenPresent: Bool
    let cellW: CGFloat
    let cellH: CGFloat
    var onSelect: (SPAlbum, UIImage?) -> Void

    var body: some View {
        let isPad = UIDevice.current.userInterfaceIdiom == .pad

        Group {
            if albums.isEmpty {
                if tokenPresent == false {
                    VStack(spacing: 16) {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 60))
                            .foregroundStyle(.white.opacity(0.3))
                        Text("Connect Spotify to browse your saved albums")
                            .font(.headline)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white.opacity(0.7))

                        Text("Browse the built-in demo records now, or sign in to switch this gallery to your real Spotify library.")
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white.opacity(0.55))
                            .frame(maxWidth: 320)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 16) {
                        ProgressView().scaleEffect(1.5)
                        Text("Loading your album collection…")
                            .font(.headline)
                            .foregroundStyle(.white.opacity(0.7))

                        Text("We're fetching the albums saved in your Spotify library.")
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white.opacity(0.55))
                            .frame(maxWidth: 320)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                let spacing: CGFloat = isPad ? 28 : 16
                ScrollViewReader { proxy in
                    GeometryReader { outerGeo in
                        let visibleWidth = outerGeo.size.width
                        let sidePadding = max(0, (visibleWidth - cellW) / 2.0)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: spacing) {
                                ForEach(Array(albums.enumerated()), id: \.element.id) { i, album in
                                    GeometryReader { cardGeo in
                                        let cardMidX = cardGeo.frame(in: .named("AlbumCarouselSpace")).midX
                                        let distance = (cardMidX - (visibleWidth / 2.0))
                                        let progress = distance / (cellW + spacing)
                                        let clamped = max(-1.0, min(1.0, progress))
                                        let absProgress = abs(clamped)
                                        
                                        // Netflix-style: cards face forward, scale + drop creates depth.
                                        // No individual card spin — the shelf slides as a unit.
                                        let scale = CGFloat(1.0 - absProgress * 0.20)
                                        let yOffset  = CGFloat(absProgress * 32.0)   // side cards drop down
                                        let alpha    = Double(1.0 - absProgress * 0.18)

                                        // Very subtle outward fan (≤10°) just to hint at 3D depth.
                                        let tiltSign: Double = clamped >= 0 ? -1.0 : 1.0
                                        let fanDeg = tiltSign * min(10.0, Double(absProgress) * 10.0)

                                        let shadowStrength = 0.08 + (1.0 - absProgress) * 0.35
                                        let shadowRadius   = CGFloat(6.0 + (1.0 - absProgress) * 18.0)

                                        EnhancedAlbumCard(
                                            album: album,
                                            width: cellW,
                                            ns: ns,
                                            isCenter: i == index
                                        ) { image in onSelect(album, image) }
                                        .rotation3DEffect(
                                            .degrees(fanDeg),
                                            axis: (x: 0, y: 1, z: 0),
                                            anchor: .center,
                                            anchorZ: 0,
                                            perspective: 0.6
                                        )
                                        .scaleEffect(scale)
                                        .opacity(alpha)
                                        .offset(y: yOffset)
                                        .shadow(color: .black.opacity(shadowStrength), radius: shadowRadius, x: 0, y: shadowRadius * 0.6)
                                        .zIndex(Double(100 - absProgress * 40.0))
                                        .onTapGesture {
                                            withAnimation(.interpolatingSpring(stiffness: 340, damping: 22)) {
                                                index = i
                                                proxy.scrollTo(i, anchor: .center)
                                            }
                                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                        }
                                    }
                                    .frame(width: cellW)
                                }
                            }
                            .padding(.horizontal, sidePadding)
                            .padding(.top, cellH * 0.05) // Small top headroom
                            .contentShape(Rectangle())
                        }
                        .coordinateSpace(name: "AlbumCarouselSpace")
                        .frame(width: visibleWidth, height: outerGeo.size.height, alignment: .top)
                        .gesture(
                            DragGesture(minimumDistance: 6)
                                .onEnded { value in
                                    let dx = value.translation.width
                                    let predicted = value.predictedEndTranslation.width
                                    let velocity = predicted - dx

                                    if abs(dx) > 40 || abs(velocity) > 120 {
                                        if dx < 0 { index = min(index + 1, albums.count - 1) }
                                        else { index = max(index - 1, 0) }
                                    } else {
                                        var best = index
                                        var bestDist = CGFloat.greatestFiniteMagnitude
                                        for i in 0..<albums.count {
                                            let centerX = sidePadding + CGFloat(i) * (cellW + spacing) + (cellW / 2.0)
                                            let dist = abs(centerX - (visibleWidth/2.0))
                                            if dist < bestDist { bestDist = dist; best = i }
                                        }
                                        index = best
                                    }
                                    withAnimation(.interpolatingSpring(stiffness: 340, damping: 22)) {
                                        proxy.scrollTo(index, anchor: .center)
                                    }
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                }
                        )
                        .onAppear { proxy.scrollTo(index, anchor: .center) }
                    }
                }
            }
        }
    }
}

// MARK: - Enhanced Background (Dynamic Ambient Glow)
private struct BackgroundView: View {
    let albums: [SPAlbum]
    let currentIndex: Int
    @State private var blurredBg: UIImage? = nil
    @State private var paletteColor: UIColor? = nil

    var body: some View {
        let ambient = paletteColor.map { Color(uiColor: $0) } ?? Color(red: 0.42, green: 0.30, blue: 0.18)

        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.02, green: 0.02, blue: 0.04),
                    Color(red: 0.08, green: 0.07, blue: 0.10),
                    ambient.opacity(0.28)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [ambient.opacity(0.34), .clear],
                center: .center,
                startRadius: 30,
                endRadius: 460
            )
            .blur(radius: 10)
            .offset(y: -40)
            .ignoresSafeArea()

            RadialGradient(
                colors: [.white.opacity(0.07), .clear],
                center: .bottomLeading,
                startRadius: 20,
                endRadius: 420
            )
            .blur(radius: 14)
                .ignoresSafeArea()

            if let image = blurredBg {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .saturation(1.15)
                    .blur(radius: 55, opaque: true)
                    .opacity(0.34)
                    .animation(.easeInOut(duration: 0.8), value: currentIndex)
                    .overlay(ambient.opacity(0.18).blendMode(.plusLighter))
            }

            Image("blank-brown-paper-textured-wallpaper")
                .resizable()
                .scaledToFill()
                .grayscale(0.2)
                .blendMode(.softLight)
                .opacity(0.08)
                .ignoresSafeArea()

            RadialGradient(
                colors: [.clear, .black.opacity(0.5), .black.opacity(0.9)],
                center: .center,
                startRadius: 200,
                endRadius: 800
            )
            .ignoresSafeArea()
        }
        .task(id: currentIndex) {
            await loadBackgroundImage()
        }
    }

    private func loadBackgroundImage() async {
        guard albums.indices.contains(currentIndex),
              let source = albums[currentIndex].images?.first?.url
        else {
            blurredBg = nil
            return
        }

        if let image = await AlbumArtworkLoader.loadImage(for: source) {
            let average = image.averageColor()
            await MainActor.run {
                blurredBg = image
                paletteColor = average
            }
        } else {
            await MainActor.run {
                blurredBg = nil
                paletteColor = nil
            }
        }
    }
}

// MARK: - Shelf Surface
private struct ShelfSurface: View {
    var body: some View {
        VStack(spacing: 0) {
            // Top highlight edge — the lit top face of the shelf
            Rectangle()
                .fill(LinearGradient(
                    colors: [.white.opacity(0.30), .white.opacity(0.10)],
                    startPoint: .leading, endPoint: .trailing
                ))
                .frame(height: 1)

            // Shelf face — dark glass/metal surface
            Rectangle()
                .fill(LinearGradient(
                    colors: [
                        Color(white: 0.20),
                        Color(white: 0.13),
                        Color(white: 0.07)
                    ],
                    startPoint: .top, endPoint: .bottom
                ))
                .frame(height: 6)

            // Bottom shadow casting downward from shelf
            Rectangle()
                .fill(LinearGradient(
                    colors: [.black.opacity(0.55), .clear],
                    startPoint: .top, endPoint: .bottom
                ))
                .frame(height: 18)
        }
    }
}

// MARK: - Depth Distortion Modifier
private struct DepthDistortion: ViewModifier {
    let isCenter: Bool
    let cardIndex: Int
    
    func body(content: Content) -> some View {
        content
            .perspective3D(strength: isCenter ? 0.0 : 0.15, direction: cardIndex % 2 == 0 ? .forward : .backward)
    }
}

private extension View {
    func perspective3D(strength: CGFloat, direction: PerspectiveDirection) -> some View {
        self.transformEffect(CGAffineTransform(scaleX: 1.0 - strength * 0.05, y: 1.0))
    }
}

enum PerspectiveDirection {
    case forward, backward
}

// MARK: - Enhanced Album Card
private struct EnhancedAlbumCard: View {
    let album: SPAlbum
    let width: CGFloat
    let ns: Namespace.ID
    let isCenter: Bool
    var onSelect: (UIImage?) -> Void

    @State private var dominantColor: UIColor? = nil
    @State private var ui: UIImage?
    @State private var albumTint: UIColor? = nil

    private var height: CGFloat { width * 1.2 }
    private let radius: CGFloat = 4
    private let spine: CGFloat = 18
    private let thickness: CGFloat = 8

    var body: some View {
        let artistText = (album.artists ?? []).map { $0.name }.joined(separator: ", ")
        let coverWidth = width - spine - thickness + 6
        let caseYaw = 0.0  // Carousel handles all rotation; card stays face-on

        VStack(spacing: 0) {
            ZStack(alignment: .leading) {
                BackPlate(width: coverWidth, height: height - 2, radius: radius, tint: dominantColor)
                    .frame(width: coverWidth, height: height - 2)
                    .offset(x: spine + 7, y: 5)
                    .shadow(color: .black.opacity(0.28), radius: 8, x: 8, y: 7)

                ThicknessEdge(height: height, thickness: thickness, radius: radius, tint: dominantColor)
                    .frame(width: thickness, height: height)
                    .offset(x: width - thickness)
                    .shadow(color: .black.opacity(0.18), radius: 6, x: 4, y: 0)

                FrontCover(album: album, ui: ui, width: coverWidth, height: height, radius: radius, ns: ns, isCenter: isCenter)
                    .frame(width: coverWidth, height: height)
                    .offset(x: spine + 2)
                    .shadow(color: .black.opacity(isCenter ? 0.26 : 0.18), radius: isCenter ? 14 : 8, x: 10, y: 12)

                SpinePanel(width: spine, height: height, radius: radius, tint: albumTint,
                           albumName: album.name,
                           artistName: (album.artists ?? []).map { $0.name }.joined(separator: ", "))
                    .frame(width: spine, height: height)
                    .offset(x: 0)
            }
            .frame(width: width, height: height, alignment: .leading)
            .compositingGroup()
            .rotation3DEffect(
                .degrees(caseYaw),
                axis: (x: 0, y: 1, z: 0),
                anchor: .center,
                perspective: 0.85
            )
            .modifier(DepthDistortion(isCenter: isCenter, cardIndex: 0))
            .shadow(color: .black.opacity(isCenter ? 0.35 : 0.2), radius: isCenter ? 14 : 8, x: isCenter ? 6 : 3, y: isCenter ? 10 : 5)
            .onTapGesture {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onSelect(ui)
            }
            .scaleEffect(isCenter ? 1.0 : 0.98)
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isCenter)

            // 2. ✅ FIXED REFLECTION: Cleanly cropped so it doesn't push the labels down
            ReflectionView(ui: ui, width: width, height: height, spine: spine, radius: radius)
                .frame(height: height * 0.35, alignment: .top) // Strictly limits the layout space
                .clipped()
                .offset(y: 4)

            // 3. LABELS: Snug right under the reflection
            LabelsView(albumName: album.name, artistText: artistText, totalWidth: width)
                .padding(.top, 12)
        }
        .task(id: album.id) {
            if ui == nil,
               let source = album.images?.first?.url,
               let image = await AlbumArtworkLoader.loadImage(for: source) {
                DispatchQueue.global(qos: .userInitiated).async {
                    let c = image.averageColor()
                    DispatchQueue.main.async {
                        self.ui = image
                        self.dominantColor = c
                        self.albumTint = c?.withAlphaComponent(1.0)
                    }
                }
            }
        }
    }
}

// MARK: - Back Plate
private struct BackPlate: View {
    let width: CGFloat
    let height: CGFloat
    let radius: CGFloat
    var tint: UIColor?

    var body: some View {
        let base = tint.map { Color(uiColor: $0).opacity(0.18) } ?? Color(white: 0.16)
        
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Color.black.opacity(0.96))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [base.opacity(0.95), .black.opacity(0.86), .black.opacity(0.98)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color.white.opacity(0.05), lineWidth: 1)
            )
    }
}

// MARK: - Thickness Edge
private struct ThicknessEdge: View {
    let height: CGFloat
    let thickness: CGFloat
    let radius: CGFloat
    var tint: UIColor? = nil

    var body: some View {
        let edgeColor = tint.map { Color(uiColor: $0) } ?? Color(white: 0.12)
        let darkEdge = tint.map { Color(uiColor: $0).opacity(0.7) } ?? Color(white: 0.06)

        RoundedRectangle(cornerRadius: radius * 0.5)
            .fill(
                LinearGradient(
                    colors: [darkEdge, edgeColor.opacity(0.92), edgeColor.opacity(0.65), .black.opacity(0.8)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                Rectangle()
                    .fill(LinearGradient(colors: [.white.opacity(0.22), .clear], startPoint: .leading, endPoint: .trailing))
                    .frame(width: thickness * 0.35)
                    .frame(maxWidth: .infinity, alignment: .leading)
            )
            .overlay(
                Rectangle()
                    .fill(Color.black.opacity(0.22))
                    .frame(width: 1)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            )
    }
}

// MARK: - Front Cover
private struct FrontCover: View {
    let album: SPAlbum
    let ui: UIImage?
    let width: CGFloat
    let height: CGFloat
    let radius: CGFloat
    let ns: Namespace.ID
    let isCenter: Bool
    
    var body: some View {
        ZStack {
            // Base Artwork
            Group {
                if let ui = ui {
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFill()
                        .matchedGeometryEffect(id: album.id, in: ns)
                } else {
                    LinearGradient(colors: [.gray.opacity(0.25), .gray.opacity(0.45)], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
            
            // Texture Overlay
            Image("blank-brown-paper-textured-wallpaper")
                .resizable()
                .grayscale(1.0)
                .contrast(1.2)
                .blendMode(.multiply)
                .opacity(0.35)
            
            // Baked-in Light
            LinearGradient(colors: [.white.opacity(0.25), .clear, .black.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .blendMode(.overlay)
            
            // Ring Wear
            Circle()
                .stroke(LinearGradient(colors: [.white.opacity(0.15), .clear, .black.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5)
                .frame(width: width * 0.85, height: width * 0.85)
                .blur(radius: 2.5)
                .blendMode(.overlay)
            
            // Glossy Sheen
            LinearGradient(
                colors: [.clear, .white.opacity(isCenter ? 0.0 : 0.15), .white.opacity(isCenter ? 0.15 : 0.0), .clear],
                startPoint: isCenter ? .topLeading : .leading,
                endPoint: isCenter ? .bottomTrailing : .trailing
            )
            .blendMode(.screen)
            
            // Spine-crease shadow: the fold casts a shadow on the left of the cover face
            HStack {
                LinearGradient(
                    colors: [.black.opacity(0.40), .black.opacity(0.12), .clear],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(width: 20)
                Spacer()
            }

            // Right hollow edge shadow
            HStack {
                Spacer()
                LinearGradient(colors: [.clear, .black.opacity(0.4)], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 8)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(LinearGradient(colors: [.white.opacity(0.5), .clear, .black.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
        )
    }
}

// MARK: - Spine Panel
private struct SpinePanel: View {
    let width: CGFloat
    let height: CGFloat
    let radius: CGFloat
    var tint: UIColor? = nil
    let albumName: String
    let artistName: String

    var body: some View {
        let base = tint.map { Color(uiColor: $0) } ?? Color(white: 0.15)

        ZStack {
            // Base: dark left edge fading to album color
            RoundedRectangle(cornerRadius: radius * 0.5, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.black.opacity(0.96), base.opacity(0.80)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

            // Subtle top-to-bottom sheen so it reads as a lit surface
            RoundedRectangle(cornerRadius: radius * 0.5, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.14), .clear, .black.opacity(0.25)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            // Outer left highlight line — the outermost lit edge of the case
            Rectangle()
                .fill(LinearGradient(colors: [.white.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing))
                .frame(width: 2)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Spine text: album name + artist stacked, rotated to run bottom→top
            VStack(spacing: 3) {
                Text(albumName.uppercased())
                    .font(.system(size: 7.5, weight: .bold, design: .rounded))
                    .tracking(1.4)
                    .lineLimit(1)
                    .foregroundStyle(.white)

                if !artistName.isEmpty {
                    Text(artistName)
                        .font(.system(size: 6.5, weight: .medium, design: .rounded))
                        .tracking(0.8)
                        .lineLimit(1)
                        .foregroundStyle(.white.opacity(0.70))
                }
            }
            .frame(width: height * 0.88)   // long axis before rotation
            .fixedSize(horizontal: true, vertical: false)
            .rotationEffect(.degrees(-90))
            .frame(width: width, height: height)
            .shadow(color: .black.opacity(0.6), radius: 2, x: 0, y: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: radius * 0.5, style: .continuous))
    }
}



// MARK: - Reflection View
private struct ReflectionView: View {
    let ui: UIImage?
    let width: CGFloat
    let height: CGFloat
    let spine: CGFloat
    let radius: CGFloat
    
    var body: some View {
        let coverWidth = width - spine
        
        // Use a clear proxy frame so it layouts perfectly downwards
        Color.clear
            .overlay(
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: radius)
                        .fill(Color.black.opacity(0.3))
                        .frame(width: spine, height: height)
                        .offset(x: 0)

                    Group {
                        if let ui = ui {
                            Image(uiImage: ui).resizable().scaledToFill()
                        } else {
                            Color.white.opacity(0.03)
                        }
                    }
                    .frame(width: coverWidth, height: height)
                    .clipShape(RoundedRectangle(cornerRadius: radius))
                    .offset(x: spine)
                }
                .frame(width: width, height: height, alignment: .leading)
                .scaleEffect(x: 1, y: -1) // Flips it upside down
                .rotation3DEffect(.degrees(15), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
                .opacity(0.12)
                .blur(radius: 3.5)
                .mask(LinearGradient(colors: [.black.opacity(0.7), .clear], startPoint: .top, endPoint: .center))
                
                , alignment: .top
            )
    }
}

// MARK: - Labels View
private struct LabelsView: View {
    let albumName: String
    let artistText: String
    let totalWidth: CGFloat
    
    var body: some View {
        VStack(spacing: 1) {
            Text(albumName)
                .font(.system(.headline, design: .rounded))
                .fontWeight(.semibold)
                .lineLimit(1)
                .foregroundStyle(.white)
            
            if !artistText.isEmpty {
                Text(artistText)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
            }
        }
        .frame(width: totalWidth)
    }
}














