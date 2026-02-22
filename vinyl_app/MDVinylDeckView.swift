import SwiftUI
import Combine
import QuartzCore // optional but good for future CA tweaks
import UIKit// for UIImpactFeedbackGenerator
import CoreImage
import CoreImage.CIFilterBuiltins




// Simple cache for procedurally-generated noise textures
final class NoiseCache {
    static let shared = NoiseCache()
    private let cache = NSCache<NSString, UIImage>()
    private let ciContext = sharedCIContext

    private init() { cache.countLimit = 16 }

    private func key(for size: CGSize, seed: Int) -> NSString {
        return "\(Int(size.width))x\(Int(size.height))-s\(seed)" as NSString
    }

    func imageSync(size: CGSize, seed: Int = 0, scale: CGFloat = UIScreen.main.scale) -> UIImage? {
        let k = key(for: size, seed: seed)
        if let img = cache.object(forKey: k) { return img }

        guard let noiseFilter = CIFilter(name: "CIRandomGenerator"),
              var noise = noiseFilter.outputImage else { return nil }

        if seed != 0 { noise = noise.transformed(by: CGAffineTransform(translationX: CGFloat(seed)*137, y: CGFloat(seed)*67)) }

        // Crop to pixel-sized rect
        let pixelRect = CGRect(origin: .zero, size: CGSize(width: size.width * scale, height: size.height * scale))
        noise = noise.cropped(to: pixelRect)

        guard let cg = ciContext.createCGImage(noise, from: pixelRect) else { return nil }
        let ui = UIImage(cgImage: cg, scale: scale, orientation: .up)
        cache.setObject(ui, forKey: k)
        return ui
    }

    func imageAsync(size: CGSize, seed: Int = 0, scale: CGFloat = UIScreen.main.scale, completion: @escaping (UIImage?) -> Void) {
        let k = key(for: size, seed: seed)
        if let img = cache.object(forKey: k) { completion(img); return }

        DispatchQueue.global(qos: .userInitiated).async {
            guard let noiseFilter = CIFilter(name: "CIRandomGenerator"),
                  var noise = noiseFilter.outputImage else {
                DispatchQueue.main.async { completion(nil) }; return
            }
            if seed != 0 { noise = noise.transformed(by: CGAffineTransform(translationX: CGFloat(seed)*137, y: CGFloat(seed)*67)) }

            let pixelRect = CGRect(origin: .zero, size: CGSize(width: size.width * scale, height: size.height * scale))
            noise = noise.cropped(to: pixelRect)

            guard let cg = self.ciContext.createCGImage(noise, from: pixelRect) else {
                DispatchQueue.main.async { completion(nil) }; return
            }
            let ui = UIImage(cgImage: cg, scale: scale, orientation: .up)
            self.cache.setObject(ui, forKey: k)
            DispatchQueue.main.async { completion(ui) }
        }
    }
}


fileprivate let sharedCIContext = CIContext()
// Replace the existing MDVinylDeckView struct with this version.
// All helper functions below (VinylRecordView, MPTonearmView, etc.) remain unchanged.

struct MDVinylDeckView: View {
    let cover: Image?
    @Binding var playing: Bool
    var showCoverCard: Bool = true
    
    // NEW: horizontal slide applied to the RECORD ONLY (tonearm stays put)
    var recordSlide: CGFloat = 0
    
    
    // Angles (world: 0°=right, +90°=up, -90°=down)
    //private let restAngle: Double = -90
    //private let playAngle: Double = -55
    // private let minAngle:  Double = -56
    // private let maxAngle:  Double = -100
    
    // Angles (0° = pointing right). Arm sits on the RIGHT side of the disc.
    private let restAngle: Double = 0      // parked, almost vertical on the right
    private let playAngle: Double = -25    // lowered onto the disc
    private let minAngle:  Double =  -5    // clamp so users can't drag past vertical
    private let maxAngle:  Double = -45    // clamp so needle won't cross too far in
    
    private let spinPerFrame: Double = 0.55
    
    @State private var armDeg = -90.0
    @State private var targetArmDeg: Double = -90.0
    @State private var rotation = 0.0
    @State private var wasOnDisc = false
    @State private var rotationSpeed: Double = 0.0         // current displayed spin speed
    @State private var rotationSpeedTarget: Double = 0.0   // where we lerp toward
    
    @State private var armDragOffset: CGFloat = 0      // tracks arm slide distance
    @State private var armStartPosition: CGPoint = .zero
    
    private let timer = Timer.publish(every: 1/60, on: .main, in: .common).autoconnect()
    
    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width
            let H = geo.size.height
            let isPad = UIDevice.current.userInterfaceIdiom == .pad
            let isPhone = UIDevice.current.userInterfaceIdiom == .phone || min(W, H) < 700
            
            // Larger proportions for iPad
            let artSide    = min(W, H) * (isPad ? 0.86 : 0.72)
            let recordSide = artSide * (isPad ? 1.06 : 0.98) // slightly larger disc
            let roomy = recordSide * 1.16    // container slightly larger than the visible disc
            
