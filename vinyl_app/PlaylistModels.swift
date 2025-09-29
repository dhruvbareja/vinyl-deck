import Foundation

// Images on a playlist; may be empty or null in the API
struct SPImage: Decodable {
    let url: String
    let height: Int?
    let width: Int?
}

// Playlist owner (note the CodingKeys for display_name)
struct SPUser: Decodable {
    let displayName: String?
    enum CodingKeys: String, CodingKey { case displayName = "display_name" }
}

// The playlist itself
struct SPPlaylist: Identifiable, Decodable {
    let id: String
    let name: String
    let images: [SPImage]?   // <-- optional, because some items return null
    let owner: SPUser?
}

// A page of playlists returned by /v1/me/playlists
struct SPPlaylistsPage: Decodable {
    let items: [SPPlaylist]
}//
//  PlaylistModels.swift
//  vinyl_app
//
//  Created by Dhruv bareja on 29/09/25.
//

