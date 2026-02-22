//
//  PreviewMocks.swift
//  vinyl_app
//
//  Created by Dhruv bareja on 20/10/25.
//

#if DEBUG
import SwiftUI
import UIKit
import Combine

// Minimal SPAlbum stub for preview (match real model fields used in view)
struct SPAlbumPreview: Identifiable {
    var id = UUID().uuidString
    var name: String
    var images: [PreviewImage]
    var artists: [PreviewArtist]?
    
    struct PreviewImage {
        let url: String
    }
    struct PreviewArtist { let name: String }
}

// A tiny mock AlbumService used by previews
final class MockAlbumService: ObservableObject {
    @Published var albums: [SPAlbumPreview] = []
    @Published var errorMessage: String? = nil
    
    init() {
        // create a few local assets names or remote small images if you want
        albums = [
            SPAlbumPreview(
                id: "1",
                name: "Surroor",
                images: [SPAlbumPreview.PreviewImage(url: "surroor")], // use xcasset name
                artists: [SPAlbumPreview.PreviewArtist(name: "Artist A")]
            ),
            SPAlbumPreview(
                id: "2",
                name: "Good Vibes Only",
                images: [SPAlbumPreview.PreviewImage(url: "goodvibes")],
                artists: [SPAlbumPreview.PreviewArtist(name: "Gajendra Verma")]
            )
        ]
    }
}
#endif