            ZStack {
                // ⛔️ IMPORTANT: Only render MDVinylDeckView's own background
                // when it's used as the *combined* layout (showCoverCard == true).
                // When used as the RIGHT panel in PlayerScreen we pass false,
                // so no dark box is drawn behind the disc.
                if showCoverCard {
                    if let cover {
                        cover.resizable().scaledToFill()
                            .frame(width: W, height: H).clipped()
                            .blur(radius: 18).saturation(0.95)
                            .overlay(
                                LinearGradient(
                                    colors: [.black.opacity(0.05), .clear],
                                    startPoint: .bottom, endPoint: .top
                                )
                            )
                            .ignoresSafeArea()
                    } else {
                        LinearGradient(colors: [.black, .gray], startPoint: .top, endPoint: .bottom)
                            .ignoresSafeArea()
                    }
                }
                // Side-by-side layout. Slight negative spacing so disc overlaps cover.
                HStack(spacing: 0) {
                    
                    // LEFT — album cover card
                    if showCoverCard {
                        Group {
                            if let cover {
                                cover.resizable().scaledToFill()
                            } else {
                                Color.gray.opacity(0.25)
                            }
                        }
                        .frame(width: artSide, height: artSide)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(.white.opacity(0.06), lineWidth: 1)
                            
                            
                            
                            
                            
                        )
                        .zIndex(0) // keep below disc
                    }
                    
                    
                    
                    // RIGHT — disc only (clipped), tonearm is drawn in overlay above it.
                    // RIGHT — disc only (clipped), tonearm is drawn in overlay above it.
                    // inside MDVinylDeckView body where you render the disc + overlay
                    // Replace the existing disc ZStack with this block:
                    ZStack {
                        // The vinyl itself — only THIS moves left/right via recordSlide (if you use it later)
                        VinylRecordView(art: cover, diameter: recordSide, rotationDeg: rotation)
                            .frame(width: recordSide, height: recordSide)
                            .contentShape(Circle())
                            .zIndex(1)
                        // If you pass a recordSlide param, apply it here:
                        //.offset(x: recordSlide)
                    }
                    .frame(width: roomy, height: roomy)   // IMPORTANT: container bigger than the disc
                    .background(Color.clear)
                    .compositingGroup()
                    .drawingGroup(opaque: false)
                    
                    
                    
                    
                    
                    
                    
                    // ⛔️ REMOVE any old container offsets like:
                    // .offset(x: showCoverCard ? -artSide * 0.12 : 0)    // keep transparency, avoid square backplate
                    
                    // Tonearm overlaid (NOT clipped by the disc)
                    .overlay(alignment: .center) {
                        GeometryReader { rGeo in
                            let S = min(rGeo.size.width, rGeo.size.height)
                            let center = CGPoint(x: S/2, y: S/2)
                            let radius = S/2
                            
                            // ✅ PIVOT: move much farther to the RIGHT of the disc (almost screen edge)
                            // Slightly above center so the arm leans down onto the record like a real deck.
                            // ✅ Move tonearm pivot slightly inward to match disc shift
                            let pivot = CGPoint(
                                x: center.x + radius * 0.95,
                                y: center.y - radius * 0.02
                            )
                            // ✅ LONGER arm to reach from the right pod onto the disc
                            let armLength  = radius * 1.62
                            let armWidth   = max(2.0, S * 0.022)
                            
                            MPTonearmView(worldAngle: armDeg, length: armLength, thickness: armWidth)
                                .position(pivot)          // place whole arm at the right-side pod
                                .shadow(radius: 3)
                                .contentShape(Rectangle().inset(by: -48))
                                .gesture(
                                    DragGesture(minimumDistance: 2)
                                        .onChanged { value in
                                            // ✅ NEW: Track starting position on first drag
                                            if armStartPosition == .zero {
                                                armStartPosition = value.startLocation
                                            }
                                            
                                            // Calculate drag distance (how far swiped)
                                            let dragDistance = value.location.x - armStartPosition.x
                                            
                                            // Update arm offset for smooth sliding feel
                                            withAnimation(.easeInOut(duration: 0.05)) {
                                                armDragOffset = dragDistance
                                            }
                                            
                                            handleDragChanged(value: value,
                                                              pivot: pivot,
                                                              center: center,
                                                              radius: radius,
                                                              armLength: armLength)
                                        }
                                        .onEnded { value in
                                            let dragDistance = value.location.x - armStartPosition.x
                                            let dragVelocity = value.predictedEndLocation.x - value.location.x
                                            
                                            // ✅ NEW: Momentum-based snapping
                                            // If dragged far enough or fast enough, snap to end position
                                            let threshold = 30.0
                                            let velocityThreshold = 200.0
                                            
                                            if abs(dragDistance) > threshold || abs(dragVelocity) > velocityThreshold {
                                                // Snap to final state
                                                withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) {
                                                    armDragOffset = dragDistance > 0 ? 80 : -80
                                                }
                                            } else {
                                                // Return to neutral
                                                withAnimation(.spring(response: 0.40, dampingFraction: 0.75)) {
                                                    armDragOffset = 0
                                                }
                                            }
                                            
                                            handleDragEnded(pivot: pivot,
                                                            center: center,
                                                            radius: radius,
                                                            armLength: armLength)
                                            
                                            // Reset tracking
                                            armStartPosition = .zero
                                        }
                                )
                                .zIndex(2)  // keep above the record
                        }
                        .allowsHitTesting(true)
                    }
                    // Pull the record a bit into the cover to mimic MD-Vinyl
                    // Pull the record a bit into the cover to mimic MD-Vinyl
                    // remove the line or use this smaller tuck:
                    // ✅ Shift the entire disc + tonearm slightly left to overlap the cover more
                    .offset(x: showCoverCard ? -artSide * 0.37 : -artSide * 0.18)
                    .onTapGesture {
                        // Keep a springy feel but shorter and heavily damped so it's subtle and smooth
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.90, blendDuration: 0)) {
                            if playing {
                                playing = false
                                SpotifyManager.shared.pause()
                                armDeg = restAngle
                            } else {
                                playing = true
                                // set target spin speed; actual rotationSpeed will be lerped towards this
                                rotationSpeedTarget = spinPerFrame
                                if !SpotifyManager.shared.isConnected {
                                    SpotifyManager.shared.connect()
                                }
                                SpotifyManager.shared.resume()
                                armDeg = playAngle
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .padding(isPad ? 44 : 16)
                }
            }
            // Spin animation — smoother acceleration & deceleration (lerp-style)
            .onReceive(timer) { _ in
                func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
                // smooth rotation speed
                if rotationSpeedTarget > 0 {
                        rotationSpeed = lerp(rotationSpeed, rotationSpeedTarget, 0.12)
                    } else {
                        rotationSpeed = lerp(rotationSpeed, 0.0, 0.06)
                        if rotationSpeed < 0.01 { rotationSpeed = 0.0 }
                    }
                    rotation = (rotation + rotationSpeed).truncatingRemainder(dividingBy: 360)
                }

            
            .onChange(of: playing) { _, now in
                var tx = Transaction(animation: .spring(response: 0.45, dampingFraction: 0.88, blendDuration: 0.12))
                tx.disablesAnimations = false
                targetArmDeg = now ? playAngle : restAngle

                withTransaction(tx) {
                    // ✅ SMOOTH ARM DESCENT: Spring animation feels like gravity pulling arm down
                    withAnimation(.spring(response: 0.50, dampingFraction: 0.85, blendDuration: 0)) {
                        armDeg = now ? playAngle : restAngle
                    }
                }

                // Spin gradually increases as arm drops
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(.easeInOut(duration: 0.30)) {
                        rotationSpeedTarget = now ? spinPerFrame : 0.0
                    }
                }
            }
            .onAppear {
                armDeg = playing ? playAngle : restAngle
                // ensure rotation targets are initialized
                rotationSpeedTarget = playing ? spinPerFrame : 0.0
            }
        }
    }
            // MARK: - Interaction helpers (correct scope)
         
        // MARK: - Interaction helpers

        private func tipPoint(pivot: CGPoint, deg: Double, length: CGFloat) -> CGPoint {
            let rad = deg * .pi / 180
            return CGPoint(x: pivot.x + CGFloat(cos(rad)) * length,
                           y: pivot.y + CGFloat(sin(rad)) * length)
        }

        private func isOnDisc(tip: CGPoint, center: CGPoint, radius: CGFloat) -> Bool {
            let dist = hypot(tip.x - center.x, tip.y - center.y)
            return (dist > radius * 0.70) && (dist < radius * 1.02)
        }

        private func handleDragChanged(value: DragGesture.Value,
                                       pivot: CGPoint,
                                       center: CGPoint,
                                       radius: CGFloat,
                                       armLength: CGFloat) {
            let v = CGPoint(x: value.location.x - pivot.x,
                            y: value.location.y - pivot.y)
            var deg = Double(atan2(v.y, v.x) * 180 / .pi)
            deg = max(minAngle, min(maxAngle, deg))
            armDeg = deg

            let tip = tipPoint(pivot: pivot, deg: armDeg, length: armLength)
            let onDisc = isOnDisc(tip: tip, center: center, radius: radius)

            if onDisc && !wasOnDisc {
                wasOnDisc = true
                if !playing {
                    playing = true
                    if !SpotifyManager.shared.isConnected { SpotifyManager.shared.connect() }
                    SpotifyManager.shared.resume()
                }
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
                
            } else if !onDisc && wasOnDisc {
                wasOnDisc = false
                if playing {
                    playing = false
                    SpotifyManager.shared.pause()
                }
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            }
        }
    private func handleDragEnded(pivot: CGPoint,
                                         center: CGPoint,
                                         radius: CGFloat,
                                         armLength: CGFloat) {
                let tip = tipPoint(pivot: pivot, deg: armDeg, length: armLength)
                let onDisc = isOnDisc(tip: tip, center: center, radius: radius)

                withAnimation(.spring(response: 0.40, dampingFraction: 0.75, blendDuration: 0)) {
                    armDeg = onDisc ? playAngle : restAngle
                }
            wasOnDisc = onDisc

            if onDisc && !playing {
                playing = true
                if !SpotifyManager.shared.isConnected { SpotifyManager.shared.connect() }
                SpotifyManager.shared.resume()
            } else if !onDisc && playing {
                playing = false
                SpotifyManager.shared.pause()
            }
        }
    } // END struct MDVinylDeckView
