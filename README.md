# Floor Plan Studio (Drawww)

A freeform, infinite-canvas iPad app for drawing interior room layouts with Apple Pencil. Measurements display live as you draw, in your chosen unit system. Think Excalidraw meets a tape measure.

## What It Does

You launch the app and you're immediately on a canvas — no onboarding, no sign-up wall. Pick your unit system (ft/in or m/cm), grab the wall tool, and start drawing with Apple Pencil. As your stroke extends, a live dimension label follows the line updating every frame. Release to commit the segment, and snap guides appear for alignment. Pan and zoom with your fingers. Export a to-scale PDF when you're done.

## Architecture

```
Drawww/
├── DrawwwApp.swift                 # App entry point, SwiftData container setup
├── ContentView.swift               # Root view — auto-creates default project, launches editor
│
├── Models/
│   ├── FloorPlanProject.swift      # SwiftData models + UnitSystem formatting
│   └── CanvasState.swift           # Observable canvas state (tools, viewport, undo/redo)
│
├── Engine/
│   ├── SnapEngine.swift            # Endpoint snapping, axis locking, extension guides
│   └── GeometryEngine.swift        # Hit testing, intersections, room area detection
│
├── Views/
│   ├── FloorPlanEditorView.swift   # Main editor composing canvas + toolbar + overlays
│   ├── Canvas/
│   │   ├── FloorPlanCanvasView.swift   # Orchestrates drawing lifecycle with snapping
│   │   ├── CanvasRenderer.swift        # Core Graphics rendering (grid, walls, labels, guides)
│   │   └── CanvasGestureView.swift     # UIKit layer separating Pencil from finger input
│   └── Toolbar/
│       ├── ToolPaletteView.swift       # Floating left-side tool palette
│       ├── TopBarView.swift            # Top bar (undo/redo, units, grid, zoom, export)
│       └── ScaleCalibrationSheet.swift # Scale presets + custom reference line calibration
│
├── Export/
│   └── PDFExporter.swift           # To-scale PDF generation with labels and room areas
│
└── Assets.xcassets/                # App icons, accent color
```

### Rendering Strategy (Hybrid)

The app uses a hybrid rendering approach, which is a deliberate architectural decision:

**Core Graphics (via SwiftUI Canvas)** handles all structured geometry — walls, measurement labels, grid, snap guides, room area labels. This gives us precise control over line weights, hit testing, and coordinate transforms that PencilKit can't provide for structured floor plan elements.

**PencilKit** is reserved for the freeform annotation layer only (Phase 2), where native ink feel matters and structured geometry doesn't.

This separation means walls are always vector data with exact coordinates, not ink strokes that need interpretation.

### Input Model

The `CanvasGestureView` is a `UIViewRepresentable` wrapping a custom `UIView` subclass that discriminates touch types at the lowest level:

- **Apple Pencil** (`UITouch.TouchType.pencil/stylus`) → forwarded to drawing handlers with predicted touches for low latency
- **Direct touch (finger)** → left for `UIPanGestureRecognizer` (one-finger pan) and `UIPinchGestureRecognizer` (two-finger zoom)

This means pencil never accidentally pans the canvas, and fingers never accidentally draw walls.

### Data Flow

```
User draws with Pencil
    → CanvasGestureView (UIKit touch discrimination)
    → FloorPlanCanvasView (drawing handlers)
    → SnapEngine (endpoint snap, axis lock, guides)
    → WallSegment created (SwiftData @Model)
    → CanvasState updated (undo stack, guide lines)
    → CanvasRenderer re-draws (SwiftUI Canvas)
    → SwiftData auto-persists
```

### Snap System

The `SnapEngine` runs on every pencil move event and applies three layers of snapping in priority order:

1. **Endpoint snapping** — new wall endpoint locks to existing wall endpoints within a threshold (adjusted for zoom level)
2. **Axis locking** — auto-locks to 0°, 45°, 90°, 135° based on pencil angle relative to the start point
3. **Extension guides** — dotted lines extend from existing wall endpoints to show horizontal/vertical alignment and wall direction continuity

### Geometry Engine

`GeometryEngine` handles the math-heavy operations:

- **Hit testing** — point-to-line-segment distance for wall selection
- **Wall intersection** — parametric line-line intersection for T-junctions
- **Room detection** — builds an adjacency graph from wall endpoints, finds minimal cycles (triangles, quads), calculates area via the shoelace formula, and places labels at polygon centroids

