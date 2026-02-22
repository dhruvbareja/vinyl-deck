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

private extension UIImage {
    /// Fast average color sample by drawing to 1x1 context.
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
    @State private var isAutoPlaying = false
    @State private var showStats = false
    var body: some View {
        ZStack {
            // Background
            BackgroundView(albums: service.albums, currentIndex: index)

            VStack(spacing: 0) {
                // Header
                HeaderView(
                    isAutoPlaying: $isAutoPlaying,
                    showStats: $showStats,
                    albumCount: service.albums.count,
                    currentIndex: index
                )
                .padding(.top, 8)
                .zIndex(10)

                // Error / spacer
                if let err = service.errorMessage {
                    Text(err)
                        .font(.footnote)
                        .foregroundStyle(.red.opacity(0.8))
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(.ultraThinMaterial))
                        .padding(.top, 8)
                } else {
                    Spacer(minLength: 0).frame(height: 8)
                }

                // Gallery
                GeometryReader { geo in
                    AlbumCarousel(
                        albums: service.albums,
                        ns: ns,
                        index: $index,
                        tokenPresent: auth.webAPIToken != nil,
                        containerSize: geo.size
                    ) { album, image in
                        onSelect(album, image)
                    }
                    .zIndex(0)
                }

                // Dots
                if service.albums.count > 1 {
                    NavigationDots(count: service.albums.count, current: index)
                        .padding(.bottom, 16)
                        .zIndex(10)
                }

                // Stats
                if showStats && !service.albums.isEmpty {
                    StatsView(albums: service.albums, currentIndex: index)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
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
        .onChange(of: isAutoPlaying) { _, newValue in
            if newValue { startAutoPlay() }
        }
        

    }
    
    private func startAutoPlay() {
        guard isAutoPlaying, !service.albums.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            guard isAutoPlaying, !service.albums.isEmpty else { return }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                index = (index + 1) % service.albums.count
            }
            startAutoPlay()
        }
    }
}



private struct AlbumCarousel: View {
    let albums: [SPAlbum]
    let ns: Namespace.ID
    @Binding var index: Int
    let tokenPresent: Bool
    let containerSize: CGSize
    var onSelect: (SPAlbum, UIImage?) -> Void