// -----------------------------
// Vintage vinyl view + helpers
// -----------------------------


// -----------------------------
// File-scope helpers & overlays
// // end struct MDVinylDeckView // END struct MDVinylDeckView
// -----------------------------
// Vintage vinyl view + helpers
// -----------------------------


// -----------------------------
// File-scope helpers & overlays
// -----------------------------


fileprivate extension UIImage {
    /// Average color via CIAreaAverage
    var averageColor: UIColor? {
        guard let ciImage = CIImage(image: self) else { return nil }
        let filter = CIFilter.areaAverage()
        filter.inputImage = ciImage
        filter.extent = ciImage.extent
        guard let output = filter.outputImage else { return nil }

        var bitmap = [UInt8](repeating: 0, count: 4)
        let ctx = CIContext(options: nil)
        ctx.render(output,
                   toBitmap: &bitmap,
                   rowBytes: 4,
                   bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                   format: .RGBA8,
                   colorSpace: CGColorSpaceCreateDeviceRGB())
        return UIColor(red: CGFloat(bitmap[0]) / 255.0,
                       green: CGFloat(bitmap[1]) / 255.0,
                       blue: CGFloat(bitmap[2]) / 255.0,
                       alpha: 1.0)
    }
}



/// Build a tiny tint gradient using the artwork's average color
fileprivate func dominantHueGradient(from uiImage: UIImage?) -> [Color] {
    guard let ui = uiImage, let avg = ui.averageColor else {
        return [.orange.opacity(0.04), .clear, .red.opacity(0.03), .clear]
    }
    let c = Color(avg)
    return [c.opacity(0.06), .clear, c.opacity(0.03), .clear]
}

// Alternating faint highlight rings for analog sheen.
private struct ShimmerBands: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let R = min(rect.width, rect.height) / 2
        // Use spacing that blends with the grooves; tweak stride to taste
        stride(from: R * 0.26, through: R * 0.96, by: 8.0).forEach { r in
            p.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        }
        return p
    }
}

private struct Grooves: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let R = min(rect.width, rect.height) / 2
        stride(from: R * 0.22, through: R * 0.98, by: 3.8).forEach { r in
            p.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        }
        return p
    }
}

private struct PaperTexture: View {
    var body: some View {
        Canvas { ctx, size in
            let count = Int((size.width + size.height) * 0.6)
            var rng = SeededGenerator(seed: 20251005)
            for _ in 0..<count {
                let x = CGFloat.random(in: 0...size.width, using: &rng)
                let y = CGFloat.random(in: 0...size.height, using: &rng)
                let r = CGFloat.random(in: 0.3...1.2, using: &rng)
                let a = Double.random(in: 0.08...0.22, using: &rng)
                ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)),
                         with: .color(.white.opacity(a)))
            }
        }
        .allowsHitTesting(false)
    }
}

