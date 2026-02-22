# SwiftUI Performance Analysis: Scroll & View Recomposition

Focus: **scroll animations** and **view recomposition** bottlenecks in the vinyl app.

---

## 1. Scroll-related bottlenecks

### 1.1 GeometryReader inside every carousel cell (high impact)

**File:** `AlbumCoverFlowView.swift` (lines 222–266)

```swift
ScrollView(.horizontal, ...) {
    HStack(spacing: spacing) {
        ForEach(Array(albums.enumerated()), id: \.element.id) { i, album in
            GeometryReader { cardGeo in
                let cardMidX = cardGeo.frame(in: .named("AlbumCarouselSpace")).midX
                let distance = (cardMidX - (visibleWidth / 2.0))
                // ... tiltDegrees, scale, alpha, yOffset from progress
                VStack { EnhancedAlbumCard(...) }
                    .rotation3DEffect(.degrees(tiltDegrees), ...)
                    .scaleEffect(scale)
                    .opacity(alpha)
                    ...
            }
            .frame(...)
        }
    }
}
```

**Issue:** Each visible cell has its own `GeometryReader`. During scroll, `cardGeo.frame(in: .named(...))` changes continuously, so **every visible card’s `body` is re-evaluated on every scroll update**. That means:

- Many `EnhancedAlbumCard` bodies (with 3D case, spine, reflections, overlays) recompute at scroll rate.
- Tilt, scale, opacity, and shadow are recalculated per frame from `progress`.

**Recommendations:**

- Prefer a **single** `GeometryReader` (or `ScrollView` + `scrollPosition`) and pass progress/distance into each card, or use a single overlay that reads scroll offset and computes which index is “center” and progress.
- Or use **`LazyHStack`** so only visible items are in the hierarchy, and give cards **stable identity** (e.g. `id: album.id`) so SwiftUI doesn’t recreate views unnecessarily.
- Consider **reducing work per card**: move heavy overlays (e.g. Canvas textures) into subviews that are not dependent on scroll-derived values, or cache their output.

---

### 1.2 No layer flattening on carousel cards

**File:** `AlbumCoverFlowView.swift` — `EnhancedAlbumCard` (lines 416–434)

Cards use `rotation3DEffect`, `scaleEffect`, `opacity`, `shadow`, and a deep hierarchy (BackPlate, ThicknessEdge, FrontCover, SpinePanel, ReflectionView, etc.) but **no `.drawingGroup()` or `.compositingGroup()`** on the card container.

**Issue:** During scroll, each card is re-rendered with full 3D and blending. That increases GPU work and can cause stutter when many cards are on screen.

**Recommendation:** Apply `.compositingGroup()` (and, if needed, `.drawingGroup(opaque: false)`) to the **card container** (e.g. the `ZStack` that holds the 3D case + reflection) so the card is rasterized once per frame instead of re-blending every subview during scroll.

---

### 1.3 ScrollView + DragGesture and index updates

**File:** `AlbumCoverFlowView.swift` (lines 281–311)

A `DragGesture` is attached to the whole `ScrollView` and updates `index` in `onEnded`, then calls `proxy.scrollTo(index, anchor: .center)` inside `withAnimation(...)`.

**Issue:** Changing `index` triggers:

- `BackgroundView` (`.task(id: currentIndex)`, `.animation(..., value: currentIndex)`).
- Every `EnhancedAlbumCard` that uses `isCenter: i == index` (scale, shadow, animation).
- `NavigationDots` (`.animation(..., value: current)` on each dot).

So a **single** scroll end causes a **broad** recomposition and animation pass.

**Recommendation:** Keep `index` for “selected” semantics, but avoid driving **scroll-position-dependent visuals** from `index` where possible. If you move to a single scroll-position reader, you can derive “center index” and “progress” from that and animate only the visuals that truly depend on them, reducing the number of views that get `.animation(..., value: currentIndex)`.

---

### 1.4 BackgroundView animation on index change

**File:** `AlbumCoverFlowView.swift` (lines 324–361)

```swift
if let image = blurredBg {
    Image(uiImage: image)
        ...
        .animation(.easeInOut(duration: 0.8), value: currentIndex)
}
```

**Issue:** When `currentIndex` changes, the entire blurred background is animated. Large blurred images are expensive; animating them for 0.8s increases GPU and compositing cost.