    var body: some View {
        // Sizing (same math you already had)
        let W = containerSize.width
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        // Sizing for album cards — reduce slightly
        let cellW = W * (isPad ? 0.32 : 0.40)
        let cellH = cellW * 1.20
        // Keep gallery inside rectangle — reduce overshoot
        let headroom = cellH * 0.10
        let labelsH: CGFloat = 50
        let perspectiveBulge = cellH * 0.20
        let extraVisualHeadroom: CGFloat = cellH * 0.18   // ≈ 45–55 pts on iPad
        let galleryHeight =
            cellH +
            labelsH +
            headroom * 2 +
            perspectiveBulge +
            extraVisualHeadroom
        let verticalNudge: CGFloat = 18
        let centerYOffset = (containerSize.height - galleryHeight) / 2.0
        let sidePadding = max(32, (W - cellW) / 2.0)

        Group {
            if albums.isEmpty {
                Group {
                    if tokenPresent == false {
                        VStack(spacing: 16) {
                            Image(systemName: "music.note.list")
                                .font(.system(size: 60))
                                .foregroundStyle(.white.opacity(0.3))
                            Text("Connect Spotify to explore your vinyl collection")
                                .font(.headline)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        .padding()
                    } else {
                        VStack(spacing: 16) {
                            ProgressView().scaleEffect(1.5)
                            Text("Loading your collection…")
                                .font(.headline)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // use named coordinate space so cards can measure their center relative to the container
                let spacing: CGFloat = isPad ? 50 : 28
                ScrollViewReader { proxy in
                    GeometryReader { outerGeo in
                        let visibleWidth = outerGeo.size.width
                        let visibleHeight = outerGeo.size.height

                        // device flags
                        let isPad = UIDevice.current.userInterfaceIdiom == .pad

                        // tuning constants
                        let cardHeightBuffer: CGFloat = isPad ? 24 : 18

                        // sizes
                        let spacing: CGFloat = isPad ? 50 : 28
                        let cellW = W * (isPad ? 0.32 : 0.40)
                        let cellH = cellW * 1.20
                        let labelsH: CGFloat = 50
                        let headroom = cellH * 0.10
                        let perspectiveBulge = cellH * 0.20
                        // Extra space for card reflection + labels so album art isn't clipped
                        let reflectionAndLabelsHeight = cellH * 0.55 + 60
                        let galleryHeight = cellH + labelsH + headroom * 2 + perspectiveBulge + reflectionAndLabelsHeight

                        // Cap gallery height so it fits in the black box; center the carousel vertically
                        let galleryContentHeight = min(visibleHeight - 24, galleryHeight + 48)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: spacing) {
                                ForEach(Array(albums.enumerated()), id: \.element.id) { i, album in
                                    GeometryReader { cardGeo in
                                        let cardMidX = cardGeo.frame(in: .named("AlbumCarouselSpace")).midX
                                        let distance = (cardMidX - (visibleWidth / 2.0))
                                        let progress = distance / (cellW + spacing)
                                        let clamped = max(-1.0, min(1.0, progress))

                                        // transforms
                                        let tiltDegrees = Double(-clamped * 10.0)
                                        let scale = CGFloat(1.0 - abs(clamped) * 0.12)
                                        let alpha = Double(1.0 - abs(clamped) * 0.18)
                                        let yOffset = CGFloat(-abs(clamped) * 8.0)

                                        VStack(spacing: 10) {
                                            EnhancedAlbumCard(
                                                album: album,
                                                width: cellW,
                                                ns: ns,
                                                isCenter: i == index
                                            ) { image in onSelect(album, image) }
                                            .frame(width: cellW, height: cellH * 1.45)
                                            .rotation3DEffect(.degrees(tiltDegrees), axis: (x: 0, y: 1, z: 0), perspective: 0.8)
                                            .scaleEffect(scale)
                                            .opacity(alpha)
                                            .offset(y: yOffset)
                                            .shadow(color: .black.opacity(i == index ? 0.32 : 0.08), radius: i == index ? 20 : 6, x: 0, y: 10)
                                            .onTapGesture {
                                                withAnimation(.interpolatingSpring(stiffness: 340, damping: 22)) {
                                                    index = i
                                                    proxy.scrollTo(i, anchor: .center)
                                                }
                                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                            }

                                            // label under the card
                                            Text(album.name)
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundStyle(.white)
                                                .lineLimit(1)
                                                .frame(maxWidth: cellW)
                                        }
                                        .frame(width: cardGeo.size.width, height: cardGeo.size.height)
                                    } // card GeometryReader
                                    .frame(width: cellW, height: max( (galleryHeight - labelsH) - cardHeightBuffer, cellH * 1.55 + 70 ))
                                }
                            } // HStack
                            .padding(.horizontal, sidePadding)
                            .padding(.top, headroom * 0.6)
                            .padding(.bottom, headroom + perspectiveBulge + 32)
                            .contentShape(Rectangle())
                        } // ScrollView
                        .coordinateSpace(name: "AlbumCarouselSpace")
                        .frame(width: visibleWidth, height: galleryContentHeight, alignment: .top)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .gesture(
                            DragGesture(minimumDistance: 6)
                                .onEnded { value in
                                    let dx = value.translation.width
                                    let predicted = value.predictedEndTranslation.width
                                    let velocity = predicted - dx

                                    // flick logic
                                    if abs(dx) > 40 || abs(velocity) > 120 {
                                        if dx < 0 {
                                            index = min(index + 1, albums.count - 1)
                                        } else {
                                            index = max(index - 1, 0)
                                        }
                                    } else {
                                        // snap to nearest center by computing closest center
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
                        .onAppear {
                            // ensure initial centering
                            proxy.scrollTo(index, anchor: .center)
                        }
                    } // GeometryReader
                } // ScrollViewReader
            } // end else
        } // Group
    }
}
// MARK: - Enhanced Background (aesthetic vinyl-style)
private struct BackgroundView: View {
    let albums: [SPAlbum]
    let currentIndex: Int
    
    @State private var blurredBg: UIImage? = nil

    var body: some View {
        ZStack {
            // Deep base — warm black
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.04, blue: 0.10),
                    Color(red: 0.04, green: 0.03, blue: 0.07),
                    Color(red: 0.02, green: 0.02, blue: 0.04)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Soft center glow (spotlight behind albums)
            RadialGradient(
                colors: [
                    Color(red: 0.12, green: 0.08, blue: 0.18).opacity(0.5),
                    Color(red: 0.06, green: 0.04, blue: 0.12).opacity(0.3),
                    .clear
                ],
                center: .center,
                startRadius: 60,
                endRadius: 420
            )
            .ignoresSafeArea()

            // Blurred current album art (tinted, subtle)
            if let image = blurredBg {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 120)
                    .saturation(0.4)
                    .opacity(0.25)
                    .blendMode(.softLight)
                    .ignoresSafeArea()
                    .animation(.easeInOut(duration: 0.8), value: currentIndex)
            } else {
                LinearGradient(
                    colors: [
                        Color(red: 0.08, green: 0.05, blue: 0.12).opacity(0.6),
                        Color(red: 0.04, green: 0.03, blue: 0.08).opacity(0.9)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            }

            // Inner vignette (darker edges)
            RadialGradient(
                colors: [.clear, .black.opacity(0.4), .black.opacity(0.85)],
                center: .center,
                startRadius: 80,
                endRadius: 500
            )
            .ignoresSafeArea()

            // Top-edge fade for depth
            LinearGradient(
                colors: [Color.black.opacity(0.35), .clear],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()
        }
        .task(id: currentIndex) {
            await loadBackgroundImage()
        }
    }

    // MARK: - Async Loader
    private func loadBackgroundImage() async {
        guard albums.indices.contains(currentIndex),
              let urlString = albums[currentIndex].images?.first?.url,
              let url = URL(string: urlString)
        else {
            blurredBg = nil
            return
        }

        // 1️⃣ Check cache first
        if let cached = ImageCache.shared.image(forKey: url.absoluteString) {
            await MainActor.run {
                blurredBg = cached
            }
            return
        }

        // 2️⃣ Async network load
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let ui = UIImage(data: data) {
                ImageCache.shared.setImage(ui, forKey: url.absoluteString)
                await MainActor.run {
                    blurredBg = ui
                }
            }
        } catch {
            // Fail silently (no blocking UI)
        }
    }
}

// MARK: - Enhanced Header
private struct HeaderView: View {
    @Binding var isAutoPlaying: Bool
    @Binding var showStats: Bool
    let albumCount: Int
    let currentIndex: Int
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your Vinyl Collection")
                        .font(.title2).bold()
                        .foregroundStyle(.white)
                    if albumCount > 0 {
                        Text("\(currentIndex + 1) of \(albumCount)")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                
                Spacer()
                
                HStack(spacing: 12) {
                    // Left: Go to Vinyl player
                    Button {
                        NotificationCenter.default.post(name: .goToVinylPage, object: nil)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Image(systemName: "record.circle")
                            .font(.system(size: 18))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(.ultraThinMaterial))
                    }
                    .accessibilityLabel("Open vinyl player")

                    // Stats
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            showStats.toggle()
                        }
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    } label: {
                        Image(systemName: showStats ? "chart.bar.fill" : "chart.bar")
                            .font(.system(size: 18))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(.ultraThinMaterial))
                    }
                    .accessibilityLabel(showStats ? "Hide stats" : "Show stats")

                    // Autoplay carousel (advances album every 3 seconds)
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            isAutoPlaying.toggle()
                        }
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    } label: {
                        Image(systemName: isAutoPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(.ultraThinMaterial))
                    }
                    .accessibilityLabel(isAutoPlaying ? "Pause autoplay" : "Autoplay carousel")

                    // Right: Go to Vinyl player
                    Button {
                        NotificationCenter.default.post(name: .goToVinylPage, object: nil)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Image(systemName: "record.circle")
                            .font(.system(size: 18))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(.ultraThinMaterial))
                    }
                    .accessibilityLabel("Open vinyl player")
                }
            }
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - Navigation Dots
private struct NavigationDots: View {
    let count: Int
    let current: Int
    
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<min(count, 10), id: \.self) { i in
                Circle()
                    .fill(i == current ? .white : .white.opacity(0.3))
                    .frame(width: i == current ? 8 : 6, height: i == current ? 8 : 6)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: current)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
        )
    }
}