private struct HairlineScratchesOverlay: View {
    var body: some View {
        Canvas { ctx, size in
            var rng = SeededGenerator(seed: 4242)
            let lines = 6
            for _ in 0..<lines {
                let start = CGPoint(
                    x: CGFloat.random(in: 0...size.width, using: &rng),
                    y: CGFloat.random(in: 0...size.height*0.4, using: &rng)
                )
                let dx = CGFloat.random(in: -40...40, using: &rng)
                let len = CGFloat.random(in: size.width*0.35...size.width*0.6, using: &rng)
                let end = CGPoint(x: start.x + dx, y: start.y + len)

                var path = Path()
                path.move(to: start)
                path.addLine(to: end)

                ctx.stroke(path,
                           with: .color(.white.opacity(Double.random(in: 0.06...0.16, using: &rng))),
                           lineWidth: CGFloat.random(in: 0.35...0.7, using: &rng))
            }
        }
        .blendMode(.screen)
        .allowsHitTesting(false)
    }
}

private struct DustOverlay: View {
    var body: some View {
        Canvas { ctx, size in
            let n = Int((size.width + size.height) * 0.35)
            var rng = SeededGenerator(seed: 1337)
            for _ in 0..<n {
                let x = CGFloat.random(in: 0...size.width, using: &rng)
                let y = CGFloat.random(in: 0...size.height, using: &rng)
                let r = CGFloat.random(in: 0.4...1.1, using: &rng)
                let alpha = Double.random(in: 0.12...0.40, using: &rng)
                ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)), with: .color(.white.opacity(alpha)))
            }
        }
        .allowsHitTesting(false)
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

// -----------------------------
// VinylRecordView (corrected)
// -----------------------------
private struct VinylRecordView: View {
    let art: Image?            // optional SwiftUI Image for label / tint
    let diameter: CGFloat
    let rotationDeg: Double

