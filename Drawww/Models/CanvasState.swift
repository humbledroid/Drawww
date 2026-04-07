import Foundation
import SwiftUI
import PencilKit
import Combine

// MARK: - Drawing Tool

enum DrawingTool: String, CaseIterable, Identifiable {
    // Core tools
    case wall
    case select
    case objectEraser    // tap a whole wall/shape to delete it
    case strokeEraser    // scrub across PencilKit sketch strokes to erase them

    // Paper-like tools
    case sketch          // freeform PencilKit with pressure
    case smartSketch     // sketch with shape recognition

    // Drafting primitives
    case line            // straight line with style/weight
    case circle
    case arc
    case rectangle

    // Elevation tools
    case sectionCut
    case heightMarker
    case stairSymbol
    case hatchRegion
    case elevationArrow

    // Annotation tools
    case constructionLine
    case dimensionLine
    case textLabel

    var id: String { rawValue }

    var label: String {
        switch self {
        case .wall: return "Wall"
        case .select: return "Select"
        case .objectEraser: return "Object Erase"
        case .strokeEraser: return "Stroke Erase"
        case .sketch: return "Sketch"
        case .smartSketch: return "Smart"
        case .line: return "Line"
        case .circle: return "Circle"
        case .arc: return "Arc"
        case .rectangle: return "Rect"
        case .sectionCut: return "Section"
        case .heightMarker: return "Height"
        case .stairSymbol: return "Stairs"
        case .hatchRegion: return "Hatch"
        case .elevationArrow: return "Elev."
        case .constructionLine: return "Guide"
        case .dimensionLine: return "Dim."
        case .textLabel: return "Label"
        }
    }

    var iconName: String {
        switch self {
        case .wall: return "line.diagonal"
        case .select: return "cursorarrow"
        case .objectEraser: return "trash"
        case .strokeEraser: return "eraser"
        case .sketch: return "pencil.tip"
        case .smartSketch: return "pencil.tip.crop.circle"
        case .line: return "line.diagonal"
        case .circle: return "circle"
        case .arc: return "circle.bottomhalf.filled"
        case .rectangle: return "rectangle"
        case .sectionCut: return "scissors"
        case .heightMarker: return "arrow.up.and.down.text.horizontal"
        case .stairSymbol: return "stairs"
        case .hatchRegion: return "square.fill.on.square.fill"
        case .elevationArrow: return "arrow.up.circle"
        case .constructionLine: return "line.3.horizontal"
        case .dimensionLine: return "ruler"
        case .textLabel: return "textformat"
        }
    }

    /// Grouping for the tool palette
    var group: ToolGroup {
        switch self {
        case .wall, .select, .objectEraser, .strokeEraser: return .core
        case .sketch, .smartSketch: return .paper
        case .line, .circle, .arc, .rectangle: return .drafting
        case .sectionCut, .heightMarker, .stairSymbol, .hatchRegion, .elevationArrow: return .elevation
        case .constructionLine, .dimensionLine, .textLabel: return .annotation
        }
    }

    /// Tools shown in the radial menu (most used)
    static var radialMenuTools: [DrawingTool] {
        [.wall, .sketch, .smartSketch, .select, .objectEraser, .strokeEraser]
    }
}

enum ToolGroup: String, CaseIterable, Identifiable {
    case core
    case paper
    case drafting
    case elevation
    case annotation

    var id: String { rawValue }

    var label: String {
        switch self {
        case .core: return "Core"
        case .paper: return "Sketch"
        case .drafting: return "Draft"
        case .elevation: return "Elevation"
        case .annotation: return "Annotate"
        }
    }

    var tools: [DrawingTool] {
        DrawingTool.allCases.filter { $0.group == self }
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
    case draftingShape(UUID)
    case dimensionLine(UUID)
    case textLabel(UUID)
    case sectionCut(UUID)
    case heightMarker(UUID)
    case stairSymbol(UUID)
    case hatchRegion(UUID)
    case elevationArrow(UUID)
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
    case addDraftingShape(DraftingShape)
    case removeDraftingShape(DraftingShape)
    case addSectionCut(SectionCutLine)
    case removeSectionCut(SectionCutLine)
    case addHeightMarker(HeightMarker)
    case removeHeightMarker(HeightMarker)
    case addStairSymbol(StairSymbol)
    case removeStairSymbol(StairSymbol)
    case sketchStrokeChanged
}

// MARK: - Active Line Style (for drafting tools)

@Observable
final class ActiveLineProperties {
    var style: LineStyle = .solid
    var weight: LineWeight = .medium
}

// MARK: - Canvas State (Observable)

@Observable
final class CanvasState {
    // Current tool
    var activeTool: DrawingTool = .wall
    var previousTool: DrawingTool = .select

    // Line properties for drafting tools
    var lineProperties = ActiveLineProperties()

    // Viewport
    var viewportOffset: CGSize = .zero
    var viewportZoom: CGFloat = 1.0

    // Drawing in progress
    var isDrawing: Bool = false
    var drawingStartPoint: SerializablePoint?
    var drawingCurrentPoint: SerializablePoint?

    // Smart sketch — collected points during a stroke
    var smartSketchPoints: [SerializablePoint] = []

    // PencilKit freeform drawing
    var sketchDrawing: PKDrawing = PKDrawing()

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

    // Radial menu
    var showRadialMenu: Bool = false
    var radialMenuPosition: CGPoint = .zero

    // Construction lines visibility
    var showConstructionLines: Bool = true

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
        smartSketchPoints = []
        activeGuideLines = []
        liveMeasurementText = nil
        liveMeasurementPosition = nil
    }

    // MARK: - Viewport Transforms

    func screenToCanvas(_ screenPoint: CGPoint, canvasSize: CGSize) -> SerializablePoint {
        let centerX = canvasSize.width / 2
        let centerY = canvasSize.height / 2
        let canvasX = (Double(screenPoint.x) - Double(centerX) - Double(viewportOffset.width)) / Double(viewportZoom)
        let canvasY = (Double(screenPoint.y) - Double(centerY) - Double(viewportOffset.height)) / Double(viewportZoom)
        return SerializablePoint(x: canvasX, y: canvasY)
    }

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
        redoStack.removeAll()
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