// MARK: - Stats View (album name + artist name)
private struct StatsView: View {
    let albums: [SPAlbum]
    let currentIndex: Int
    
    var body: some View {
        if albums.indices.contains(currentIndex) {
            let album = albums[currentIndex]
            let artistNames = (album.artists ?? []).map { $0.name }.joined(separator: ", ")
            VStack(spacing: 12) {
                StatItem(icon: "rectangle.stack", value: album.name, label: "Album")
                StatItem(icon: "person.2", value: artistNames.isEmpty ? "—" : artistNames, label: "Artist")
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
            )
            .padding(.horizontal, 20)
        }
    }
}

private struct StatItem: View {
    let icon: String
    let value: String
    let label: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.7))
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Enhanced 3D Coverflow
private struct Enhanced3DCoverflow: ViewModifier {
    let currentIndex: Int
    let cardIndex: Int
    let cellWidth: CGFloat

    func body(content: Content) -> some View {
        GeometryReader { geo -> AnyView in
            // screen midpoint in global coords
            let screenMid = UIScreen.main.bounds.midX
            let cardMidX = geo.frame(in: .global).midX
            // relative distance in units of card width (fractional)
            let rawDistance = Double((cardMidX - screenMid) / cellWidth)
            // clamp to reasonable range
            let distance = min(max(rawDistance, -3.0), 3.0)
            let absDist = abs(distance)

            // Smooth closeness curve (use pow for smooth falloff)
            // closeness = 1 at center, -> 0 as absDist grows
            let closeness = max(0.0, 1.0 - pow(absDist / 2.5, 1.15))

            // scale range (center slightly larger)
            let minScale: CGFloat = 0.72
            let maxScale: CGFloat = 1.02
            let dynamicScale = minScale + (CGFloat(closeness) * (maxScale - minScale))

            // limit tilt to +/- 25 degrees, make tilt smaller overall
            let maxTilt: Double = 25.0
            let tiltDegrees = -distance * maxTilt * 0.9

            // subtle X parallax so cards curve like a shelf
            let xParallax = CGFloat(-distance) * (cellWidth * 0.18)

            // vertical lift for center + slight extra for near-cards
            let yOffset = CGFloat(absDist) * 8.0 - (closeness > 0.9 ? 6.0 : 0.0)

            // depth-of-field blur and opacity
            let dofBlur = CGFloat(absDist) * 1.8
            let alpha = 1.0 - (CGFloat(absDist) * 0.05)

            // zIndex based on closeness (center on top)
            let z = Double(100 - absDist * 20.0)

            let view = content
                .rotation3DEffect(.degrees(tiltDegrees), axis: (x: 0, y: 1, z: 0), perspective: 0.38)
                .scaleEffect(dynamicScale)
                .offset(x: xParallax, y: yOffset)
                .shadow(color: .black.opacity(cardIndex == currentIndex ? 0.55 : 0.28),
                        radius: cardIndex == currentIndex ? 26 : 12,
                        x: CGFloat(-distance) * 6.0,
                        y: cardIndex == currentIndex ? 16 : 8)
                .blur(radius: dofBlur)
                .opacity(Double(alpha))
                .zIndex(z)
                .animation(.interactiveSpring(response: 0.45, dampingFraction: 0.78, blendDuration: 0.06), value: currentIndex)

            return AnyView(view)
        }
        .frame(width: cellWidth)
    }
}

