import Foundation
import Combine

final class PlaylistService: ObservableObject {
    @Published var playlists: [SPPlaylist] = []
    @Published var errorMessage: String?

    func loadMyPlaylists(bearer token: String) {
        errorMessage = nil
        var req = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/playlists?limit=50")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: req) { data, _, err in
            if let err = err {
                DispatchQueue.main.async { self.errorMessage = err.localizedDescription }
                return
            }
            guard let data = data else {
                DispatchQueue.main.async { self.errorMessage = "No data" }
                return
            }

            do {
                // Primary strict decode
                let page = try JSONDecoder().decode(SPPlaylistsPage.self, from: data)
                DispatchQueue.main.async { self.playlists = page.items }
            } catch {
                // Fallback tolerant decode to handle odd/null images payloads
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let items = json["items"] as? [[String: Any]] {
                    let mapped: [SPPlaylist] = items.compactMap { dict in
                        guard let id = dict["id"] as? String,
                              let name = dict["name"] as? String else { return nil }

                        var imgs: [SPImage]? = nil
                        if let arr = dict["images"] as? [[String: Any]] {
                            imgs = arr.compactMap { im in
                                guard let url = im["url"] as? String else { return nil }
                                return SPImage(url: url,
                                               height: im["height"] as? Int,
                                               width:  im["width"]  as? Int)
                            }
                        }

                        var owner: SPUser? = nil
                        if let od = dict["owner"] as? [String: Any] {
                            owner = SPUser(displayName: od["display_name"] as? String)
                        }

                        return SPPlaylist(id: id, name: name, images: imgs, owner: owner)
                    }
                    DispatchQueue.main.async {
                        self.playlists = mapped
                        // optional: self.errorMessage = "Loaded with tolerant parser"
                    }
                } else {
                    let raw = String(data: data, encoding: .utf8) ?? ""
                    DispatchQueue.main.async {
                        self.errorMessage = "Decode failed: \(error.localizedDescription)\n\(raw.prefix(200))"
                    }
                }
            }
        }.resume()
    }
}
