import Foundation
import SwiftData
import simd

// MARK: - Unit System

/// 1 foot = 0.3048 meters exactly
let kFeetPerMeter: Double = 1.0 / 0.3048  // ≈ 3.28084
let kMetersPerFoot: Double = 0.3048

enum UnitSystem: String, Codable, CaseIterable {
    case imperial // ft/in
    case metric   // m/cm

    var shortLabel: String {
        switch self {
        case .imperial: return "ft/in"
        case .metric: return "m/cm"
        }
    }

    var baseUnitLabel: String {
        switch self {
        case .imperial: return "ft"
        case .metric: return "m"
        }
    }

    /// Convert a pointsPerRealUnit scale factor FROM this unit system TO the other
    func convertScale(_ pointsPerUnit: Double, to target: UnitSystem) -> Double {
        guard self != target else { return pointsPerUnit }
        switch (self, target) {
        case (.imperial, .metric):
            // pts/ft → pts/m: 1 m = 3.28084 ft, so pts/m = pts/ft × 3.28084
            return pointsPerUnit * kFeetPerMeter
        case (.metric, .imperial):
            // pts/m → pts/ft: 1 ft = 0.3048 m, so pts/ft = pts/m × 0.3048
            return pointsPerUnit * kMetersPerFoot
        default:
            return pointsPerUnit
        }
    }

    func formatLength(_ points: Double, scale: Double) -> String {
        let realUnits = points / scale
        switch self {
        case .imperial:
            let totalInches = realUnits * 12.0
            let feet = Int(totalInches / 1.0) / 12
            let inches = totalInches - Double(feet) * 12.0
            if feet > 0 {
                if inches < 0.05 {
                    return String(format: "%d'", feet)
                }
                return String(format: "%d' %.1f\"", feet, inches)
            } else {
                return String(format: "%.1f\"", inches)
            }
        case .metric:
            if realUnits >= 1.0 {
                return String(format: "%.2f m", realUnits)
            } else {
                return String(format: "%.0f cm", realUnits * 100.0)
            }
        }
    }

    func formatArea(_ pointsSquared: Double, scale: Double) -> String {
        let realArea = pointsSquared / (scale * scale)
        switch self {
        case .imperial:
            return String(format: "%.1f ft²", realArea)
        case .metric:
            return String(format: "%.2f m²", realArea)
        }
    }
}

// MARK: - Serializable Point

struct SerializablePoint: Codable, Equatable {
    var x: Double
    var y: Double

    var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    init(_ point: CGPoint) {
        self.x = Double(point.x)
        self.y = Double(point.y)
    }

    func distance(to other: SerializablePoint) -> Double {
        let dx = x - other.x
        let dy = y - other.y
        return sqrt(dx * dx + dy * dy)
    }

    func midpoint(to other: SerializablePoint) -> SerializablePoint {
        SerializablePoint(x: (x + other.x) / 2, y: (y + other.y) / 2)
    }

    func angle(to other: SerializablePoint) -> Double {
        atan2(other.y - y, other.x - x)
    }
}

// MARK: - Wall Segment

@Model
final class WallSegment {
    var id: UUID
    var startX: Double
    var startY: Double
    var endX: Double
    var endY: Double
    var thickness: Double // center-line only in Phase 1, visual in Phase 2
    var createdAt: Date

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

    @Transient
    var length: Double {
        start.distance(to: end)
    }

    @Transient
    var midpoint: SerializablePoint {
        start.midpoint(to: end)
    }

    @Transient
    var angle: Double {
        start.angle(to: end)
    }

    var project: FloorPlanProject?

    init(start: SerializablePoint, end: SerializablePoint, thickness: Double = 6.0) {
        self.id = UUID()
        self.startX = start.x
        self.startY = start.y
        self.endX = end.x
        self.endY = end.y
        self.thickness = thickness
        self.createdAt = Date()
    }

    /// Returns the closest point on this wall segment to a given point
    func closestPoint(to point: SerializablePoint) -> SerializablePoint {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSq = dx * dx + dy * dy

        guard lengthSq > 0 else { return start }

        var t = ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSq
        t = max(0, min(1, t))

        return SerializablePoint(
            x: start.x + t * dx,
            y: start.y + t * dy
        )
    }