// ✅ NEW: Applies subtle perspective warping
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
        self.transformEffect(
            CGAffineTransform(scaleX: 1.0 - strength * 0.05, y: 1.0)
        )
    }
}

enum PerspectiveDirection {
    case forward, backward
}

// MARK: - Enhanced Album Card (Photo-Realistic 3D Vinyl Case)
private struct EnhancedAlbumCard: View {
    let album: SPAlbum
    let width: CGFloat
    let ns: Namespace.ID
    let isCenter: Bool
    var onSelect: (UIImage?) -> Void

    @State private var dominantColor: UIColor? = nil
    @State private var ui: UIImage?
    @State private var albumTint: UIColor? = nil   // spine tint

    private var height: CGFloat { width * 1.2 }
    private let radius: CGFloat = 12
    private let spine: CGFloat = 11       // wide enough for readable spine text
    private let thickness: CGFloat = 6    // proportional

    var body: some View {
        let artistText = (album.artists ?? []).map { $0.name }.joined(separator: ", ")

        VStack(spacing: 0) {
            // Main 3D case assembly
            ZStack {
                // LAYER 1: Back depth plate (now accepts tint)
                BackPlate(width: width, height: height, spine: spine, thickness: thickness, radius: radius, tint: dominantColor)

                // LAYER 2: Right thickness edge (same album color = one box)
                ThicknessEdge(height: height, thickness: thickness, radius: radius, tint: dominantColor)
                    .offset(x: (width / 2) - spine - thickness / 2, y: thickness * 0.4)

                // LAYER 3: Front cover
                FrontCover(album: album, ui: ui, width: width, height: height, spine: spine, radius: radius, ns: ns)
                    .offset(x: spine * 0.5 + 1.5)
                    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .stroke(Color.white.opacity(0.05), lineWidth: 0.9)
                            .blendMode(.overlay)
                    )
                    .overlay(
                        // Box corner: dark strip where front meets spine so it reads as inner corner
                        LinearGradient(
                            colors: [.black.opacity(0.5), .black.opacity(0.15), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: 10, height: height)
                        .offset(x: -(width - spine) / 2 + 5)
                        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                    )
                    .shadow(color: Color.black.opacity(0.65), radius: 4, x: -4, y: 0)
                    .shadow(color: Color.black.opacity(isCenter ? 0.45 : 0.32),
                            radius: isCenter ? 14 : 10, x: isCenter ? 8 : 6, y: isCenter ? 12 : 8)

                // Spine offset (place spine exactly touching left edge of front)
                SpinePanel(
                    width: spine,
                    height: height,
                    radius: radius,
                    tint: albumTint,
                    albumNameForSpine: album.name
                )
                .offset(x: -width / 2 + spine / 2 + 1)
                // LAYER 5: Seam details
                SeamDetails(width: width, height: height, spine: spine)
            }
            .frame(width: width + spine, height: height)
            .compositingGroup()
            .modifier(DepthDistortion(isCenter: isCenter, cardIndex: 0))
            .onTapGesture {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onSelect(ui)
            }
            .scaleEffect(isCenter ? 1.0 : 0.98)
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isCenter)

            // Reflection (starts at bottom edge)
            ReflectionView(ui: ui, width: width, height: height, spine: spine, radius: radius)
                .offset(y: 2)

            // Labels
            LabelsView(albumName: album.name, artistText: artistText, totalWidth: width + spine)
                .padding(.top, 10)
        }
        .task(id: album.id) {
            // Async load + cache + compute dominant color
            if ui == nil, let urlStr = album.images?.first?.url, let url = URL(string: urlStr) {
                // check cache
                if let cached = ImageCache.shared.image(forKey: url.absoluteString) {
                    self.ui = cached
                    DispatchQueue.global(qos: .userInitiated).async {
                        let c = cached.averageColor()
                        DispatchQueue.main.async {
                            self.dominantColor = c
                            // set spine tint to a slightly darker variant
                            self.albumTint = c?.withAlphaComponent(1.0)
                        }
                    }
                } else {
                    do {
                        let (data, _) = try await URLSession.shared.data(from: url)
                        if let img = UIImage(data: data) {
                            ImageCache.shared.setImage(img, forKey: url.absoluteString)
                            // compute color off main thread
                            DispatchQueue.global(qos: .userInitiated).async {
                                let c = img.averageColor()
                                DispatchQueue.main.async {
                                    self.ui = img
                                    self.dominantColor = c
                                    self.albumTint = c?.withAlphaComponent(1.0)
                                }
                            }
                        }
                    } catch {
                        // ignore failures for now
                    }
                }
            }
        }
    }
}

