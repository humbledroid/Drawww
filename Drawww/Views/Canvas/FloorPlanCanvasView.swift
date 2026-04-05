import SwiftUI
import SwiftData

/// The main infinite canvas view for drawing floor plans.
/// Handles Apple Pencil input, touch gestures for pan/zoom, and renders all geometry.
struct FloorPlanCanvasView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var project: FloorPlanProject
    @Bindable var canvasState: CanvasState

    private let snapEngine = SnapEngine()

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                Color(.systemBackground)
                    .ignoresSafeArea()

                // Canvas renderer (grid, walls, measurements, guides)
                CanvasRenderer(
                    walls: project.walls,
                    canvasState: canvasState,
                    unitSystem: project.unitSystem,
                    scale: project.pointsPerRealUnit,
                    canvasSize: geometry.size
                )

                // Gesture overlay
                CanvasGestureView(
                    canvasState: canvasState,
                    canvasSize: geometry.size,
                    onPencilBegan: { point in handleDrawBegan(point, canvasSize: geometry.size) },
                    onPencilMoved: { point in handleDrawMoved(point, canvasSize: geometry.size) },
                    onPencilEnded: { point in handleDrawEnded(point, canvasSize: geometry.size) },
                    onTapAt: { point in handleTap(point, canvasSize: geometry.size) }
                )
            }
        }
    }

    // MARK: - Drawing Handlers

    private func handleDrawBegan(_ screenPoint: CGPoint, canvasSize: CGSize) {
        let canvasPoint = canvasState.screenToCanvas(screenPoint, canvasSize: canvasSize)

        switch canvasState.activeTool {
        case .wall:
            // Snap start point to existing endpoints
            let snapped = snapEngine.snap(
                point: canvasPoint,
                from: nil,
                existingWalls: project.walls,
                zoomLevel: Double(canvasState.viewportZoom)
            )
            canvasState.isDrawing = true
            canvasState.drawingStartPoint = snapped.snappedPoint
            canvasState.drawingCurrentPoint = snapped.snappedPoint

        case .eraser:
            // Erase wall under point
            let threshold = 20.0 / Double(canvasState.viewportZoom)
            let nearWalls = GeometryEngine.wallsNearPoint(canvasPoint, walls: project.walls, threshold: threshold)
            if let wallToRemove = nearWalls.first {
                canvasState.recordAction(.removeWall(wallToRemove))
                project.walls.removeAll { $0.id == wallToRemove.id }
                modelContext.delete(wallToRemove)
                project.touch()
            }

        case .select:
            // Start selection
            let threshold = 20.0 / Double(canvasState.viewportZoom)
            let nearWalls = GeometryEngine.wallsNearPoint(canvasPoint, walls: project.walls, threshold: threshold)
            if let selectedWall = nearWalls.first {
                canvasState.selectedItems = [.wall(selectedWall.id)]
            } else {
                canvasState.clearSelection()
            }

        default:
            break
        }
    }

    private func handleDrawMoved(_ screenPoint: CGPoint, canvasSize: CGSize) {
        guard canvasState.isDrawing else { return }
        let canvasPoint = canvasState.screenToCanvas(screenPoint, canvasSize: canvasSize)

        switch canvasState.activeTool {
        case .wall:
            let snapped = snapEngine.snap(
                point: canvasPoint,
                from: canvasState.drawingStartPoint,
                existingWalls: project.walls,
                zoomLevel: Double(canvasState.viewportZoom)
            )
            canvasState.drawingCurrentPoint = snapped.snappedPoint
            canvasState.activeGuideLines = snapped.guideLines

        default:
            break
        }
    }

    private func handleDrawEnded(_ screenPoint: CGPoint, canvasSize: CGSize) {
        guard canvasState.isDrawing else { return }

        switch canvasState.activeTool {
        case .wall:
            if let start = canvasState.drawingStartPoint,
               let end = canvasState.drawingCurrentPoint,
               start.distance(to: end) > 5 {

                let wall = WallSegment(start: start, end: end)
                wall.project = project
                project.walls.append(wall)
                modelContext.insert(wall)
                canvasState.recordAction(.addWall(wall))
                project.touch()
            }

        default:
            break
        }

        canvasState.clearDrawingState()
    }

    private func handleTap(_ screenPoint: CGPoint, canvasSize: CGSize) {
        let canvasPoint = canvasState.screenToCanvas(screenPoint, canvasSize: canvasSize)

        if canvasState.activeTool == .select {
            let threshold = 20.0 / Double(canvasState.viewportZoom)
            let nearWalls = GeometryEngine.wallsNearPoint(canvasPoint, walls: project.walls, threshold: threshold)
            if let selectedWall = nearWalls.first {
                canvasState.selectedItems = [.wall(selectedWall.id)]
            } else {
                canvasState.clearSelection()
            }
        }
    }

    // MARK: - Undo / Redo

    func performUndo() {
        guard let action = canvasState.undoStack.popLast() else { return }

        switch action {
        case .addWall(let wall):
            project.walls.removeAll { $0.id == wall.id }
            modelContext.delete(wall)
            canvasState.redoStack.append(action)

        case .removeWall(let wall):
            let newWall = WallSegment(start: wall.start, end: wall.end, thickness: wall.thickness)
            newWall.project = project
            project.walls.append(newWall)
            modelContext.insert(newWall)
            canvasState.redoStack.append(.addWall(newWall))

        case .moveWall(let wall, let oldStart, let oldEnd):
            let currentStart = wall.start
            let currentEnd = wall.end
            wall.start = oldStart
            wall.end = oldEnd
            canvasState.redoStack.append(.moveWall(wall: wall, oldStart: currentStart, oldEnd: currentEnd))

        default:
            break
        }

        project.touch()
    }

    func performRedo() {
        guard let action = canvasState.redoStack.popLast() else { return }

        switch action {
        case .addWall(let wall):
            wall.project = project
            project.walls.append(wall)
            modelContext.insert(wall)
            canvasState.undoStack.append(action)

        case .removeWall(let wall):
            project.walls.removeAll { $0.id == wall.id }
            modelContext.delete(wall)
            canvasState.undoStack.append(action)

        case .moveWall(let wall, let oldStart, let oldEnd):
            let currentStart = wall.start
            let currentEnd = wall.end
            wall.start = oldStart
            wall.end = oldEnd
            canvasState.undoStack.append(.moveWall(wall: wall, oldStart: currentStart, oldEnd: currentEnd))

        default:
            break
        }

        project.touch()
    }

    func deleteSelected() {
        for item in canvasState.selectedItems {
            switch item {
            case .wall(let id):
                if let wall = project.walls.first(where: { $0.id == id }) {
                    canvasState.recordAction(.removeWall(wall))
                    project.walls.removeAll { $0.id == id }
                    modelContext.delete(wall)
                }
            default:
                break
            }
        }
        canvasState.clearSelection()
        project.touch()
    }
}