    var body: some View {
        ZStack {
            // Base black vinyl with subtle vignette
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.black.opacity(0.88), Color.black.opacity(0.62)],
                        center: .center,
                        startRadius: 2,
                        endRadius: diameter * 0.55
                    )
                )

            // Outer vignette for realistic depth falloff
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.clear, .black.opacity(0.28)],
                        center: .center,
                        startRadius: diameter * 0.10,
                        endRadius: diameter * 0.55
                    )
                )
                .blendMode(.multiply)

            // subtle blurred cover-tint reflection (vintage-ish)
            Group {
                if let ui = art?.asUIImage() {
                    if let filtered = applyVintageFilter(to: ui) {
                        filtered
                            .resizable()
                            .scaledToFill()
                            .blur(radius: 16)
                            .saturation(0.7)
                            .opacity(0.12)
                            .clipShape(Circle())
                    } else {
                        Image(uiImage: ui)
                            .resizable()
                            .scaledToFill()
                            .blur(radius: 16)
                            .saturation(0.7)
                            .opacity(0.12)
                            .clipShape(Circle())
                    }
                } else if let art {
                    art
                        .resizable()
                        .scaledToFill()
                        .blur(radius: 16)
                        .saturation(0.7)
                        .opacity(0.12)
                        .clipShape(Circle())
                }
            }

            // edge bevel / rim highlight
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.06), .clear, Color.white.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 3
                )
                .blur(radius: 0.8)

            // inner carved groove shadow
            Circle()
                .strokeBorder(Color.black.opacity(0.28), lineWidth: 6)
                .blur(radius: 4)
                .opacity(0.35)

            // -----------------------
            // Surface texture / subsurface noise (placed under grooves)
            // -----------------------
            // NOTE: NoiseDepthOverlay uses rotationDeg as driver (no Date()),
            // and is cached internally for performance.
            // AFTER outer vignette & cover-tint group
            NoiseDepthOverlay(diameter: diameter, rotationDeg: rotationDeg, seed: 7)
                .blendMode(.multiply)
                .opacity(0.12)
                .clipShape(Circle())

            RimBevelOverlay(diameter: diameter)
                .opacity(0.95)
                .clipShape(Circle())

            InnerAOOverlay(diameter: diameter)
                .opacity(0.6)
                .clipShape(Circle())

            // GROOVES
            Grooves()
                .stroke(style: StrokeStyle(lineWidth: 0.55))
                .foregroundStyle(Color.white.opacity(0.07))
                .mask(
                    RadialGradient(
                        colors: [.clear, .black, .black, .clear],
                        center: .center,
                        startRadius: diameter * 0.10,
                        endRadius: diameter * 0.53
                    )
                )
                .drawingGroup()
                .overlay(
                    GrooveDepthHint(diameter: diameter)
                        .clipShape(Circle())
                        .opacity(0.08)
                )

            // SHIMMER BANDS (subtle)
            ShimmerBands()
                .stroke(style: StrokeStyle(lineWidth: 1))
                .foregroundStyle(Color.white.opacity(0.06))
                .blendMode(.overlay)
                .rotationEffect(.degrees(rotationDeg * 0.25))
            // Curved anisotropic highlight — gives a curved glossy band
            Circle()
                .fill(
                    AngularGradient(
                        colors: [
                            .clear,
                            .white.opacity(0.14),
                            .clear,
                            .white.opacity(0.09),
                            .clear
                        ],
                        center: .center
                    )
                )
                .blur(radius: 8)
                .opacity(0.25)
                .rotationEffect(.degrees(rotationDeg * 0.4 + 25))
                .blendMode(.screen)
            // DEAD-WAX ring
            Circle()
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
                .frame(width: diameter * 0.48, height: diameter * 0.48)

            // LIGHT SWEEP (rotates a little slower than disc)
            Circle()
                .fill(
                    AngularGradient(
                        colors: [.clear, Color.white.opacity(0.14), .clear, Color.white.opacity(0.10), .clear],
                        center: .center
                    )
                )
                .blur(radius: 16)
                .opacity(0.18)
                .rotationEffect(.degrees(rotationDeg * 0.6))
            
            SpecularBandOverlay(diameter: diameter, rotationDeg: rotationDeg)
                .opacity(0.14)
            
                .overlay(
                    Circle()
                        .fill(
                            AngularGradient(
                                colors: [
                                    .white.opacity(0.0),
                                    .white.opacity(0.15),
                                    .white.opacity(0.0),
                                    .white.opacity(0.1),
                                    .clear
                                ],
                                center: .center
                            )
                        )
                        .blur(radius: 8)
                        .opacity(0.25)
                        .rotationEffect(.degrees(rotationDeg * 0.4 + 25))
                )
            // Soft rim lighting along the record’s edge
            Circle()
                .strokeBorder(
                    AngularGradient(
                        colors: [.clear, .white.opacity(0.25), .clear, .white.opacity(0.15), .clear],
                        center: .center
                    ),
                    lineWidth: 2
                )
                .blur(radius: 1.5)
                .blendMode(.screen)
                .opacity(0.2)

            // CENTER LABEL (album art), metallic rim + paper texture
            Group {
                if let ui = art?.asUIImage() {
                    Image(uiImage: ui).resizable().scaledToFill()
                } else if let art {
                    art.resizable().scaledToFill()
                } else {
                    Color.gray.opacity(0.35)
                }
            }
            .frame(width: diameter * 0.34, height: diameter * 0.34)
            .clipShape(Circle())
            .overlay(
                ZStack {
                    Circle().stroke(metalFoilGradient, lineWidth: 2.2)
                    Circle().inset(by: 6).stroke(Color.white.opacity(0.10), lineWidth: 0.9)
                }
            )
            .overlay(PaperTexture().opacity(0.08).clipShape(Circle()))
            
            .overlay(
                LabelInnerShadow(labelDiameter: diameter * 0.34)
                    .clipShape(Circle())
                    .opacity(0.6)
            )
            .overlay(
                LabelParallax(labelDiameter: diameter * 0.34, rotationDeg: rotationDeg)
                    .clipShape(Circle())
                    .opacity(0.5)
            )

            // SPINDLE HOLE
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.gray.opacity(0.6), .black],
                        center: .center,
                        startRadius: 0,
                        endRadius: diameter * 0.03
                    )
                )
                .frame(width: diameter * 0.055, height: diameter * 0.055)
                .shadow(radius: 0.8)

            // -----------------------
            // NEW vintage overlays (surface-level, ABOVE grooves)
            // -----------------------

            // 1) rust / brown spots near grooves (multiply so it darkens)
            RustSpotsOverlay(diameter: diameter)
                .blendMode(.multiply)
                .opacity(0.18)
                .clipShape(Circle())

            // 2) edge wear / thin chipped rim (masked radial gradient)
            EdgeWearOverlay(diameter: diameter)
                .blendMode(.overlay)
                .opacity(0.22)
                .clipShape(Circle())

            // 3) fingerprint / smudge overlays (subtle overlay)
            // If you want to enable fingerprint smudges, uncomment below and implement FingerprintSmudgeOverlay accordingly
            // FingerprintSmudgeOverlay(diameter: diameter).blendMode(.overlay).opacity(0.06).clipShape(Circle())

            // Final glue: ambient soft light & tint
            // Reduced ambient lift (subtle, not a halo)
            // Subtle surface depth — no white glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            .black.opacity(0.15), // center slightly darker
                            .clear                // fades to nothing
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: diameter * 0.55
                    )
                )
                .blendMode(.multiply)
                .opacity(0.25)
        }
        // end of ZStack content
        .frame(width: diameter, height: diameter)
        .rotationEffect(.degrees(rotationDeg))    // spinning
        .compositingGroup()                       // keep grouping; we'll mask at the end
        // subtle tint sweep derived from artwork
        .overlay(
            AngularGradient(
                colors: dominantHueGradient(from: art?.asUIImage()),
                center: .center
            )
            .blendMode(.screen)
            .clipShape(Circle())
        )
        // Adds moving light depth and grain (kept as top-level overlay but cheap)
        .overlay(
            NoiseDepthOverlay(diameter: diameter, rotationDeg: rotationDeg, seed: 11)
                .compositingGroup()
                .mask(Circle())
                .opacity(0.06)
        )
        .overlay(
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.clear, Color.black.opacity(0.25)],
                        center: .center,
                        startRadius: diameter * 0.2,
                        endRadius: diameter * 0.5
                    )
                )
                .blendMode(.multiply)
                .opacity(0.4)
        )
        // Slight radial warps to simulate aged vinyl
        .overlay(
            RadialCreaseOverlay()
                .opacity(0.03)
                .compositingGroup()
                .mask(Circle())
        )
        .overlay(DustOverlay().opacity(0.05).clipShape(Circle()))
        .overlay(HairlineScratchesOverlay().opacity(0.025).clipShape(Circle()))
        // Faint micro scratches — short surface scuffs
        .overlay(MicroScratchOverlay().opacity(0.015).clipShape(Circle()))
        .overlay(GrooveHighlightOverlay(diameter: diameter).clipShape(Circle()))
        .overlay(
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 1.0, green: 0.95, blue: 0.9).opacity(0.05), // warm
                    Color(red: 0.85, green: 0.9, blue: 1.0).opacity(0.05)   // cool
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .blendMode(.softLight)
            .compositingGroup()
            .mask(Circle())
        )
        .overlay(
            DirectionalLightingOverlay(diameter: diameter)
                .opacity(0.18)
                .compositingGroup()
                .mask(Circle())
        )
        .overlay(
            GrooveImperfectionOverlay(diameter: diameter)
                .opacity(0.04)
                .compositingGroup()
                .mask(Circle())
        )
        .overlay(
            GrooveDepthHint(diameter: diameter)
                .opacity(0.08)
                .compositingGroup()
                .mask(Circle())
        )
        .overlay(
            Circle()
                .strokeBorder(
                    RadialGradient(
                        colors: [.white.opacity(0.2), .clear],
                        center: .center,
                        startRadius: diameter * 0.45,
                        endRadius: diameter * 0.5
                    ),
                    lineWidth: diameter * 0.04
                )
                .blur(radius: 6)              // reduced blur to limit bleed
                .blendMode(.screen)
                .opacity(0.12)               // reduced opacity
                .compositingGroup()
                .mask(Circle())
        )
        .compositingGroup()
        .mask(Circle())
    } // end var body: some View

    private var metalFoilGradient: AngularGradient {
        AngularGradient(
            colors: [
                .white.opacity(0.65), .gray.opacity(0.35), .white.opacity(0.5),
                .gray.opacity(0.4), .white.opacity(0.55), .gray.opacity(0.3), .white.opacity(0.6)
            ],
            center: .center
        )
    }
} // end struct VinylRecordView