// MARK: - Back Plate (Depth/Shadow Layer)
private struct BackPlate: View {
    let width: CGFloat
    let height: CGFloat
    let spine: CGFloat
    let thickness: CGFloat
    let radius: CGFloat
    var tint: UIColor?

    var body: some View {
        let base = tint.map { Color(uiColor: $0).opacity(0.08) } ?? Color.black.opacity(0.95)
        let mid = tint.map { Color(uiColor: $0).opacity(0.06) } ?? Color(white: 0.08)

        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Color.black.opacity(0.95))
                .frame(width: width - spine, height: height)
                .offset(x: spine / 2 - thickness * 0.7, y: thickness * 0.5)
                .blur(radius: 8)

            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(LinearGradient(colors: [base, mid, Color.black.opacity(0.88)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: width - spine, height: height)
                .offset(x: spine / 2 - thickness * 0.4, y: thickness * 0.3)

            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(LinearGradient(colors: [.white.opacity(0.06), .clear],
                                       startPoint: .topLeading, endPoint: .center),
                        lineWidth: 1)
                .frame(width: width - spine, height: height)
                .offset(x: spine / 2 - thickness * 0.7, y: thickness * 0.5)
                .blendMode(.screen)
        }
        .shadow(color: .black.opacity(0.75), radius: 20, x: 10, y: 14)
    }
}

// MARK: - Thickness Edge (Right Side of Box) — same album color so whole case is one box
private struct ThicknessEdge: View {
    let height: CGFloat
    let thickness: CGFloat
    let radius: CGFloat
    var tint: UIColor? = nil

