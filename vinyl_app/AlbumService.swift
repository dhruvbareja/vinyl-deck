import Foundation
import Combine

/// UI-facing service lives on the main actor (safe @Published updates).
@MainActor
final class AlbumService: ObservableObject {
    @Published var albums: [SPAlbum] = []
    @Published var errorMessage: String?

    func loadMyAlbums(bearer token: String) {
        errorMessage = nil

        var req = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/albums?limit=50")!)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        // perform network + decode off the main actor
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let (data, _) = try await URLSession.shared.data(for: req)

                // Decode into lightweight DTOs
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let page = try decoder.decode(MyAlbumsPage.self, from: data)

                // ✅ YOUR MAPPING BLOCK GOES HERE
                let mapped: [SPAlbum] = page.items.map { saved in
                    let a = saved.album
                    let imgs: [SPImage]? = a.images?.map {
                        SPImage(url: $0.url, height: $0.height, width: $0.width)
                    }
                    let arts: [SPArtist]? = a.artists?.map { SPArtist(name: $0.name) }

                    return SPAlbum(
                        id: a.id,
                        name: a.name,
                        images: imgs,
                        artists: arts,
                        totalTracks: a.totalTracks,
                        releaseDate: a.releaseDate
                    )
                }

                // ✅ Hop back to the main actor to update UI state
                await MainActor.run {
                    self?.albums = mapped
                }

            } catch {
                // error handling — keeps your existing behavior
                await MainActor.run {
                    self?.errorMessage = "Failed to load albums: \(error.localizedDescription)"
                    #if DEBUG
                    print("❌ AlbumService decode error:", error)
                    #endif
                }
            }
        }
    }
}

// MARK: - DTOs (private decoding structs)
private struct MyAlbumsPage: Decodable {
    let items: [SavedAlbumDTO]
}

private struct SavedAlbumDTO: Decodable {
    let album: AlbumDTO
}

private struct AlbumDTO: Decodable {
    let id: String
    let name: String
    let images: [ImageDTO]?
    let artists: [ArtistDTO]?
    let totalTracks: Int?
    let releaseDate: String?
}

private struct ImageDTO: Decodable {
    let url: String
    let height: Int?
    let width: Int?
}

private struct ArtistDTO: Decodable {
    let name: String
}