private struct RadialCreaseOverlay: View {
    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let maxR = min(size.width, size.height) / 2
            var path = Path()
            for i in stride(from: 0, to: 360, by: 15) {
                let angle = CGFloat(i) * .pi / 180
                let offset = CGFloat.random(in: -3...3)
                let x = c.x + cos(angle) * (maxR + offset)
                let y = c.y + sin(angle) * (maxR + offset)
                path.move(to: c)
                path.addLine(to: CGPoint(x: x, y: y))
            }
            ctx.stroke(path, with: .color(.white.opacity(0.03)), lineWidth: 0.6)
        }
        .blur(radius: 1.2)
        .blendMode(.overlay)
        .allowsHitTesting(false)
    }
}
private struct MicroScratchOverlay: View {
    var body: some View {
        Canvas { ctx, size in
            var rng = SeededGenerator(seed: 51515)
            for _ in 0..<80 {
                let x = CGFloat.random(in: 0...size.width, using: &rng)
                let y = CGFloat.random(in: 0...size.height, using: &rng)
                let length = CGFloat.random(in: 5...14, using: &rng)
                let angle = CGFloat.random(in: 0...CGFloat.pi * 2, using: &rng)
                let endX = x + cos(angle) * length
                let endY = y + sin(angle) * length

                var path = Path()
                path.move(to: CGPoint(x: x, y: y))
                path.addLine(to: CGPoint(x: endX, y: endY))

                ctx.stroke(path,
                           with: .color(.white.opacity(Double.random(in: 0.04...0.08, using: &rng))),
                           lineWidth: 0.4)
            }
        }
        .blur(radius: 0.3)
        .blendMode(.screen)
        .allowsHitTesting(false)
    }
}
private struct GrooveImperfectionOverlay: View {
    let diameter: CGFloat
    var body: some View {
        Canvas { ctx, size in
            var rng = SeededGenerator(seed: 404)
            let center = CGPoint(x: size.width/2, y: size.height/2)
            for _ in 0..<20 {
                let startAngle = CGFloat.random(in: 0..<CGFloat.pi * 2, using: &rng)
                let arcLength = CGFloat.random(in: 0.2..<1.0, using: &rng)
                let radius = CGFloat.random(in: diameter*0.15...diameter*0.48, using: &rng)
                let path = Path { p in
                    p.addArc(center: center, radius: radius,
                             startAngle: .radians(Double(startAngle)),
                             endAngle: .radians(Double(startAngle + arcLength)), clockwise: false)
                }
                ctx.stroke(path, with: .color(.white.opacity(Double.random(in: 0.05...0.15, using: &rng))), lineWidth: 0.5)
            }
        }
        .blendMode(.overlay)
        .allowsHitTesting(false)
    }
}

private struct AngularSheenOverlay: View {
    let rotationDeg: Double
    var body: some View {
        AngularGradient(
            gradient: Gradient(colors: [
                .white.opacity(0.0),
                .white.opacity(0.12),
                .white.opacity(0.0),
                .white.opacity(0.10),
                .white.opacity(0.0)
            ]),
            center: .center
        )
        .rotationEffect(.degrees(rotationDeg * 0.5))
        .blur(radius: 2.5)
    }
}

    
private struct NoiseDepthOverlay: View {
    let diameter: CGFloat
    let rotationDeg: Double
    let seed: UInt64

    // simple in-memory cache keyed by size+seed
    private static var cache = NSCache<NSString, UIImage>()

    var body: some View {
        GeometryReader { geo in
            // Compute uiImage first, then return a single View expression
            let size = geo.size
            let key = "\(Int(size.width))x\(Int(size.height))-\(seed)" as NSString

            let uiImage: UIImage = {
                if let cached = NoiseDepthOverlay.cache.object(forKey: key) {
                    return cached
                }
                let extent = CGRect(origin: .zero, size: size)
                if let noiseFilter = CIFilter(name: "CIRandomGenerator"),
                   let noiseCI = noiseFilter.outputImage?.cropped(to: extent),
                   let cg = sharedCIContext.createCGImage(noiseCI, from: extent) {
                    let created = UIImage(cgImage: cg)
                    NoiseDepthOverlay.cache.setObject(created, forKey: key)
                    return created
                }
                // Fallback: solid 1x1 transparent image to avoid returning Void
                let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
                return renderer.image { _ in UIColor.clear.setFill(); UIBezierPath(rect: CGRect(x: 0, y: 0, width: 1, height: 1)).fill() }
            }()

            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .saturation(0.0)
                .blur(radius: 18)
                .contrast(1.35)
                .opacity(0.12)
                .rotationEffect(.degrees(rotationDeg * 0.6))
                .colorMultiply(Color(red: 0.12, green: 0.14, blue: 0.10))
                .blendMode(.multiply)
        }
        .frame(width: diameter, height: diameter)
        .allowsHitTesting(false)
    }
}
    private struct DirectionalLightingOverlay: View {
        let diameter: CGFloat
        var body: some View {
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.white.opacity(0.12),
                    Color.black.opacity(0.25)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .opacity(0.25)
            .blendMode(.softLight)
            .clipShape(Circle())
        }
    }