    var body: some View {
        let edgeColor = tint.map { Color(uiColor: $0) } ?? Color(white: 0.12)
        let edgeColorDark = tint.map { Color(uiColor: $0).opacity(0.85) } ?? Color(white: 0.08)

        ZStack {
            // shadow behind edge
            RoundedCorners(radius: radius * 0.65, corners: [.topRight, .bottomRight])
                .fill(edgeColorDark.opacity(0.9))
                .frame(width: thickness, height: height)
                .offset(x: 1.2, y: 1.2)
                .blur(radius: 2)

            // main edge — same solid album color as spine (one box)
            RoundedCorners(radius: radius * 0.55, corners: [.topRight, .bottomRight])
                .fill(
                    LinearGradient(
                        colors: [edgeColorDark, edgeColor, edgeColor],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: thickness, height: height)

            // subtle catch-light so edge is visible
            Rectangle()
                .fill(LinearGradient(colors: [.white.opacity(0.12), .white.opacity(0.04)], startPoint: .leading, endPoint: .trailing))
                .frame(width: thickness * 0.3, height: height)
                .offset(x: thickness * 0.2)
                .blendMode(.screen)

            // rim highlight
            RoundedCorners(radius: radius * 0.6, corners: [.topRight])
                .stroke(LinearGradient(colors: [.white.opacity(0.2), .clear], startPoint: .leading, endPoint: .trailing), lineWidth: 1.2)
                .frame(width: thickness, height: thickness * 1.2)
                .offset(y: -(height / 2 - thickness * 0.6))
        }
        .rotation3DEffect(.degrees(10), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
        .shadow(color: .black.opacity(0.6), radius: 6, x: 3, y: 5)
    }
}
private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { self.state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

// MARK: - Front Cover
private struct FrontCover: View {
    let album: SPAlbum
    let ui: UIImage?
    let width: CGFloat
    let height: CGFloat
    let spine: CGFloat
    let radius: CGFloat
    let ns: Namespace.ID
    
    var body: some View {
        Group {
            if let ui = ui {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .matchedGeometryEffect(id: album.id, in: ns)
                
            } else {
                LinearGradient(
                    colors: [.gray.opacity(0.25), .gray.opacity(0.45)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        // In FrontCover's body, replace the .clipShape with:
        .frame(width: width - spine, height: height)
        .clipShape(AlbumFrontShape(radius: radius))
        // rest of overlays / shadows remain the same
                .overlay(
                    // ✅ ENHANCED: Multi-layer lighting for depth
                    ZStack {
                        // Layer 1: Top-left highlight (bright catch light)
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [.white.opacity(0.35), .clear],
                                    startPoint: .topLeading,
                                    endPoint: .center
                                )
                            )
                            .blendMode(.screen)
                        
                        // Layer 2: Bottom-right shadow (depth shadow)
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [.clear, .black.opacity(0.30)],
                                    startPoint: .center,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .blendMode(.multiply)
                        
                        // Layer 3: Subtle edge vignette
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .stroke(
                                RadialGradient(
                                    gradient: Gradient(colors: [.clear, .black.opacity(0.15)]),
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: max(width, height) / 2
                                ),
                                lineWidth: 1.5
                            )
                            .blendMode(.multiply)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: radius))
                )
                .overlay(
                    Canvas { ctx, size in
                        var rng = SeededGenerator(seed: 42)
                        for _ in 0..<Int((size.width + size.height) * 0.12) {
                            let x = CGFloat.random(in: 0...size.width, using: &rng)
                            let y = CGFloat.random(in: 0...size.height, using: &rng)
                            ctx.fill(
                                Path(ellipseIn: CGRect(x: x, y: y, width: 1.2, height: 1.2)),
                                with: .color(.white.opacity(0.03))
                            )
                        }
                    }
                    .blendMode(.overlay)
                    .opacity(0.45)
                    .clipShape(RoundedRectangle(cornerRadius: radius))
                )
                .overlay(
                    // ✅ ENHANCED: Crisp rim highlight for edge definition
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.20), .white.opacity(0.06), .white.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                        .blendMode(.screen)
                )
                .shadow(color: .black.opacity(0.45), radius: 14, x: 6, y: 10)
                        .shadow(color: .black.opacity(0.25), radius: 6, x: 3, y: 4)
        // ✅ Secondary shadow for depth
                .overlay(
                            // ✅ NEW: Subtle case material texture
                            Canvas { ctx, size in
                                var rng = SeededGenerator(seed: 42)
                                for _ in 0..<Int((size.width + size.height) * 0.15) {
                                    let x = CGFloat.random(in: 0...size.width, using: &rng)
                                    let y = CGFloat.random(in: 0...size.height, using: &rng)
                                    let opacity = Double.random(in: 0.02...0.06, using: &rng)
                                    ctx.fill(
                                        Path(ellipseIn: CGRect(x: x, y: y, width: 1, height: 1)),
                                        with: .color(.white.opacity(opacity))
                                    )
                                }
                            }
                            .blendMode(.overlay)
                            .opacity(0.5)
                            .clipShape(RoundedRectangle(cornerRadius: radius))
                        )
                .overlay(
                    AlbumFrontShape(radius: radius)
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.12), .clear, .white.opacity(0.04)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.2
                        )
                        .blendMode(.screen)
                )
        .overlay(
            // Outer rim highlight
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.12), .clear, .white.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.2
                )
        )
        .overlay(
            // Left edge bevel highlight
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .trim(from: 0.02, to: 0.12)
                .stroke(Color.white.opacity(0.18), lineWidth: 2.5)
                .rotationEffect(.degrees(-90))
                .offset(x: -(width - spine) / 2 + 4)
                .blendMode(.screen)
        )
    }
}
private struct AlbumFrontShape: Shape {
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = min(radius, min(rect.width, rect.height) / 2)

