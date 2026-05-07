# 🎵 Vinyl Deck

A beautiful iOS/iPadOS app that displays your Spotify album library as a 3D vinyl record shelf — physical album spines, a lit shelf surface, and a fully animated vinyl player.

---

## What it looks like

- **Home screen** — Your albums arranged on a dark shelf like a real record store. Cards have 3D spines with the album name printed vertically, a lit top-edge shelf surface, and Netflix-style fan scroll.
- **Player screen** — A tonearm vinyl deck where the record slides out of the sleeve and spins while your track plays via Spotify.

---

## Requirements

| Tool | Version |
|------|---------|
| Mac | macOS 14 Sonoma or later |
| Xcode | 16.0 or later (free from Mac App Store) |
| iOS target | iOS 17+ (iPhone or iPad, or Simulator) |
| Spotify app | Installed on the device you run it on |

---

## Setup — Step by Step

### 1. Clone the repo

```bash
git clone https://github.com/dhruvbareja/vinyl-deck.git
cd vinyl-deck
```

### 2. Open in Xcode

Double-click `vinyl_app.xcodeproj`
Xcode will automatically download the Spotify iOS SDK — wait for the progress bar at the top to finish (about 30 seconds).

### 3. Set your signing team

1. In the left sidebar click the **vinyl_app** project (top item, blue icon)
2. Click the **vinyl_app** target under TARGETS
3. Go to **Signing & Capabilities** tab
4. Under **Team** — if it says None, click it and select **Add Account**
5. Sign in with any **Apple ID** (free — no paid developer account needed for Simulator)
6. Select your name from the Team dropdown

### 4. Pick a device

In the toolbar at the top, click the device picker and choose:
- Any **iPhone or iPad Simulator** (free, no device needed), OR
- Your **physical iPhone/iPad** plugged in via USB

### 5. Run it

Press **▶ (the Play button)** or hit `Cmd + R`

The app will launch. You'll see the vinyl shelf with a built-in demo library — no Spotify login needed to browse it.

---

## Connecting your Spotify library

To load your real Spotify albums:

1. The Spotify app **must be installed** on the same device
2. In the app, tap **Login with Spotify**
3. Authorize in the browser that opens
4. Your full album library loads into the shelf

> **Note:** The app uses a shared Spotify Client ID. To log in with your Spotify account, ask the repo owner to whitelist your Spotify email at [developer.spotify.com](https://developer.spotify.com) → their app → Settings → User Management.
> OR create your own free Spotify developer app (see below).

---

## Using your own Spotify Developer credentials (optional)

If you want full independence from the owner's Spotify app:

1. Go to [developer.spotify.com/dashboard](https://developer.spotify.com/dashboard) and log in
2. Click **Create App**
3. Fill in any name/description
4. Set **Redirect URI** to exactly: `vinylplayer://callback`
5. Save and copy your **Client ID**
6. Open `vinyl-app-Info.plist` in Xcode
7. Replace the value for `SPOTIFY_CLIENT_ID` with your new Client ID

---

## What's been built

- **3D album cases** — spine panel with rotated album/artist text, back plate peek, thickness edge, baked lighting and paper texture overlay on cover art
- **Shelf carousel** — Netflix-style horizontal scroll: center card full size, side cards fan outward and drop down, smooth spring snap-to-center
- **Shelf surface** — Lit top edge + dark polished face + floor shadow, spans full screen width
- **Floating header** — "Record Room" title and counter float directly on the ambient background, no box/card
- **Ambient background** — Blurred album art + radial palette glow that cross-fades as you scroll
- **Vinyl player** — Tonearm view, spinning disc, record slides out of sleeve animation, playback controls via Spotify SDK
- **Demo mode** — Built-in album library works without any Spotify login

---

## Project structure

```
vinyl_app/
├── AlbumCoverFlowView.swift   # Shelf home screen + 3D album card rendering
├── ContentView.swift          # App navigation (login → shelf → player)
├── VinylNowPlayingView.swift  # Vinyl player screen
├── MDVinylDeckView.swift      # Spinning disc + tonearm component
├── SpotifyManager.swift       # Spotify playback SDK integration
├── SpotifyWebAuth.swift       # Spotify Web API OAuth (album loading)
├── AlbumService.swift         # Fetches saved albums from Spotify API
├── DemoLibrary.swift          # Built-in demo albums (no login required)
├── AppConfig.swift            # Reads Spotify keys from Info.plist
├── GeminiService.swift        # Gemini AI integration (optional)
Config/
├── TargetDebug.xcconfig       # Build settings (team ID intentionally blank)
├── TargetRelease.xcconfig
vinyl-app-Info.plist           # Spotify Client ID + URL scheme config
```

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| "Missing package product 'SpotifyiOS'" | Wait for Xcode to finish resolving packages, or File → Packages → Resolve Package Versions |
| "No account for team" | Xcode → Settings → Accounts → + → Apple ID |
| Spotify login fails / redirect doesn't work | Make sure your Spotify email is whitelisted on the developer dashboard, and the Spotify app is installed |
| Build succeeds but app crashes immediately | Check that `SPOTIFY_CLIENT_ID` in `vinyl-app-Info.plist` is not empty |
| Workspace arena folder error | In Xcode: Product → Clean Build Folder (Cmd+Shift+K), then build again |