// 1) Rim bevel (thin layered rim highlight + inner shadow)
private struct RimBevelOverlay: View {
    let diameter: CGFloat
    var body: some View {
        ZStack {
            // thin bright rim
            Circle()
                .strokeBorder(
                    LinearGradient(colors: [
                        Color.white.opacity(0.12),
                        Color.white.opacity(0.03),
                        Color.clear
                    ], startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: diameter * 0.01
                )
                .blur(radius: 0.6)
                .opacity(0.85)

            // small dark inner ring to imply thickness
            Circle()
                .inset(by: diameter * 0.012)
                .stroke(Color.black.opacity(0.45), lineWidth: diameter * 0.013)
                .blur(radius: 1.2)
                .opacity(0.6)
        }
        .allowsHitTesting(false)
    }
}

// 2) Inner Ambient Occlusion (subtle darkening under the dead-wax area)
private struct InnerAOOverlay: View {
    let diameter: CGFloat
    var body: some View {
        Circle()
            .fill(
                RadialGradient(gradient: Gradient(stops: [
                    .init(color: Color.black.opacity(0.45), location: 0.60),
                    .init(color: Color.black.opacity(0.18), location: 0.78),
                    .init(color: Color.clear, location: 0.97)
                ]), center: .center, startRadius: 0, endRadius: diameter * 0.5)
            )
            .blendMode(.multiply)
            .allowsHitTesting(false)
    }
}

// 3) Specular band (thin gleam that moves with rotation — gives curved surface)
private struct SpecularBandOverlay: View {
    let diameter: CGFloat
    let rotationDeg: Double
    var body: some View {
        // make a narrow curved highlight across the face
        Circle()
            .stroke(LinearGradient(colors: [
                Color.white.opacity(0.0),
                Color.white.opacity(0.55),
                Color.white.opacity(0.0)
            ], startPoint: .leading, endPoint: .trailing), lineWidth: diameter * 0.06)
            .scaleEffect(x: 1.0, y: 0.35, anchor: .center) // flatten into a band
            .rotationEffect(.degrees(rotationDeg * 0.45 + 12)) // ties to disc rotation
            .blur(radius: 6)
            .opacity(0.14)
            .blendMode(.screen)
            .allowsHitTesting(false)
    }
}

// 4) Label depth inner shadow (gives label paper thickness)
private struct LabelInnerShadow: View {
    let labelDiameter: CGFloat
    var body: some View {
        Circle()
            .stroke(Color.black.opacity(0.28), lineWidth: labelDiameter * 0.06)
            .blur(radius: 3)
            .clipShape(Circle())
            .allowsHitTesting(false)
    }
}

// 5) Micro groove emboss (very subtle radial gradient to suggest carved grooves)
private struct GrooveDepthHint: View {
    let diameter: CGFloat
    var body: some View {
        Circle()
            .stroke(
                RadialGradient(gradient: Gradient(colors: [Color.clear, Color.black.opacity(0.04)]),
                               center: .center,
                               startRadius: diameter * 0.25,
                               endRadius: diameter * 0.52),
                lineWidth: diameter * 0.012
            )
            .blur(radius: 0.6)
            .blendMode(.multiply)
            .allowsHitTesting(false)
    }
}

// 6) Micro parallax layer (slightly offset copy of label to create subtle depth)
private struct LabelParallax: View {
    let labelDiameter: CGFloat
    let rotationDeg: Double
    var body: some View {
        Circle()
            .stroke(Color.white.opacity(0.02), lineWidth: 1)
            .scaleEffect(1.002)
            .rotationEffect(.degrees(rotationDeg * 0.1))
            .offset(x: CGFloat(cos(rotationDeg * .pi/180)) * 0.3, y: -CGFloat(sin(rotationDeg * .pi/180)) * 0.3)
            .blendMode(.overlay)
            .allowsHitTesting(false)
    }
}
    private struct GrooveHighlightOverlay: View {
        let diameter: CGFloat
        var body: some View {
            AngularGradient(
                gradient: Gradient(colors: [
                    Color.white.opacity(0.03),
                    Color.white.opacity(0.14),
                    Color.white.opacity(0.03),
                    Color.white.opacity(0.10),
                    Color.white.opacity(0.03)
                ]),
                center: .center
            )
            .blur(radius: 8)
            .opacity(0.12)
            .blendMode(.overlay)
        }
    }



    
    
    // -----------------------------
    // File-scope Core Image helpers
    // -----------------------------
    private let ciContext = CIContext()

fileprivate func coverImageForHelpers(_ cover: Image?) -> UIImage? {
    guard let cover = cover else { return nil }
    if #available(iOS 16.0, *) {
        let renderer = ImageRenderer(content: cover)
        renderer.scale = UIScreen.main.scale
        return renderer.uiImage
    }
    return nil
}

    
    extension Image {
        /// Render SwiftUI Image to UIImage. Uses ImageRenderer (iOS 16+). Returns nil on older OS.
        func asUIImage(scale: CGFloat = UIScreen.main.scale) -> UIImage? {
            if #available(iOS 16.0, *) {
                let renderer = ImageRenderer(content: self)
                renderer.scale = scale
                return renderer.uiImage
            } else {
                return nil
            }
        }
    }
// -----------------------------
// Vintage overlay helpers
//
private struct RustSpotsOverlay: View {
    let diameter: CGFloat
    var body: some View {
        Canvas { ctx, size in
            var rng = SeededGenerator(seed: 424242)
            let center = CGPoint(x: size.width/2, y: size.height/2)
            let count = Int(6 + Double.random(in: 0...6, using: &rng))
            for _ in 0..<count {
                let angle = Double.random(in: 0...(2 * Double.pi), using: &rng)
                let r = CGFloat.random(in: diameter * 0.28...diameter * 0.70, using: &rng)
                let px = center.x + CGFloat(cos(angle)) * r
                let py = center.y + CGFloat(sin(angle)) * r
                let w = CGFloat.random(in: diameter * 0.03...diameter * 0.10, using: &rng)
                let h = w * CGFloat.random(in: 0.6...1.6, using: &rng)
                var p = Path(ellipseIn: CGRect(x: px - w/2, y: py - h/2, width: w, height: h))
                let jitter = CGFloat.random(in: -w*0.18...w*0.18, using: &rng)
                p = p.applying(CGAffineTransform(translationX: jitter, y: jitter))
                let rust = Color(red: 0.45 + Double.random(in: -0.06...0.06, using: &rng),
                                 green: 0.28 + Double.random(in: -0.05...0.05, using: &rng),
                                 blue: 0.12 + Double.random(in: -0.03...0.03, using: &rng),
                                 opacity: Double.random(in: 0.55...0.85, using: &rng))
                ctx.fill(p, with: .color(rust))
            }
        }
        .allowsHitTesting(false)
    }
}