        let topLeft = CGPoint(x: rect.minX,  y: rect.minY)
        let topRight = CGPoint(x: rect.maxX, y: rect.minY)
        let bottomRight = CGPoint(x: rect.maxX, y: rect.maxY)
        let bottomLeft = CGPoint(x: rect.minX, y: rect.maxY)

        p.move(to: topLeft)
        // top edge to start of top-right arc
        p.addLine(to: CGPoint(x: topRight.x - r, y: topRight.y))
        // top-right arc
        p.addArc(
            center: CGPoint(x: topRight.x - r, y: topRight.y + r),
            radius: r,
            startAngle: Angle(degrees: -90),
            endAngle: Angle(degrees: 0),
            clockwise: false
        )
        // right edge to start of bottom-right arc
        p.addLine(to: CGPoint(x: bottomRight.x, y: bottomRight.y - r))
        // bottom-right arc
        p.addArc(
            center: CGPoint(x: bottomRight.x - r, y: bottomRight.y - r),
            radius: r,
            startAngle: Angle(degrees: 0),
            endAngle: Angle(degrees: 90),
            clockwise: false
        )
        // bottom edge to bottom-left
        p.addLine(to: bottomLeft)
        // left edge up to top-left
        p.addLine(to: topLeft)
        p.closeSubpath()

        return p
    }
}

// MARK: - Spine Panel (Left Side)
// MARK: - Spine Panel (Left Side)
private struct SpinePanel: View {
    let width: CGFloat
    let height: CGFloat
    let radius: CGFloat
    var tint: UIColor? = nil
    let albumNameForSpine: String

    var body: some View {
        // Same solid color as album — spine is part of the album box
        let spineColor = tint.map { Color(uiColor: $0) } ?? Color(white: 0.18)
        let bevelLight = Color.white.opacity(0.18)

        ZStack {
            // ONE SOLID ALBUM COLOR — no gradient, reads as same box as cover
            RoundedCorners(radius: radius * 0.75, corners: [.topLeft, .bottomLeft])
                .fill(spineColor)
                .frame(width: width, height: height)

            // Very subtle fold — narrow darkening at seam so it’s still one box
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.black.opacity(0.22), .black.opacity(0.06), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 2, height: height * 0.92)
                .offset(x: width / 2 - 1)

            Rectangle()
                .fill(Color.white.opacity(0.04))
                .frame(width: 0.6, height: height * 0.82)
                .offset(x: width / 2 + 0.4)
                .blendMode(.screen)

            // TOP BEVEL
            RoundedCorners(radius: radius * 0.65, corners: [.topLeft])
                .stroke(LinearGradient(colors: [bevelLight.opacity(0.35),
                                                bevelLight.opacity(0.1), .clear],
                                       startPoint: .leading, endPoint: .trailing), lineWidth: 1.2)
                .frame(width: width * 0.86, height: 8)
                .offset(x: -width * 0.07, y: -(height/2) + 6)

            // Outer edge — subtle highlight so it reads as one box with an edge
            Rectangle()
                .fill(LinearGradient(colors: [.white.opacity(0.1), .white.opacity(0.03)],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(width: 1, height: height * 0.98)
                .offset(x: width / 2 - 0.5)

            RoundedCorners(radius: radius * 0.75, corners: [.topLeft, .bottomLeft])
                .stroke(LinearGradient(colors: [.white.opacity(0.05), .clear],
                                       startPoint: .topLeading, endPoint: .center),
                        lineWidth: 0.8)
                .frame(width: width, height: height)

            // VERY SUBTLE TEXTURE (kept faint)
            Canvas { ctx, size in
                var rng = SeededGenerator(seed: UInt64((width + height).bitPattern))
                let count = Int((size.width + size.height) * 0.05)
                for _ in 0..<count {
                    let x = CGFloat.random(in: 0...size.width, using: &rng)
                    let y = CGFloat.random(in: 0...size.height, using: &rng)
                    let a = Double.random(in: 0.01...0.03, using: &rng)
                    ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1, height: 1)),
                             with: .color(.white.opacity(a)))
                }
            }
            .opacity(0.45)
            .mask(RoundedCorners(radius: radius * 0.75, corners: [.topLeft, .bottomLeft])
                    .frame(width: width, height: height))

