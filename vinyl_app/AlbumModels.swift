import Foundation

// MARK: - Small UI models (used throughout the app)

struct SPImage: Identifiable, Codable {
    var id: String { url }
    let url: String
    let height: Int?
    let width: Int?
}

struct SPArtist: Codable {
    let name: String
}

struct SPAlbum: Identifiable, Codable {
    let id: String
    let name: String
    let images: [SPImage]?
    let artists: [SPArtist]?
    // match convertFromSnakeCase decoding
    let totalTracks: Int?
    let releaseDate: String?
}

struct SPUser: Codable {
    let displayName: String?
}

struct SPPlaylist: Identifiable, Codable {
    let id: String
    let name: String
    let images: [SPImage]?
    let owner: SPUser?
}
// DTO for strict JSON decoding of playlists page
private struct SPPlaylistsPage: Decodable {
    let items: [SPPlaylist]
}
