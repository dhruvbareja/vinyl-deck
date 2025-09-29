import SwiftUI
import Combine

/// MD-style deck: blurred cover bg, big cover card (optional), record + tonearm.
/// `playing` is bound to Spotify state from the outside.
struct MDVinylDeckView: View {
    let cover: Image?
    @Binding var playing: Bool
    var showCoverCard: Bool = true

    // Tuning
    private let coverSizeRel:  CGFloat = 0.62  // cover card size (relative to min side)
    private let recordSizeRel: CGFloat = 0.58  // record diameter (slightly smaller than cover)

    // World angles (0° = right, +90° = up, -90° = down)
    private let restAngle: Double = -90     // arm down (perpendicular)
    private let playAngle: Double = -55     // tilts onto record
    private let minAngle:  Double = -56     // clamp inward
    private let maxAngle:  Double = -100    // clamp outward

    private let degPerFrame: Double = 0.55  // rotation speed

    @State private var armDeg = -90.0
    @State private var rotation = 0.0
    @State private var wasOnDisc = false

    private let timer = Timer.publish(every: 1/60, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width
            let H = geo.size.height
            let S = min(W, H)

            // sizes and positions
            let coverSide      = S * coverSizeRel
            let recordDiameter = S * recordSizeRel
            let recordRadius   = recordDiameter / 2
            let recordCenter   = CGPoint(x: W * 0.68, y: H * 0.58)

            // tonearm geometry (pivot up-right from record)
            let pivot      = CGPoint(x: recordCenter.x + recordRadius * 0.92,
                                     y: recordCenter.y - recordRadius * 0.70)
            let armLength  = recordRadius * 1.12
            let armWidth   = max(2.0, recordDiameter * 0.018)

            ZStack {
                // Background: blurred cover or gradient
                if let cover {
                    cover.resizable().scaledToFill()
                        .frame(width: W, height: H).clipped()
                        .blur(radius: 18).saturation(0.95)
                        .overlay(
                            LinearGradient(colors: [.black.opacity(0.20), .black.opacity(0.45)],
                                           startPoint: .top, endPoint: .bottom)
                        )
                        .ignoresSafeArea()
                } else {
                    LinearGradient(colors: [.black, .gray],
                                   startPoint: .top, endPoint: .bottom)
                        .ignoresSafeArea()
                }

                // Optional big cover card on the left
                if showCoverCard, let cover {
                    cover.resizable().scaledToFill()
                        .frame(width: coverSide, height: coverSide)
                        .clipped()
                        .cornerRadius(14)
                        .shadow(radius: 14)
                        .rotationEffect(.degrees(-2))
                        .position(x: W * 0.28, y: H * 0.62)
                        .zIndex(0)
                }

                // Record
                VinylRecordView(art: cover, diameter: recordDiameter, rotationDeg: rotation)
                    .position(recordCenter)
                    .shadow(radius: 12)
                    .zIndex(1)

                // Tonearm (pivot is fixed; stylus swings)
                MPTonearmView(worldAngle: armDeg, length: armLength, thickness: armWidth)
                    .position(pivot)
                    .shadow(radius: 3)
                    .contentShape(Rectangle().inset(by: -44))
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                // vector from pivot to finger
                                let v = CGPoint(x: value.location.x - pivot.x,
                                                y: value.location.y - pivot.y)
                                // 0°=right, +90°=up, -90°=down
                                var deg = Double(atan2(v.y, v.x) * 180 / .pi)
                                deg = max(minAngle, min(maxAngle, deg))
                                armDeg = deg

                                // stylus tip position
                                let tip  = tipPoint(pivot: pivot, deg: armDeg, length: armLength)
                                let dist = hypot(tip.x - recordCenter.x, tip.y - recordCenter.y)

                                // hit zone (avoid label/edge)
                                let onDisc = (dist > recordRadius * 0.70) && (dist < recordRadius * 1.02)

                                // OFF → ON
                                if onDisc && !wasOnDisc {
                                    wasOnDisc = true
                                    if !playing {
                                        playing = true
                                        if !SpotifyManager.shared.isConnected {
                                            SpotifyManager.shared.connect()
                                        }
                                        SpotifyManager.shared.resume()
                                    }
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                }

                                // ON → OFF
                                if !onDisc && wasOnDisc {
                                    wasOnDisc = false
                                    if playing {
                                        playing = false
                                        SpotifyManager.shared.pause()
                                    }
                                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                                }
                            }
                            .onEnded { _ in
                                let tip  = tipPoint(pivot: pivot, deg: armDeg, length: armLength)
                                let dist = hypot(tip.x - recordCenter.x, tip.y - recordCenter.y)
                                let onDisc = (dist > recordRadius * 0.70) && (dist < recordRadius * 1.02)

                                withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                                    armDeg = onDisc ? playAngle : restAngle
                                }
                                wasOnDisc = onDisc

                                if onDisc && !playing {
                                    playing = true
                                    if !SpotifyManager.shared.isConnected {
                                        SpotifyManager.shared.connect()
                                    }
                                    SpotifyManager.shared.resume()
                                } else if !onDisc && playing {
                                    playing = false
                                    SpotifyManager.shared.pause()
                                }
                            }
                    )
                    .onTapGesture {
                        // simple toggle by tapping the arm
                        let goingToPlay = abs(armDeg - restAngle) < 10
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                            armDeg = goingToPlay ? playAngle : restAngle
                        }
                        if goingToPlay { playing = true;  SpotifyManager.shared.resume() }
                        else           { playing = false; SpotifyManager.shared.pause() }
                    }
                    .zIndex(2)
            }
            .onReceive(timer) { _ in
                guard playing else { return }
                rotation = (rotation + degPerFrame).truncatingRemainder(dividingBy: 360)
            }
            .onChange(of: playing) { _, now in
                withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                    armDeg = now ? playAngle : restAngle
                }
            }
            .onAppear { armDeg = playing ? playAngle : restAngle }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    // stylus tip in world coords
    private func tipPoint(pivot: CGPoint, deg: Double, length: CGFloat) -> CGPoint {
        let rad = deg * .pi / 180.0
        let dx  = CGFloat(cos(rad)) * length
        let dy  = CGFloat(sin(rad)) * length
        return CGPoint(x: pivot.x + dx, y: pivot.y + dy)
    }
}

