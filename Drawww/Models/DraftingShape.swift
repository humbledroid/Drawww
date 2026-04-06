import Foundation
import SwiftData

// MARK: - Line Style

enum LineStyle: String, Codable, CaseIterable, Identifiable {
    case solid
    case dashed
    case dotted
    case dashDot       // architectural center line
    case construction  // light, non-printing guide line

    var id: String { rawValue }

    var label: String {
        switch self {
        case .solid: return "Solid"
        case .dashed: return "Dashed"
        case .dotted: return "Dotted"
        case .dashDot: return "Dash-Dot"
        case .construction: return "Construction"
        }
    }

    var dashPattern: [CGFloat] {
        switch self {
        case .solid: return []
        case .dashed: return [10, 6]
        case .dotted: return [2, 4]
        case .dashDot: return [12, 4, 2, 4]
        case .construction: return [6, 8]
        }
    }

    var isPrintable: Bool {
        self != .construction
    }
}

// MARK: - Line Weight

enum LineWeight: String, Codable, CaseIterable, Identifiable {
    case hairline   // 0.5 pt — construction lines, light details
    case thin       // 1.0 pt — dimension lines, hatching
    case medium     // 2.0 pt — standard walls, outlines
    case thick      // 3.5 pt — section cut lines, heavy outlines
    case extraThick // 5.0 pt — ground line, emphasis

    var id: String { rawValue }

    var width: CGFloat {
        switch self {
        case .hairline: return 0.5
        case .thin: return 1.0
        case .medium: return 2.0
        case .thick: return 3.5
        case .extraThick: return 5.0
        }
    }

    var label: String {
        switch self {
        case .hairline: return "Hairline"
        case .thin: return "Thin"
        case .medium: return "Medium"
        case .thick: return "Thick"
        case .extraThick: return "Extra Thick"
        }
    }
}

// MARK: - Drafting Shape Types

enum DraftingShapeType: String, Codable {
    case line
    case rectangle
    case circle
    case arc
    case ellipse
    case lShape
    case triangle
}

// MARK: - Drafting Shape Model

@Model
final class DraftingShape {
    var id: UUID
    var shapeTypeRaw: String

    // Generic geometry storage — interpretation depends on shapeType
    var x1: Double   // start / origin / center
    var y1: Double
    var x2: Double   // end / size / radius
    var y2: Double
    var x3: Double   // third point (triangle) / extra param
    var y3: Double

    var rotation: Double      // rotation angle in radians
    var lineStyleRaw: String
    var lineWeightRaw: String

    var startAngle: Double    // for arcs
    var endAngle: Double      // for arcs

    var isConstructionLine: Bool  // non-printing guide
    var createdAt: Date

    var project: FloorPlanProject?

    @Transient
    var shapeType: DraftingShapeType {
        get { DraftingShapeType(rawValue: shapeTypeRaw) ?? .line }
        set { shapeTypeRaw = newValue.rawValue }
    }

    @Transient
    var lineStyle: LineStyle {
        get { LineStyle(rawValue: lineStyleRaw) ?? .solid }
        set { lineStyleRaw = newValue.rawValue }
    }

    @Transient
    var lineWeight: LineWeight {
        get { LineWeight(rawValue: lineWeightRaw) ?? .medium }
        set { lineWeightRaw = newValue.rawValue }
    }

    init(shapeType: DraftingShapeType) {
        self.id = UUID()
        self.shapeTypeRaw = shapeType.rawValue
        self.x1 = 0; self.y1 = 0
        self.x2 = 0; self.y2 = 0
        self.x3 = 0; self.y3 = 0
        self.rotation = 0
        self.lineStyleRaw = LineStyle.solid.rawValue
        self.lineWeightRaw = LineWeight.medium.rawValue
        self.startAngle = 0
        self.endAngle = .pi * 2
        self.isConstructionLine = false
        self.createdAt = Date()
    }

    // MARK: - Factory Methods

    static func makeLine(from start: SerializablePoint, to end: SerializablePoint, style: LineStyle = .solid, weight: LineWeight = .medium) -> DraftingShape {
        let shape = DraftingShape(shapeType: .line)
        shape.x1 = start.x; shape.y1 = start.y
        shape.x2 = end.x; shape.y2 = end.y
        shape.lineStyle = style
        shape.lineWeight = weight
        shape.isConstructionLine = (style == .construction)
        return shape
    }

    static func makeCircle(center: SerializablePoint, radius: Double, style: LineStyle = .solid, weight: LineWeight = .medium) -> DraftingShape {
        let shape = DraftingShape(shapeType: .circle)
        shape.x1 = center.x; shape.y1 = center.y
        shape.x2 = radius; shape.y2 = radius
        shape.lineStyle = style
        shape.lineWeight = weight
        return shape
    }

    static func makeArc(center: SerializablePoint, radius: Double, startAngle: Double, endAngle: Double, weight: LineWeight = .medium) -> DraftingShape {
        let shape = DraftingShape(shapeType: .arc)
        shape.x1 = center.x; shape.y1 = center.y
        shape.x2 = radius; shape.y2 = 0
        shape.startAngle = startAngle
        shape.endAngle = endAngle
        shape.lineWeight = weight
        return shape
    }

    static func makeRectangle(origin: SerializablePoint, width: Double, height: Double, angle: Double = 0, style: LineStyle = .solid, weight: LineWeight = .medium) -> DraftingShape {
        let shape = DraftingShape(shapeType: .rectangle)
        shape.x1 = origin.x; shape.y1 = origin.y
        shape.x2 = width; shape.y2 = height
        shape.rotation = angle
        shape.lineStyle = style
        shape.lineWeight = weight
        return shape
    }

    static func makeTriangle(p1: SerializablePoint, p2: SerializablePoint, p3: SerializablePoint, weight: LineWeight = .medium) -> DraftingShape {
        let shape = DraftingShape(shapeType: .triangle)
        shape.x1 = p1.x; shape.y1 = p1.y
        shape.x2 = p2.x; shape.y2 = p2.y
        shape.x3 = p3.x; shape.y3 = p3.y
        shape.lineWeight = weight
        return shape
    }

    static func makeConstructionLine(from start: SerializablePoint, to end: SerializablePoint) -> DraftingShape {
        return makeLine(from: start, to: end, style: .construction, weight: .hairline)
    }
}
