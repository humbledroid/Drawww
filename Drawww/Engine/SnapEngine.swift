import Foundation
import CoreGraphics

/// Handles all snapping logic: endpoint snapping, axis locking, extension guides
struct SnapEngine {
    let threshold: Double
    let axisLockAngleThreshold: Double = 5.0 // degrees

    init(threshold: Double = 15.0) {
        self.threshold = threshold
    }

    // MARK: - Main Snap Function

    func snap(
        point: SerializablePoint,
        from startPoint: SerializablePoint?,
        existingWalls: [WallSegment],
        zoomLevel: Double
    ) -> SnapResult {
        let adjustedThreshold = threshold / zoomLevel
        var snappedPoint = point
        var snappedToEndpoint = false
        var guideLines: [GuideLine] = []
        var lockedAxis: SnapResult.SnapAxis?

        // 1. First check endpoint snapping (highest priority)
        if let endpointSnap = snapToEndpoint(point: point, walls: existingWalls, threshold: adjustedThreshold) {
            snappedPoint = endpointSnap
            snappedToEndpoint = true
        }

        // 2. Then check axis locking (if we have a start point and didn't snap to endpoint)
        if let start = startPoint, !snappedToEndpoint {
            let axisResult = snapToAxis(point: snappedPoint, from: start, threshold: adjustedThreshold)
            snappedPoint = axisResult.point
            lockedAxis = axisResult.axis
        }

        // 3. Generate extension guides from existing wall endpoints
        if let start = startPoint {
            guideLines = generateExtensionGuides(
                from: start,
                to: snappedPoint,
                existingWalls: existingWalls,
                threshold: adjustedThreshold
            )
        }

        return SnapResult(
            snappedPoint: snappedPoint,
            snappedToEndpoint: snappedToEndpoint,
            axisLocked: lockedAxis != nil,
            lockedAxis: lockedAxis,
            guideLines: guideLines
        )
    }

    // MARK: - Endpoint Snapping

    func snapToEndpoint(
        point: SerializablePoint,
        walls: [WallSegment],
        threshold: Double
    ) -> SerializablePoint? {
        var closestPoint: SerializablePoint?
        var closestDistance = Double.infinity

        for wall in walls {
            let endpoints = [wall.start, wall.end]
            for endpoint in endpoints {
                let distance = point.distance(to: endpoint)
                if distance < threshold && distance < closestDistance {
                    closestDistance = distance
                    closestPoint = endpoint
                }
            }
        }

        return closestPoint
    }

    // MARK: - Axis Locking

    struct AxisSnapResult {
        let point: SerializablePoint
        let axis: SnapResult.SnapAxis?
    }

    func snapToAxis(
        point: SerializablePoint,
        from start: SerializablePoint,
        threshold: Double
    ) -> AxisSnapResult {
        let dx = point.x - start.x
        let dy = point.y - start.y
        let angle = atan2(dy, dx) * 180.0 / .pi
        let normalizedAngle = ((angle.truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360)

        let distance = sqrt(dx * dx + dy * dy)

        // Check horizontal (0° or 180°)
        if isNearAngle(normalizedAngle, target: 0) || isNearAngle(normalizedAngle, target: 180) {
            let snapped = SerializablePoint(x: point.x, y: start.y)
            return AxisSnapResult(point: snapped, axis: .horizontal)
        }

        // Check vertical (90° or 270°)
        if isNearAngle(normalizedAngle, target: 90) || isNearAngle(normalizedAngle, target: 270) {
            let snapped = SerializablePoint(x: start.x, y: point.y)
            return AxisSnapResult(point: snapped, axis: .vertical)
        }

        // Check 45° diagonals
        if isNearAngle(normalizedAngle, target: 45) || isNearAngle(normalizedAngle, target: 225) {
            let avg = (abs(dx) + abs(dy)) / 2
            let signX: Double = dx >= 0 ? 1 : -1
            let signY: Double = dy >= 0 ? 1 : -1
            let snapped = SerializablePoint(x: start.x + avg * signX, y: start.y + avg * signY)
            return AxisSnapResult(point: snapped, axis: .diagonal45)
        }

        // Check 135° diagonals
        if isNearAngle(normalizedAngle, target: 135) || isNearAngle(normalizedAngle, target: 315) {
            let avg = (abs(dx) + abs(dy)) / 2
            let signX: Double = dx >= 0 ? 1 : -1
            let signY: Double = dy >= 0 ? 1 : -1
            let snapped = SerializablePoint(x: start.x + avg * signX, y: start.y + avg * signY)
            return AxisSnapResult(point: snapped, axis: .diagonal135)
        }

        return AxisSnapResult(point: point, axis: nil)
    }

    private func isNearAngle(_ angle: Double, target: Double) -> Bool {
        let diff = abs(angle - target)
        return diff < axisLockAngleThreshold || diff > (360 - axisLockAngleThreshold)
    }

    // MARK: - Extension Guides

    func generateExtensionGuides(
        from start: SerializablePoint,
        to current: SerializablePoint,
        existingWalls: [WallSegment],
        threshold: Double
    ) -> [GuideLine] {
        var guides: [GuideLine] = []

        for wall in existingWalls {
            // Check alignment with wall endpoints
            for endpoint in [wall.start, wall.end] {
                // Horizontal alignment
                if abs(current.y - endpoint.y) < threshold {
                    guides.append(GuideLine(
                        start: endpoint,
                        end: SerializablePoint(x: current.x, y: endpoint.y),
                        type: .alignment
                    ))
                }
                // Vertical alignment
                if abs(current.x - endpoint.x) < threshold {
                    guides.append(GuideLine(
                        start: endpoint,
                        end: SerializablePoint(x: endpoint.x, y: current.y),
                        type: .alignment
                    ))
                }
            }

            // Extension along wall direction
            let wallAngle = wall.start.angle(to: wall.end)
            let extendedPoint = SerializablePoint(
                x: wall.end.x + cos(wallAngle) * 1000,
                y: wall.end.y + sin(wallAngle) * 1000
            )
            let distToLine = distanceFromPointToLine(
                point: current,
                lineStart: wall.end,
                lineEnd: extendedPoint
            )
            if distToLine < threshold {
                guides.append(GuideLine(
                    start: wall.end,
                    end: current,
                    type: .extension_
                ))
            }
        }

        return guides
    }

    // MARK: - Geometry Helpers

    private func distanceFromPointToLine(
        point: SerializablePoint,
        lineStart: SerializablePoint,
        lineEnd: SerializablePoint
    ) -> Double {
        let dx = lineEnd.x - lineStart.x
        let dy = lineEnd.y - lineStart.y
        let lengthSq = dx * dx + dy * dy
        guard lengthSq > 0 else { return point.distance(to: lineStart) }

        let num = abs(dy * point.x - dx * point.y + lineEnd.x * lineStart.y - lineEnd.y * lineStart.x)
        return num / sqrt(lengthSq)
    }
}
