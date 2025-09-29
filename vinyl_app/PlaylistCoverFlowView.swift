import SwiftUI
import Combine

struct PlaylistCoverFlowView: View {
    @ObservedObject var auth = SpotifyWebAuth.shared
    @StateObject var service = PlaylistService()

    let ns: Namespace.ID
    var onSelect: (SPPlaylist, UIImage?) -> Void

    @State private var index = 0

    var body: some View {
        VStack(spacing: 12) {
            Text("Your Playlists").font(.title3).bold()

            if let err = service.errorMessage {
                Text(err).font(.footnote).foregroundStyle(.secondary).frame(height: 24)
            } else {
                Spacer(minLength: 0).frame(height: 24)
            }

            GeometryReader { geo in
                let W = geo.size.width
                if service.playlists.isEmpty {
                    Group {
                        if auth.webAPIToken == nil { Text("Log in above to load playlists") }
                        else { ProgressView("Loading…") }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 22) {
                            ForEach(Array(service.playlists.enumerated()), id: \.element.id) { i, pl in
                                CoverCard(playlist: pl, width: W * 0.46, ns: ns) { image in
                                    onSelect(pl, image)
                                }
                                .rotation3DEffect(.degrees(Double(i - index) * 14),
                                                  axis: (x: 0, y: 1, z: 0),
                                                  perspective: 0.8)
                                .scaleEffect(i == index ? 1.0 : 0.92)
                                .animation(.easeInOut(duration: 0.2), value: index)
                                .onTapGesture { index = i }
                            }
                        }
                        .padding(.horizontal, (W * 0.27))
                    }
                    .gesture(
                        DragGesture().onEnded { v in
                            let dx = v.translation.width
                            if dx < -40 { index = min(index + 1, service.playlists.count - 1) }
                            if dx >  40 { index = max(index - 1, 0) }
                        }
                    )
                }
            }
            .frame(height: 360)
        }
        // You can keep the Combine operator, but this variant avoids it if needed:
        .onReceive(auth.$webAPIToken) { token in
            if let token { service.loadMyPlaylists(bearer: token) }
        }
        .onAppear {
            if let token = auth.webAPIToken, service.playlists.isEmpty {
                service.loadMyPlaylists(bearer: token)
            }
        }
    }
}

private struct CoverCard: View {
    let playlist: SPPlaylist
    let width: CGFloat
    let ns: Namespace.ID
    var onSelect: (UIImage?) -> Void

    @State private var ui: UIImage?

    var body: some View {
        let side = width
        VStack(spacing: 10) {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let ui {
                        Image(uiImage: ui)
                            .resizable()
                            .scaledToFill()
                            .matchedGeometryEffect(id: "cover", in: ns)
                    } else {
                        ZStack {
                            LinearGradient(colors: [.gray.opacity(0.25), .gray.opacity(0.4)],
                                           startPoint: .top, endPoint: .bottom)
                            Image(systemName: "opticaldisc")
                                .font(.system(size: 42)).opacity(0.35)
                        }
                    }
                }
                .frame(width: side, height: side * 1.15)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(radius: 10)

                Rectangle()
                    .fill(.black.opacity(0.22))
                    .frame(width: 12, height: side * 1.15)
                    .offset(x: -side/2 + 6)

                VStack(alignment: .leading, spacing: 2) {
                    Text(playlist.name).font(.headline).lineLimit(1).foregroundColor(.white)
                    if let owner = playlist.owner?.displayName {
                        Text(owner).font(.subheadline).foregroundColor(.white.opacity(0.85)).lineLimit(1)
                    }
                }
                .padding(10)
                .background(.ultraThinMaterial, in: Capsule())
                .offset(x: 12, y: -12)
            }
            .onTapGesture {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                onSelect(ui)
            }
        }
        .onAppear {
            if ui == nil, let urlStr = playlist.images?.first?.url,
               let url = URL(string: urlStr) {
                URLSession.shared.dataTask(with: url) { data, _, _ in
                    guard let data = data, let img = UIImage(data: data) else { return }
                    DispatchQueue.main.async { ui = img }
                }.resume()
            }
        }
    }
}
