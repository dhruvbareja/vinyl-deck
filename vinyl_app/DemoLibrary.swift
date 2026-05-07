import Foundation

enum DemoLibrary {
    static let albums: [SPAlbum] = [
        SPAlbum(
            id: "demo-surroor",
            name: "Surroor",
            images: [SPImage(url: "asset://surroor", height: nil, width: nil)],
            artists: [SPArtist(name: "Demo Artist")],
            totalTracks: 10,
            releaseDate: "2025-01-01"
        ),
        SPAlbum(
            id: "demo-goodvibes",
            name: "Good Vibes Only",
            images: [SPImage(url: "asset://goodvibes", height: nil, width: nil)],
            artists: [SPArtist(name: "Gajendra Verma")],
            totalTracks: 12,
            releaseDate: "2024-01-01"
        ),
        SPAlbum(
            id: "demo-onedirection",
            name: "One Direction",
            images: [SPImage(url: "asset://oneDirection", height: nil, width: nil)],
            artists: [SPArtist(name: "Demo Mix")],
            totalTracks: 14,
            releaseDate: "2023-01-01"
        )
    ]
}