**Recommendation:** Crossfade with opacity only, or use a shorter duration. Prefer not animating the blur radius or the image size; keep the animation to opacity/transition if possible.

---

## 2. View recomposition bottlenecks

### 2.1 60 fps Timer driving full deck body

**File:** `MDVinylDeckView.swift` (lines 104–105, 302–313)

```swift
private let timer = Timer.publish(every: 1/60, on: .main, in: .common).autoconnect()
// ...
.onReceive(timer) { _ in
    // lerp rotationSpeed, update rotation
    rotation = (rotation + rotationSpeed).truncatingRemainder(dividingBy: 360)
}
```

**Issue:** Every 1/60 s, `rotation` (and possibly `rotationSpeed`) are updated. These are `@State`, so **the whole `MDVinylDeckView` body is re-evaluated 60 times per second**. That body includes:

- A top-level `GeometryReader`.
- `VinylRecordView(art: cover, diameter: recordSide, rotationDeg: rotation)` and its entire subtree (dozens of overlays, two `NoiseDepthOverlay` usages, Canvas-based views, etc.).
- Tonearm overlay with `MPTonearmView(worldAngle: armDeg, ...)`.

So **scroll** isn’t the only source of recomposition here; the **timer** causes constant recomposition of the heaviest view in the app.

**Recommendations:**

- **Throttle updates:** e.g. update `rotation` at 30 fps, or only when `rotationSpeed != 0` and use a display link or a timer that you invalidate when paused.
- **Isolate rotation:** Put only the **rotating content** (e.g. the vinyl disc) in a child view that takes `rotation` as a parameter, and ensure the rest of the deck (tonearm, background, cover card) does **not** depend on `rotation`, so they don’t recompose every frame.
- Consider **CADisplayLink** or **TimelineView(.animation)** for smoother, display-synced updates without forcing the entire deck body to run 60 times per second.

---

### 2.2 VinylRecordView body cost (rotation-driven)

**File:** `MDVinylDeckView.swift` — `VinylRecordView` (lines 568–899)

`VinylRecordView` receives `rotationDeg: Double` and uses it in:

- `.rotationEffect(.degrees(rotationDeg))` (main disc).
- `NoiseDepthOverlay(diameter: diameter, rotationDeg: rotationDeg, seed: 7)` and `seed: 11`.
- `ShimmerBands()`, angular gradients, `SpecularBandOverlay`, `LabelParallax`, etc., many with `.rotationEffect(.degrees(rotationDeg * ...))`.

So **every timer tick** that updates `rotation` causes this entire view to be re-evaluated.

**Additional cost in body:**

- **`art?.asUIImage()`** (line 402, 419, 456, etc.): If `art` is a SwiftUI `Image`, this can use `ImageRenderer` and do work on the main thread.
- **`dominantHueGradient(from: art?.asUIImage())`** (line 428): Calls `averageColor` (CIAreaAverage or similar) in body — main-thread and expensive.
- **`applyVintageFilter(to: ui)`** (lines 402–418): Core Image filter in the view that displays the tint; if this path is hit, it runs during body.

**Recommendations:**

- **Cache** the result of `art?.asUIImage()` and `dominantHueGradient` (e.g. in a small wrapper view or `@State` / view model) so they are not recomputed every frame.
- Move **vintage filter** and **average color** off the main thread and cache results; show a placeholder or previous image until the new one is ready.
- Ensure **NoiseDepthOverlay** (see below) doesn’t do heavy work per frame even when only `rotationDeg` changes.

---

### 2.3 NoiseDepthOverlay and rotation

**File:** `MDVinylDeckView.swift` (lines 1039–1083)

`NoiseDepthOverlay` uses a **GeometryReader** and a **static cache** keyed by size and seed. The **noise image** is cached, but the **view body** still runs every time the parent re-renders (e.g. every timer tick) and applies:

- `.rotationEffect(.degrees(rotationDeg * 0.6))`
- `.colorMultiply(...)`, `.blur(radius: 18)`, etc.

So the **view tree** is recomposed 60 times per second even though the underlying image is cached.

**Recommendation:** The caching is good; ensure the **parent** of `NoiseDepthOverlay` (i.e. the rotating disc subtree) is the **smallest possible view** that depends on `rotation`, so that only the disc + overlays that need rotation are recomposed, not the entire `MDVinylDeckView`. Combined with timer throttling or isolating rotation (see 2.1), this reduces cost.

---