### Persistence

SwiftData with `@Model` classes. The project auto-saves continuously — no manual save button. The model hierarchy:

```
FloorPlanProject
├── walls: [WallSegment]        (start/end points, thickness)
├── dimensionLines: [DimensionLine]  (manual measurement annotations)
├── textLabels: [TextLabel]     (room names, notes)
├── unitSystem: .imperial | .metric
├── pointsPerRealUnit: Double   (scale factor)
└── viewport: offset + zoom     (restored on reopen)
```

All relationships use `.cascade` delete rules so removing a project cleans up everything.

## Current Status — Phase 1 MVP (Complete)

- [x] Infinite canvas with pan/zoom
- [x] Wall tool with live measurements (updates every frame as you draw)
- [x] Unit toggle (imperial ft/in, metric m/cm) — applies globally, updates all labels instantly
- [x] Scale calibration (presets: 1"=1', 1/4"=1', 1/2"=1', 1cm=1m + custom reference line)
- [x] Snap to axis (0°/45°/90°) + endpoint snapping + extension guides
- [x] Select / move / delete walls
- [x] Undo / redo (per-action granularity)
- [x] Auto-save with SwiftData
- [x] PDF export (to-scale, with dimension labels, room areas, title block)
- [x] Tool palette: Wall, Select, Eraser, Annotate, Dimension, Label

## Roadmap

### Phase 2 — Usable for Kitchens & Bathrooms

- [ ] Door and window placement on walls (standard architectural symbols)
- [ ] Fixture library (sink, stove, fridge, toilet, tub, shower, island, cabinets)
- [ ] Room area auto-calculation displayed in room center
- [ ] Photo tracing background layer (import photo, set opacity, draw over)
- [ ] Project gallery with multiple plans
- [ ] PencilKit annotation pen + text labels
- [ ] Visual wall thickness rendering

### Phase 3 — Polish

- [ ] Custom fixture sizing
- [ ] Multiple layers (existing vs. planned)
- [ ] Dimension line tool (manual measurements between any two points)
- [ ] SVG export
- [ ] iCloud sync
- [ ] Templates (standard room sizes)
- [ ] Double-tap Pencil barrel to toggle last two tools (`UIPencilInteraction`)

## Tech Stack

| Layer | Choice | Why |
|-------|--------|-----|
| UI framework | SwiftUI + UIKit interop | SwiftUI for chrome, UIKit for canvas input performance |
| Canvas rendering | Core Graphics (SwiftUI Canvas) | Custom geometry + 60fps pencil tracking |
| Pencil input | UIGestureRecognizer + predicted touches | Low-latency, touch-type discrimination |
| Freeform strokes | PencilKit (Phase 2, annotation layer only) | Native ink feel for notes |
| Data persistence | SwiftData | Declarative, pairs with SwiftUI, auto-save |
| Undo/Redo | Custom action stack | Per-action granularity with redo support |
| Geometry math | Custom (hit testing, snapping, area calc) | simd/Accelerate-ready for performance |
| PDF export | UIGraphicsPDFRenderer | Native, to-scale output |

## Building

Open `Drawww.xcodeproj` in Xcode 26+ and build for iPad (simulator or device). No external dependencies — everything is first-party Apple frameworks.

The project uses `PBXFileSystemSynchronizedRootGroup` so Xcode auto-discovers all Swift files in the directory structure. No manual file reference management needed.

## Key Design Decisions

**Why not PencilKit for everything?** PencilKit gives you beautiful freeform ink, but walls need to be structured geometry with exact coordinates for measurements, snapping, and export to work. PencilKit strokes are opaque — you can't query "how long is this line" or "does this endpoint touch that wall." The hybrid approach gives us the best of both worlds.

**Why center-line walls (no thickness)?** Phase 1 uses zero-thickness center-line walls to keep the drawing and snapping logic simple. Visual wall thickness is a render-time option added in Phase 2 — the underlying data model already has a `thickness` property ready to go.

**Why SwiftData over Core Data?** Modern API, less boilerplate, native SwiftUI integration with `@Query` and `@Model`. The trade-off is it requires iOS 17+, which is fine for a new app.

**Why custom undo instead of UndoManager?** The action-based undo stack (`CanvasAction` enum) gives us explicit control over what's undoable and makes redo straightforward. It's also easier to serialize if we want persistent undo history later.