            // SPINE TITLE — reads as printed ink: slightly darker, subtle horizontal compression
            Text(albumNameForSpine)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .kerning(0.4)
                .foregroundStyle(Color.white.opacity(0.88))
                .scaleEffect(x: 0.96, y: 1.0, anchor: .center)
                .rotationEffect(.degrees(-90))
                .frame(height: height * 0.86)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .allowsTightening(true)
                .offset(x: -width * 0.12)
                .shadow(color: .black.opacity(0.75), radius: 0.6, x: 0, y: 0)
                .shadow(color: .black.opacity(0.6), radius: 0.5, x: 0.5, y: 0)
                .shadow(color: .black.opacity(0.6), radius: 0.5, x: -0.5, y: 0)
                .shadow(color: .black.opacity(0.6), radius: 0.5, x: 0, y: 0.5)
                .zIndex(10)
                .accessibilityHidden(true)
        }
        .compositingGroup()
        .rotation3DEffect(.degrees(-6), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
        .shadow(color: .black.opacity(0.60), radius: 10, x: -6, y: 8)
    }
}
// MARK: - Seam Details (Fold Between Spine & Front) — soft, natural binding shadow
private struct SeamDetails: View {
    let width: CGFloat
    let height: CGFloat
    let spine: CGFloat
    
    var body: some View {
        ZStack {
            // 1) Soft crease — narrow gradient darkest at fold, fades both ways (no harsh line)
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            .clear,
                            .black.opacity(0.35),
                            .black.opacity(0.58),
                            .black.opacity(0.35),
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 6, height: height * 0.96)
                .offset(x: -width / 2 + spine + 3)

            // 2) Gentle occlusion — wider, softer strip so spine feels recessed without muddiness
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            .black.opacity(0.25),
                            .black.opacity(0.55),
                            .black.opacity(0.62),
                            .black.opacity(0.55),
                            .black.opacity(0.25)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 5, height: height * 0.92)
                .offset(x: -width / 2 + spine + 2)
                .blendMode(.multiply)

            // 3) Soft falloff on front — gradual so the front plane ends naturally
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            .black.opacity(0.42),
                            .black.opacity(0.18),
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 22, height: height * 0.94)
                .offset(x: -width / 2 + spine + 4)
                .blendMode(.multiply)
        }
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
        HStack(spacing: 0) {
            // Spine reflection — darker band so reflection suggests two planes (reference)
            RoundedRectangle(cornerRadius: radius * 0.3, style: .continuous)
                .fill(Color.black.opacity(0.12))
                .frame(width: spine, height: height * 0.28)
                .mask(
                    LinearGradient(
                        colors: [.black.opacity(0.4), .black, .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: height * 0.28)
                )

            Group {
                if let ui = ui {
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFill()
                        .frame(width: width - spine, height: height)
                        .clipShape(RoundedRectangle(cornerRadius: radius))
                        .scaleEffect(x: 1, y: -1)
                        .rotation3DEffect(.degrees(15), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
                        .opacity(0.12)
                        .blur(radius: 3.5)
                        .mask(
                            LinearGradient(
                                colors: [.black, .black.opacity(0.7), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: height * 0.45)
                        )
                } else {
                    RoundedRectangle(cornerRadius: radius)
                        .fill(Color.white.opacity(0.03))
                        .frame(width: width - spine, height: height * 0.35)
                        .blur(radius: 5)
                        .scaleEffect(x: 1, y: -1)
                }
            }
            .frame(width: width - spine, alignment: .trailing)
        }
        .frame(width: width, alignment: .trailing)
        .offset(x: spine / 2)
    }
}

// MARK: - Labels View
private struct LabelsView: View {
    let albumName: String
    let artistText: String
    let totalWidth: CGFloat
    
    var body: some View {
        VStack(spacing: 3) {
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

// MARK: - Rounded Corners Helper Shape
private struct RoundedCorners: Shape {
    var radius: CGFloat
    var corners: UIRectCorner

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

// MARK: - Helper
private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

struct AlbumCoverFlowView_Previews: PreviewProvider {
    @Namespace static var ns
    
    static var previews: some View {
        AlbumCoverFlowView(ns: ns) { _, _ in }
            .preferredColorScheme(.dark)
    }
}