### 2.4 ObservableObject and PlayerScreen / ContentView

**Files:** `ContentView.swift`, `AlbumCoverFlowView.swift`

- **ContentView:** `@StateObject private var spotify = SpotifyManager.shared` and `@ObservedObject private var auth = SpotifyWebAuth.shared`. Any `@Published` change in `SpotifyManager` or `SpotifyWebAuth` can recompose `ContentView` and thus the current screen.
- **PlayerScreen:** Uses `spotify.albumArt`, `spotify.trackName`, `spotify.artistName`, and `spotify.isPlaying` (via `playing` binding). If `SpotifyManager` publishes frequently (e.g. progress or artwork updates), **PlayerScreen** recomposes often.
- **AlbumCoverFlowView:** `@ObservedObject var auth`, `@StateObject var service`. Auth or service updates recompose the whole cover flow.

**Recommendation:** Prefer **finer-grained** observation: e.g. pass only the needed values (album art, track name, playing state) into child views as plain `let`/`Binding`, and have a thin container that subscribes to the manager. That way, only the views that actually use the changed property recompose. Also consider combining or throttling updates from the manager so it doesn’t publish at high frequency (e.g. progress every 0.5 s instead of every 0.1 s).

---

### 2.5 Animation modifiers applied broadly

**File:** `AlbumCoverFlowView.swift`

- **Enhanced3DCoverflow** (line 385): `.animation(.interactiveSpring(...), value: currentIndex)` — every view with this modifier re-animates when `currentIndex` changes.
- **NavigationDots** (line 412): `.animation(.spring(...), value: current)` on each dot.
- **EnhancedAlbumCard** (line 434): `.animation(.spring(...), value: isCenter)`.

**Issue:** When `index`/`currentIndex`/`isCenter` changes, many views get animation transactions and recomposition at once, which can cause a brief spike.

**Recommendation:** Attach `.animation(...)` only to the specific view(s) that need to animate (e.g. scale or opacity of the center card), not to the whole modifier or every dot. Prefer `withAnimation` at the call site for one-off transitions instead of implicit animation on a broad value.

---

## 3. Other notable costs (shorter)

- **PlayerScreen background:** `Image(uiImage: bg).blur(radius: 40)` — large blur is expensive; consider a pre-blurred cached image or smaller radius.
- **VinylRecordView:** Many **Canvas** overlays (PaperTexture, DustOverlay, HairlineScratchesOverlay, etc.). Each Canvas is re-invoked when the view updates; with 60 fps timer, that’s 60 Canvas draws per second for the disc. Consider caching their output to an image when diameter/seed don’t change.
- **Duplicate “record.circle” button** in `HeaderView` (lines 328–339 and 368–379) — minor, but any state change re-renders both.

---

## 4. Summary table

| Area              | Issue                              | Impact        | Fix direction                          |
|-------------------|-------------------------------------|---------------|----------------------------------------|
| Carousel scroll   | GeometryReader per cell             | High          | One reader or scrollPosition; LazyHStack |
| Carousel cards    | No compositingGroup/drawingGroup     | Medium        | Flatten card layer                     |
| Deck              | 60 fps timer → full body            | High          | Throttle; isolate rotation subtree     |
| VinylRecordView   | rotation + art/asUIImage in body    | High          | Cache; move CI/avg color off body      |
| NoiseDepthOverlay | Parent re-renders every frame       | Medium        | Smaller rotation-dependent subtree    |
| ObservableObject  | SpotifyManager/auth in root         | Medium        | Finer-grained observation              |
| Scroll + index    | index drives many animations        | Medium        | Derive from scroll; narrow animation   |

---

## 5. Suggested order of work

1. **Timer and deck:** Throttle or pause timer when not playing; isolate `rotation` so only the disc view (and its overlays) depend on it.
2. **VinylRecordView:** Cache `asUIImage()` and `dominantHueGradient`; move vintage filter and average color off the main thread.
3. **Carousel:** Replace per-cell `GeometryReader` with a single scroll-position source and pass progress into cards; add `.compositingGroup()` (and optionally `.drawingGroup()`) to the card.
4. **ObservableObject:** Reduce and narrow observation so only views that need changed data recompose.
5. **Animations:** Restrict `.animation(..., value: currentIndex)` to the minimal set of views that must animate.

This order targets the largest recomposition and scroll costs first (timer + disc, then carousel), then cleans up observation and animation scope.