private struct EdgeWearOverlay: View {
    let diameter: CGFloat
    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    gradient: Gradient(stops: [
                        .init(color: Color.white.opacity(0.06), location: 0.90),
                        .init(color: Color.white.opacity(0.02), location: 0.94),
                        .init(color: Color.clear, location: 0.98)
                    ]),
                    center: .center,
                    startRadius: 0,
                    endRadius: diameter/2
                )
            )
            .mask(
                Circle().inset(by: diameter * 0.04)
                    .stroke(lineWidth: diameter * 0.06)
            )
            .allowsHitTesting(false)
    }
}


    
fileprivate func applyVintageFilter(to uiImage: UIImage?) -> Image? {
    guard let uiImage = uiImage else { return nil }
    let ci = CIImage(image: uiImage)
    let filter = CIFilter.photoEffectTransfer()
    filter.inputImage = ci

    guard var output = filter.outputImage else { return Image(uiImage: uiImage) }

    // subtle grain
    if let grain = CIFilter.randomGenerator().outputImage?
        .cropped(to: ci!.extent)
        .applyingFilter("CIColorControls", parameters: ["inputBrightness": 0, "inputContrast": 1, "inputSaturation": 0]) {

        let matrix = CIFilter.colorMatrix()
        matrix.inputImage = grain
        matrix.rVector = CIVector(x: 0, y: 0, z: 0, w: 0.02)
        matrix.gVector = CIVector(x: 0, y: 0, z: 0, w: 0.02)
        matrix.bVector = CIVector(x: 0, y: 0, z: 0, w: 0.02)
        matrix.aVector = CIVector(x: 0, y: 0, z: 0, w: 0.02)

        if let grainMapped = matrix.outputImage {
            output = grainMapped.composited(over: output)
        }
    }

    if let cg = sharedCIContext.createCGImage(output, from: output.extent) {
        return Image(uiImage: UIImage(cgImage: cg))
    } else {
        return Image(uiImage: uiImage)
    }
}
    


    // MARK: - Realistic tonearm
private struct MPTonearmView: View {
    let worldAngle: Double
    let length: CGFloat
    let thickness: CGFloat
    var slideOffset: CGFloat = 0
    
    var body: some View {
        ZStack(alignment: .top) {
            // ✅ NEW: Tonearm base pod (more realistic)
            VStack(spacing: 0) {
                // Top acrylic pod surface
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.35),
                                Color.white.opacity(0.08),
                                Color.gray.opacity(0.15)
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: thickness * 2.2
                        )
                    )
                    .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 0.8))
                    .frame(width: thickness * 4.2, height: thickness * 2.2)
                
                // Pod base (darker underside)
                Ellipse()
                    .fill(Color.black.opacity(0.6))
                    .frame(width: thickness * 4.0, height: thickness * 0.8)
            }
            .offset(x: -thickness * 1.0, y: -thickness * 1.2)
            .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)
            .rotationEffect(.degrees(worldAngle + 90), anchor: .top)
                    .offset(x: slideOffset) // ✅ 
            
            // ✅ NEW: Vertical pivot post (chrome-like)
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: thickness * 0.4)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.7),
                                Color.gray.opacity(0.5),
                                Color.white.opacity(0.4),
                                Color.black.opacity(0.3)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: thickness * 1.1, height: thickness * 7.0)
                    .overlay(
                        RoundedRectangle(cornerRadius: thickness * 0.4)
                            .stroke(Color.white.opacity(0.4), lineWidth: 0.5)
                    )
            }
            .offset(x: -thickness * 1.4, y: -thickness * 0.6)
            .shadow(color: .black.opacity(0.3), radius: 3, x: 1, y: 1)
            
            // ✅ NEW: Heavy counterweight (behind pivot for balance)
            RoundedRectangle(cornerRadius: thickness * 0.35, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.95),
                            Color.black.opacity(0.75)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: thickness * 2.2, height: thickness * 1.8)
                .overlay(
                    RoundedRectangle(cornerRadius: thickness * 0.35)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1.2)
                )
                .offset(x: -thickness * 3.0, y: thickness * 0.3)
                .shadow(color: .black.opacity(0.4), radius: 5, x: 2, y: 2)
            
            // ✅ NEW: Arm tube assembly (polished aluminum)
            VStack(spacing: 0) {
                // Main arm tube with realistic metallic sheen
                RoundedRectangle(cornerRadius: thickness * 0.6)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.9),    // bright highlight
                                Color.gray.opacity(0.6),      // mid-tone
                                Color.black.opacity(0.15),    // shadow
                                Color.white.opacity(0.4)      // subtle shine
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: thickness * 0.95, height: length)
                    .overlay(
                        RoundedRectangle(cornerRadius: thickness * 0.6)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.6),
                                        Color.clear,
                                        Color.black.opacity(0.3)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                lineWidth: 1
                            )
                    )
                
                // Headshell (black aluminum block)
                RoundedRectangle(cornerRadius: thickness * 0.4, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.88),
                                Color.black.opacity(0.75)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: thickness * 2.0, height: thickness * 1.1)
                    .overlay(
                        RoundedRectangle(cornerRadius: thickness * 0.4)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                
                // Cartridge (small black box at tip)
                RoundedRectangle(cornerRadius: thickness * 0.2)
                    .fill(.black)
                    .frame(width: thickness * 0.75, height: thickness * 0.75)
                    .offset(y: thickness * 0.15)
                    .shadow(color: .black.opacity(0.5), radius: 1)
            }
            .offset(y: thickness * 2.2)
        }
        // Rotate around pivot point (top center)
        .rotationEffect(.degrees(worldAngle + 90), anchor: .top)
    }
}
