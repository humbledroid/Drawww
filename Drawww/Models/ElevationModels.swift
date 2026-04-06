import Foundation
import SwiftData

// MARK: - Section Cut Line

/// A section cut line with direction arrows — standard architectural symbol.
/// Drawn as a thick dash-dot line with triangular arrows at each end showing view direction.
@Model
final class SectionCutLine {
    var id: UUID
    var startX: Double
    var startY: Double
    var endX: Double
    var endY: Double
    var label: String          // e.g. "A", "B", "1"
    var viewDirectionAngle: Double  // which way the section looks (perpendicular to line)
    var createdAt: Date

    var project: FloorPlanProject?

    @Transient
    var start: SerializablePoint {
        get { SerializablePoint(x: startX, y: startY) }
        set { startX = newValue.x; startY = newValue.y }
    }

    @Transient
    var end: SerializablePoint {
        get { SerializablePoint(x: endX, y: endY) }
        set { endX = newValue.x; endY = newValue.y }
    }

    init(start: SerializablePoint, end: SerializablePoint, label: String = "A") {
        self.id = UUID()
        self.startX = start.x; self.startY = start.y
        self.endX = end.x; self.endY = end.y
        self.label = label
        // Default view direction: perpendicular to line, pointing "up" (screen)
        self.viewDirectionAngle = start.angle(to: end) + .pi / 2
        self.createdAt = Date()
    }
}

// MARK: - Height Marker

/// A level/height marker for elevation views — shows height above reference plane.
/// Displayed as a circle with crosshairs and the height value.
@Model
final class HeightMarker {
    var id: UUID
    var positionX: Double
    var positionY: Double
    var heightValue: Double     // real-world height value
    var label: String           // e.g. "FL +0.00", "CL 2.70"
    var isReferenceLevel: Bool  // is this the ±0.00 datum?
    var createdAt: Date

    var project: FloorPlanProject?

    @Transient
    var position: SerializablePoint {
        get { SerializablePoint(x: positionX, y: positionY) }
        set { positionX = newValue.x; positionY = newValue.y }
    }

    init(position: SerializablePoint, heightValue: Double = 0, label: String = "FL ±0.00") {
        self.id = UUID()
        self.positionX = position.x; self.positionY = position.y
        self.heightValue = heightValue
        self.label = label
        self.isReferenceLevel = (heightValue == 0)
        self.createdAt = Date()
    }
}

// MARK: - Stair Symbol

/// Stair representation for floor plans — shows direction of travel with arrow.
@Model
final class StairSymbol {
    var id: UUID
    var originX: Double
    var originY: Double
    var width: Double        // stair width
    var treadDepth: Double   // depth of each step
    var riserCount: Int      // number of steps
    var rotation: Double     // orientation angle
    var goesUp: Bool         // arrow direction: up or down
    var createdAt: Date

    var project: FloorPlanProject?

    @Transient
    var origin: SerializablePoint {
        get { SerializablePoint(x: originX, y: originY) }
        set { originX = newValue.x; originY = newValue.y }
    }

    /// Total run length of the stair
    @Transient
    var totalLength: Double {
        treadDepth * Double(riserCount)
    }

    init(origin: SerializablePoint, width: Double = 100, treadDepth: Double = 20, riserCount: Int = 12, rotation: Double = 0) {
        self.id = UUID()
        self.originX = origin.x; self.originY = origin.y
        self.width = width
        self.treadDepth = treadDepth
        self.riserCount = riserCount
        self.rotation = rotation
        self.goesUp = true
        self.createdAt = Date()
    }
}

// MARK: - Hatch Pattern

enum HatchPatternType: String, Codable, CaseIterable, Identifiable {
    case diagonal        // 45° lines — general material
    case crosshatch      // 45° + 135° — earth/ground
    case horizontal      // horizontal lines — wood grain
    case brick           // brick pattern
    case concrete        // random dots — concrete
    case insulation      // wavy lines — insulation

    var id: String { rawValue }

    var label: String {
        switch self {
        case .diagonal: return "Diagonal"
        case .crosshatch: return "Crosshatch"
        case .horizontal: return "Horizontal"
        case .brick: return "Brick"
        case .concrete: return "Concrete"
        case .insulation: return "Insulation"
        }
    }
}

/// A hatched region defined by a bounding polygon.
@Model
final class HatchRegion {
    var id: UUID
    // Store polygon points as parallel arrays (SwiftData can't store [SerializablePoint])
    var pointsX: [Double]
    var pointsY: [Double]
    var patternTypeRaw: String
    var patternSpacing: Double  // distance between hatch lines in points
    var patternAngle: Double    // override angle (0 = use pattern default)
    var createdAt: Date

    var project: FloorPlanProject?

    @Transient
    var patternType: HatchPatternType {
        get { HatchPatternType(rawValue: patternTypeRaw) ?? .diagonal }
        set { patternTypeRaw = newValue.rawValue }
    }

    @Transient
    var points: [SerializablePoint] {
        get {
            zip(pointsX, pointsY).map { SerializablePoint(x: $0, y: $1) }
        }
        set {
            pointsX = newValue.map(\.x)
            pointsY = newValue.map(\.y)
        }
    }

    init(points: [SerializablePoint], pattern: HatchPatternType = .diagonal, spacing: Double = 8) {
        self.id = UUID()
        self.pointsX = points.map(\.x)
        self.pointsY = points.map(\.y)
        self.patternTypeRaw = pattern.rawValue
        self.patternSpacing = spacing
        self.patternAngle = 0
        self.createdAt = Date()
    }
}

// MARK: - Elevation Reference Arrow

/// An arrow indicating view direction for an elevation, placed near section cut lines.
@Model
final class ElevationArrow {
    var id: UUID
    var positionX: Double
    var positionY: Double
    var directionAngle: Double   // where the arrow points
    var label: String            // e.g. "North Elevation", "A"
    var linkedSectionId: UUID?   // optional link to a SectionCutLine
    var createdAt: Date

    var project: FloorPlanProject?

    @Transient
    var position: SerializablePoint {
        get { SerializablePoint(x: positionX, y: positionY) }
        set { positionX = newValue.x; positionY = newValue.y }
    }

    init(position: SerializablePoint, directionAngle: Double, label: String = "A") {
        self.id = UUID()
        self.positionX = position.x; self.positionY = position.y
        self.directionAngle = directionAngle
        self.label = label
        self.createdAt = Date()
    }
}