    func distanceTo(point: SerializablePoint) -> Double {
        let closest = closestPoint(to: point)
        return closest.distance(to: point)
    }
}

// MARK: - Dimension Line (manual annotation)

@Model
final class DimensionLine {
    var id: UUID
    var startX: Double
    var startY: Double
    var endX: Double
    var endY: Double
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

    @Transient
    var length: Double {
        start.distance(to: end)
    }

    init(start: SerializablePoint, end: SerializablePoint) {
        self.id = UUID()
        self.startX = start.x
        self.startY = start.y
        self.endX = end.x
        self.endY = end.y
    }
}

// MARK: - Text Label

@Model
final class TextLabel {
    var id: UUID
    var text: String
    var positionX: Double
    var positionY: Double
    var fontSize: Double
    var project: FloorPlanProject?

    init(text: String, position: SerializablePoint, fontSize: Double = 14) {
        self.id = UUID()
        self.text = text
        self.positionX = position.x
        self.positionY = position.y
        self.fontSize = fontSize
    }
}

// MARK: - Floor Plan Project

@Model
final class FloorPlanProject {
    var id: UUID
    var name: String
    var createdAt: Date
    var modifiedAt: Date
    var unitSystemRaw: String
    var pointsPerRealUnit: Double // scale: how many canvas points = 1 real-world unit (foot or meter)

    // Viewport state
    var viewportOffsetX: Double
    var viewportOffsetY: Double
    var viewportZoom: Double

    @Relationship(deleteRule: .cascade, inverse: \WallSegment.project)
    var walls: [WallSegment]

    @Relationship(deleteRule: .cascade, inverse: \DimensionLine.project)
    var dimensionLines: [DimensionLine]

    @Relationship(deleteRule: .cascade, inverse: \TextLabel.project)
    var textLabels: [TextLabel]

    @Relationship(deleteRule: .cascade, inverse: \DraftingShape.project)
    var draftingShapes: [DraftingShape]

    @Relationship(deleteRule: .cascade, inverse: \SectionCutLine.project)
    var sectionCuts: [SectionCutLine]

    @Relationship(deleteRule: .cascade, inverse: \HeightMarker.project)
    var heightMarkers: [HeightMarker]

    @Relationship(deleteRule: .cascade, inverse: \StairSymbol.project)
    var stairs: [StairSymbol]

    @Relationship(deleteRule: .cascade, inverse: \HatchRegion.project)
    var hatchRegions: [HatchRegion]

    @Relationship(deleteRule: .cascade, inverse: \ElevationArrow.project)
    var elevationArrows: [ElevationArrow]

    @Transient
    var unitSystem: UnitSystem {
        get { UnitSystem(rawValue: unitSystemRaw) ?? .imperial }
        set {
            let oldSystem = unitSystem
            unitSystemRaw = newValue.rawValue
            // Convert scale factor so measurements stay correct
            pointsPerRealUnit = oldSystem.convertScale(pointsPerRealUnit, to: newValue)
        }
    }

    init(name: String = "Untitled Plan", unitSystem: UnitSystem = .imperial) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.unitSystemRaw = unitSystem.rawValue
        // Default: 72 pts = 1 foot (1 screen inch = 1 real foot)
        // If metric: 72 / 0.3048 ≈ 236.22 pts = 1 meter
        switch unitSystem {
        case .imperial:
            self.pointsPerRealUnit = 72.0
        case .metric:
            self.pointsPerRealUnit = 72.0 * kFeetPerMeter // ≈ 236.22
        }
        self.viewportOffsetX = 0
        self.viewportOffsetY = 0
        self.viewportZoom = 1.0
        self.walls = []
        self.dimensionLines = []
        self.textLabels = []
        self.draftingShapes = []
        self.sectionCuts = []
        self.heightMarkers = []
        self.stairs = []
        self.hatchRegions = []
        self.elevationArrows = []
    }

    func touch() {
        modifiedAt = Date()
    }
}