// MARK: - Pieces

private struct VinylRecordView: View {
    let art: Image?
    let diameter: CGFloat
    let rotationDeg: Double

    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [.black.opacity(0.9), .black.opacity(0.72)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))

            Grooves()
                .stroke(style: StrokeStyle(lineWidth: 0.6))
                .foregroundStyle(.white.opacity(0.08))

            if let art {
                art.resizable().scaledToFill()
                    .frame(width: diameter * 0.36, height: diameter * 0.36)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(.black.opacity(0.5), lineWidth: 2))
            } else {
                Circle().fill(.gray.opacity(0.4))
                    .frame(width: diameter * 0.36, height: diameter * 0.36)
            }

            Circle().fill(.black.opacity(0.85))
                .frame(width: diameter * 0.06, height: diameter * 0.06)
        }
        .frame(width: diameter, height: diameter)
        .rotationEffect(.degrees(rotationDeg))
    }
}

/// Tonearm drawn pointing straight DOWN by default; we rotate by the world angle internally.
/// Anchor is `.top` so the top cap is the hinge/pivot.
private struct MPTonearmView: View {
    let worldAngle: Double
    let length: CGFloat
    let thickness: CGFloat

    var body: some View {
        ZStack(alignment: .top) {
            // Hinge cover (clear acrylic)
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: thickness * 3.2, height: thickness * 3.2)

            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: thickness/2)
                    .fill(.gray.opacity(0.95))
                    .frame(width: thickness, height: length)

                RoundedRectangle(cornerRadius: thickness * 0.35)
                    .fill(.black.opacity(0.9))
                    .frame(width: thickness * 1.6, height: thickness * 0.9)

                Capsule()
                    .fill(.black)
                    .frame(width: thickness * 0.6, height: thickness * 0.6)
                    .offset(y: 2)
            }
            .offset(y: thickness * 1.6)
        }
        // Our drawing points DOWN by default (-90 world). Convert for rotation.
        .rotationEffect(.degrees(worldAngle + 90), anchor: .top)
    }
}

private struct Grooves: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let R = min(rect.width, rect.height) / 2
        stride(from: R*0.22, through: R*0.98, by: 3.8).forEach { r in
            p.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r*2, height: r*2))
        }
        return p
    }
}
