import Foundation
import SwiftUI
import Combine

// MARK: - Drawing Tool

enum DrawingTool: String, CaseIterable, Identifiable {
    case wall
    case select
    case eraser
    case annotation
    case dimensionLine
    case textLabel

    var id: String { rawValue }

    var label: String {
        switch self {
        case .wall: return "Wall"
        case .select: return "Select"
        case .eraser: return "Eraser"
        case .annotation: return "Annotate"
        case .dimensionLine: return "Dimension"
        case .textLabel: return "Label"
        }
    }

    var iconName: String {
        switch self {
        case .wall: return "line.diagonal"
        case .select: return "cursorarrow"
        case .eraser: return "eraser"
        case .annotation: return "pencil.tip"
        case .dimensionLine: return "ruler"
        case .textLabel: return "textformat"
        }
    }
}

// MARK: - Snap Result

struct SnapResult {
    let snappedPoint: SerializablePoint
    let snappedToEndpoint: Bool
    let axisLocked: Bool
    let lockedAxis: SnapAxis?
    let guideLines: [GuideLine]

    enum SnapAxis {
        case horizontal
        case vertical
        case diagonal45
        case diagonal135
    }
}

struct GuideLine {
    let start: SerializablePoint
    let end: SerializablePoint
    let type: GuideType

    enum GuideType {
        case extension_
        case alignment
        case axisLock
    }
}

// MARK: - Selection

enum SelectionItem: Equatable {
    case wall(UUID)
    case dimensionLine(UUID)
    case textLabel(UUID)
}

// MARK: - Undo Action

enum CanvasAction {
    case addWall(WallSegment)
    case removeWall(WallSegment)
    case moveWall(wall: WallSegment, oldStart: SerializablePoint, oldEnd: SerializablePoint)
    case addDimensionLine(DimensionLine)
    case removeDimensionLine(DimensionLine)
    case addTextLabel(TextLabel)
    case removeTextLabel(TextLabel)
}

// MARK: - Canvas State (Observable)

@Observable
final class CanvasState {
    // Current tool
    var activeTool: DrawingTool = .wall
    var previousTool: DrawingTool = .select

    // Viewport
    var viewportOffset: CGSize = .zero
    var viewportZoom: CGFloat = 1.0

    // Drawing in progress
    var isDrawing: Bool = false
    var drawingStartPoint: SerializablePoint?
    var drawingCurrentPoint: SerializablePoint?

    // Snap/guide state
    var activeGuideLines: [GuideLine] = []
    var snapThreshold: Double = 15.0 // points

    // Selection
    var selectedItems: [SelectionItem] = []

    // Grid
    var showGrid: Bool = true
    var gridSpacing: Double = 72.0 // 1 foot at default scale

    // Live measurement
    var liveMeasurementText: String?
    var liveMeasurementPosition: SerializablePoint?
    var liveMeasurementAngle: Double = 0

    // Undo/Redo stacks
    var undoStack: [CanvasAction] = []
    var redoStack: [CanvasAction] = []

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    // MARK: - Tool Switching

    func switchTool(to tool: DrawingTool) {
        previousTool = activeTool
        activeTool = tool
        clearDrawingState()
    }

    func toggleLastTwoTools() {
        let temp = activeTool
        activeTool = previousTool
        previousTool = temp
        clearDrawingState()
    }

    func clearDrawingState() {
        isDrawing = false
        drawingStartPoint = nil
        drawingCurrentPoint = nil
        activeGuideLines = []
        liveMeasurementText = nil
        liveMeasurementPosition = nil
    }

    // MARK: - Viewport Transforms

    /// Convert a screen point to canvas (world) coordinates
    func screenToCanvas(_ screenPoint: CGPoint, canvasSize: CGSize) -> SerializablePoint {
        let centerX = canvasSize.width / 2
        let centerY = canvasSize.height / 2

        let canvasX = (Double(screenPoint.x) - Double(centerX) - Double(viewportOffset.width)) / Double(viewportZoom)
        let canvasY = (Double(screenPoint.y) - Double(centerY) - Double(viewportOffset.height)) / Double(viewportZoom)

        return SerializablePoint(x: canvasX, y: canvasY)
    }

    /// Convert a canvas (world) point to screen coordinates
    func canvasToScreen(_ canvasPoint: SerializablePoint, canvasSize: CGSize) -> CGPoint {
        let centerX = canvasSize.width / 2
        let centerY = canvasSize.height / 2

        let screenX = canvasPoint.x * Double(viewportZoom) + Double(centerX) + Double(viewportOffset.width)
        let screenY = canvasPoint.y * Double(viewportZoom) + Double(centerY) + Double(viewportOffset.height)

        return CGPoint(x: screenX, y: screenY)
    }

    // MARK: - Undo/Redo

    func recordAction(_ action: CanvasAction) {
        undoStack.append(action)
        redoStack.removeAll() // clear redo stack on new action
    }

    func clearSelection() {
        selectedItems = []
    }

    // MARK: - Zoom

    var zoomPercentage: Int {
        Int(viewportZoom * 100)
    }

    func clampZoom() {
        viewportZoom = max(0.05, min(30.0, viewportZoom))
    }
}
