import SwiftUI
import SwiftData

/// The main infinite canvas view for drawing floor plans.
/// Handles Apple Pencil input, touch gestures, and renders all geometry.
struct FloorPlanCanvasView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var project: FloorPlanProject
    @Bindable var canvasState: CanvasState

    private let snapEngine = SnapEngine()

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()

                // Canvas renderer (grid, walls, shapes, measurements, guides)
                CanvasRenderer(
                    walls: project.walls,
                    draftingShapes: project.draftingShapes,
                    sectionCuts: project.sectionCuts,
                    heightMarkers: project.heightMarkers,
                    stairs: project.stairs,
                    hatchRegions: project.hatchRegions,
                    elevationArrows: project.elevationArrows,
                    canvasState: canvasState,
                    unitSystem: project.unitSystem,
                    scale: project.pointsPerRealUnit,
                    canvasSize: geometry.size
                )

                // PencilKit sketch layer (only interactive when sketch tool is active)
                if canvasState.activeTool == .sketch || canvasState.activeTool == .strokeEraser {
                    PencilKitCanvasView(
                        canvasDrawing: $canvasState.sketchDrawing,
                        isActive: .constant(true),
                        inkColor: .label,
                        inkWidth: 2.0,
                        isErasing: canvasState.activeTool == .strokeEraser
                    )
                    .allowsHitTesting(true)
                }

                // Gesture overlay (for non-sketch tools)
                if canvasState.activeTool != .sketch && canvasState.activeTool != .strokeEraser {
                    CanvasGestureView(
                        canvasState: canvasState,
                        canvasSize: geometry.size,
                        onPencilBegan: { handleDrawBegan($0, canvasSize: geometry.size) },
                        onPencilMoved: { handleDrawMoved($0, canvasSize: geometry.size) },
                        onPencilEnded: { handleDrawEnded($0, canvasSize: geometry.size) },
                        onTapAt: { handleTap($0, canvasSize: geometry.size) },
                        onPencilSqueeze: { handlePencilSqueeze($0) }
                    )
                }

                // Radial menu overlay
                if canvasState.showRadialMenu {
                    RadialMenuView(
                        canvasState: canvasState,
                        position: canvasState.radialMenuPosition,
                        onDismiss: { canvasState.showRadialMenu = false }
                    )
                    .transition(.opacity)
                    .zIndex(100)
                }
            }
        }
    }

    // MARK: - Pencil Pro Squeeze

    private func handlePencilSqueeze(_ point: CGPoint) {
        canvasState.radialMenuPosition = point
        withAnimation(.spring(response: 0.25)) {
            canvasState.showRadialMenu = true
        }
    }

    // MARK: - Drawing Handlers

    private func handleDrawBegan(_ screenPoint: CGPoint, canvasSize: CGSize) {
        let canvasPoint = canvasState.screenToCanvas(screenPoint, canvasSize: canvasSize)

        switch canvasState.activeTool {
        case .wall:
            startWallDraw(canvasPoint)
        case .line, .constructionLine:
            startLineDraw(canvasPoint)
        case .circle:
            startShapeDraw(canvasPoint)
        case .arc:
            startShapeDraw(canvasPoint)
        case .rectangle:
            startShapeDraw(canvasPoint)
        case .smartSketch:
            startSmartSketch(canvasPoint)
        case .sectionCut:
            startLineDraw(canvasPoint)
        case .objectEraser:
            handleErase(canvasPoint)
        case .strokeEraser:
            break // handled by PencilKitCanvasView in erasing mode
        case .select:
            handleSelect(canvasPoint)
        case .heightMarker:
            placeHeightMarker(canvasPoint)
        case .stairSymbol:
            placeStairSymbol(canvasPoint)
        case .elevationArrow:
            placeElevationArrow(canvasPoint)
        default:
            break
        }
    }

    private func handleDrawMoved(_ screenPoint: CGPoint, canvasSize: CGSize) {
        guard canvasState.isDrawing else { return }
        let canvasPoint = canvasState.screenToCanvas(screenPoint, canvasSize: canvasSize)

        switch canvasState.activeTool {
        case .wall:
            updateWallDraw(canvasPoint)
        case .line, .constructionLine, .sectionCut:
            updateLineDraw(canvasPoint)
        case .circle:
            updateCircleDraw(canvasPoint)
        case .arc:
            updateArcDraw(canvasPoint)
        case .rectangle:
            updateRectDraw(canvasPoint)
        case .smartSketch:
            collectSmartSketchPoint(canvasPoint)
        default:
            break
        }
    }

    private func handleDrawEnded(_ screenPoint: CGPoint, canvasSize: CGSize) {
        guard canvasState.isDrawing else { return }
        _ = canvasState.screenToCanvas(screenPoint, canvasSize: canvasSize)

        switch canvasState.activeTool {
        case .wall:
            commitWall()
        case .line:
            commitLine()
        case .constructionLine:
            commitConstructionLine()
        case .circle:
            commitCircle()
        case .arc:
            commitArc()
        case .rectangle:
            commitRectangle()
        case .smartSketch:
            commitSmartSketch()
        case .sectionCut:
            commitSectionCut()
        default:
            break
        }

        canvasState.clearDrawingState()
    }

    private func handleTap(_ screenPoint: CGPoint, canvasSize: CGSize) {
        let canvasPoint = canvasState.screenToCanvas(screenPoint, canvasSize: canvasSize)
        if canvasState.activeTool == .select {
            handleSelect(canvasPoint)
        }
    }

    // MARK: - Wall Drawing

    private func startWallDraw(_ point: SerializablePoint) {
        let snapped = snapEngine.snap(point: point, from: nil, existingWalls: project.walls, zoomLevel: Double(canvasState.viewportZoom))
        canvasState.isDrawing = true
        canvasState.drawingStartPoint = snapped.snappedPoint
        canvasState.drawingCurrentPoint = snapped.snappedPoint
    }

    private func updateWallDraw(_ point: SerializablePoint) {
        let snapped = snapEngine.snap(point: point, from: canvasState.drawingStartPoint, existingWalls: project.walls, zoomLevel: Double(canvasState.viewportZoom))
        canvasState.drawingCurrentPoint = snapped.snappedPoint
        canvasState.activeGuideLines = snapped.guideLines
    }

    private func commitWall() {
        guard let start = canvasState.drawingStartPoint,
              let end = canvasState.drawingCurrentPoint,
              start.distance(to: end) > 5 else { return }

        let wall = WallSegment(start: start, end: end)
        wall.project = project
        project.walls.append(wall)
        modelContext.insert(wall)
        canvasState.recordAction(.addWall(wall))
        project.touch()
    }

    // MARK: - Line Drawing (generic)

    private func startLineDraw(_ point: SerializablePoint) {
        let snapped = snapEngine.snap(point: point, from: nil, existingWalls: project.walls, zoomLevel: Double(canvasState.viewportZoom))
        canvasState.isDrawing = true
        canvasState.drawingStartPoint = snapped.snappedPoint
        canvasState.drawingCurrentPoint = snapped.snappedPoint
    }

    private func updateLineDraw(_ point: SerializablePoint) {
        let snapped = snapEngine.snap(point: point, from: canvasState.drawingStartPoint, existingWalls: project.walls, zoomLevel: Double(canvasState.viewportZoom))
        canvasState.drawingCurrentPoint = snapped.snappedPoint
        canvasState.activeGuideLines = snapped.guideLines
    }

    private func commitLine() {
        guard let start = canvasState.drawingStartPoint,
              let end = canvasState.drawingCurrentPoint,
              start.distance(to: end) > 5 else { return }

        let shape = DraftingShape.makeLine(
            from: start, to: end,
            style: canvasState.lineProperties.style,
            weight: canvasState.lineProperties.weight
        )
        shape.project = project
        project.draftingShapes.append(shape)
        modelContext.insert(shape)
        canvasState.recordAction(.addDraftingShape(shape))
        project.touch()
    }

    private func commitConstructionLine() {
        guard let start = canvasState.drawingStartPoint,
              let end = canvasState.drawingCurrentPoint,
              start.distance(to: end) > 5 else { return }

        let shape = DraftingShape.makeConstructionLine(from: start, to: end)
        shape.project = project
        project.draftingShapes.append(shape)
        modelContext.insert(shape)
        canvasState.recordAction(.addDraftingShape(shape))
        project.touch()
    }

    // MARK: - Shape Drawing

    private func startShapeDraw(_ point: SerializablePoint) {
        canvasState.isDrawing = true
        canvasState.drawingStartPoint = point
        canvasState.drawingCurrentPoint = point
    }

    private func updateCircleDraw(_ point: SerializablePoint) {
        canvasState.drawingCurrentPoint = point
    }

    private func updateArcDraw(_ point: SerializablePoint) {
        canvasState.drawingCurrentPoint = point
    }

    private func updateRectDraw(_ point: SerializablePoint) {
        let snapped = snapEngine.snap(point: point, from: canvasState.drawingStartPoint, existingWalls: project.walls, zoomLevel: Double(canvasState.viewportZoom))
        canvasState.drawingCurrentPoint = snapped.snappedPoint
    }

    private func commitCircle() {
        guard let center = canvasState.drawingStartPoint,
              let edge = canvasState.drawingCurrentPoint else { return }
        let radius = center.distance(to: edge)
        guard radius > 5 else { return }

        let shape = DraftingShape.makeCircle(
            center: center, radius: radius,
            style: canvasState.lineProperties.style,
            weight: canvasState.lineProperties.weight
        )
        shape.project = project
        project.draftingShapes.append(shape)
        modelContext.insert(shape)
        canvasState.recordAction(.addDraftingShape(shape))
        project.touch()
    }

    private func commitArc() {
        guard let center = canvasState.drawingStartPoint,
              let edge = canvasState.drawingCurrentPoint else { return }
        let radius = center.distance(to: edge)
        guard radius > 5 else { return }

        let startAngle = center.angle(to: edge)
        let shape = DraftingShape.makeArc(
            center: center, radius: radius,
            startAngle: startAngle,
            endAngle: startAngle + .pi, // half circle default
            weight: canvasState.lineProperties.weight
        )
        shape.project = project
        project.draftingShapes.append(shape)
        modelContext.insert(shape)
        canvasState.recordAction(.addDraftingShape(shape))
        project.touch()
    }

    private func commitRectangle() {
        guard let start = canvasState.drawingStartPoint,
              let end = canvasState.drawingCurrentPoint else { return }
        let width = abs(end.x - start.x)
        let height = abs(end.y - start.y)
        guard width > 5 && height > 5 else { return }

        let origin = SerializablePoint(x: min(start.x, end.x), y: min(start.y, end.y))
        let shape = DraftingShape.makeRectangle(
            origin: origin, width: width, height: height,
            style: canvasState.lineProperties.style,
            weight: canvasState.lineProperties.weight
        )
        shape.project = project
        project.draftingShapes.append(shape)
        modelContext.insert(shape)
        canvasState.recordAction(.addDraftingShape(shape))
        project.touch()
    }

    // MARK: - Smart Sketch (shape recognition)

    private func startSmartSketch(_ point: SerializablePoint) {
        canvasState.isDrawing = true
        canvasState.smartSketchPoints = [point]
        canvasState.drawingStartPoint = point
        canvasState.drawingCurrentPoint = point
    }

    private func collectSmartSketchPoint(_ point: SerializablePoint) {
        canvasState.smartSketchPoints.append(point)
        canvasState.drawingCurrentPoint = point
    }

    private func commitSmartSketch() {
        let points = canvasState.smartSketchPoints
        guard points.count >= 2 else { return }

        let recognized = ShapeRecognizer.recognize(points: points)

        switch recognized {
        case .line(let start, let end):
            let shape = DraftingShape.makeLine(from: start, to: end,
                                                style: canvasState.lineProperties.style,
                                                weight: canvasState.lineProperties.weight)
            insertDraftingShape(shape)

        case .rectangle(let origin, let width, let height, let angle):
            let shape = DraftingShape.makeRectangle(origin: origin, width: width, height: height, angle: angle,
                                                     style: canvasState.lineProperties.style,
                                                     weight: canvasState.lineProperties.weight)
            insertDraftingShape(shape)

        case .circle(let center, let radius):
            let shape = DraftingShape.makeCircle(center: center, radius: radius,
                                                  style: canvasState.lineProperties.style,
                                                  weight: canvasState.lineProperties.weight)
            insertDraftingShape(shape)

        case .arc(let center, let radius, let startAngle, let endAngle):
            let shape = DraftingShape.makeArc(center: center, radius: radius,
                                               startAngle: startAngle, endAngle: endAngle,
                                               weight: canvasState.lineProperties.weight)
            insertDraftingShape(shape)

        case .triangle(let p1, let p2, let p3):
            let shape = DraftingShape.makeTriangle(p1: p1, p2: p2, p3: p3,
                                                    weight: canvasState.lineProperties.weight)
            insertDraftingShape(shape)

        case .lShape, .unrecognized:
            // Fall through — keep as freeform points, draw as connected lines
            if points.count >= 2 {
                for i in 0..<(points.count - 1) {
                    let shape = DraftingShape.makeLine(from: points[i], to: points[i + 1],
                                                        weight: .thin)
                    insertDraftingShape(shape)
                }
            }
        }
    }

    private func insertDraftingShape(_ shape: DraftingShape) {
        shape.project = project
        project.draftingShapes.append(shape)
        modelContext.insert(shape)
        canvasState.recordAction(.addDraftingShape(shape))
        project.touch()
    }

    // MARK: - Elevation Tools

    private func commitSectionCut() {
        guard let start = canvasState.drawingStartPoint,
              let end = canvasState.drawingCurrentPoint,
              start.distance(to: end) > 10 else { return }

        let sectionCut = SectionCutLine(start: start, end: end)
        sectionCut.project = project
        project.sectionCuts.append(sectionCut)
        modelContext.insert(sectionCut)
        canvasState.recordAction(.addSectionCut(sectionCut))
        project.touch()
    }

    private func placeHeightMarker(_ point: SerializablePoint) {
        let marker = HeightMarker(position: point)
        marker.project = project
        project.heightMarkers.append(marker)
        modelContext.insert(marker)
        canvasState.recordAction(.addHeightMarker(marker))
        project.touch()
    }

    private func placeStairSymbol(_ point: SerializablePoint) {
        let stair = StairSymbol(origin: point)
        stair.project = project
        project.stairs.append(stair)
        modelContext.insert(stair)
        canvasState.recordAction(.addStairSymbol(stair))
        project.touch()
    }

    private func placeElevationArrow(_ point: SerializablePoint) {
        let arrow = ElevationArrow(position: point, directionAngle: -.pi / 2, label: "A")
        arrow.project = project
        project.elevationArrows.append(arrow)
        modelContext.insert(arrow)
        project.touch()
    }

    // MARK: - Eraser & Select

    private func handleErase(_ point: SerializablePoint) {
        let threshold = 20.0 / Double(canvasState.viewportZoom)

        // Try walls first
        let nearWalls = GeometryEngine.wallsNearPoint(point, walls: project.walls, threshold: threshold)
        if let wall = nearWalls.first {
            canvasState.recordAction(.removeWall(wall))
            project.walls.removeAll { $0.id == wall.id }
            modelContext.delete(wall)
            project.touch()
            return
        }

        // Try drafting shapes (lines)
        for shape in project.draftingShapes where shape.shapeType == .line {
            let shapeStart = SerializablePoint(x: shape.x1, y: shape.y1)
            let shapeEnd = SerializablePoint(x: shape.x2, y: shape.y2)
            let tempWall = WallSegment(start: shapeStart, end: shapeEnd)
            if tempWall.distanceTo(point: point) < threshold {
                canvasState.recordAction(.removeDraftingShape(shape))
                project.draftingShapes.removeAll { $0.id == shape.id }
                modelContext.delete(shape)
                project.touch()
                return
            }
        }
    }

    private func handleSelect(_ point: SerializablePoint) {
        let threshold = 20.0 / Double(canvasState.viewportZoom)
        let nearWalls = GeometryEngine.wallsNearPoint(point, walls: project.walls, threshold: threshold)
        if let wall = nearWalls.first {
            canvasState.selectedItems = [.wall(wall.id)]
        } else {
            canvasState.clearSelection()
        }
    }
}
