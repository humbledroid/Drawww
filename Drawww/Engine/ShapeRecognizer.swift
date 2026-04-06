import Foundation
import CoreGraphics

/// Recognizes rough freehand strokes and converts them to clean geometric shapes.
/// This is what makes it feel like paper — sketch roughly, get clean output.
struct ShapeRecognizer {

    /// Minimum number of points to attempt recognition
    static let minPoints = 5

    /// Recognized shape types
    enum RecognizedShape {
        case line(start: SerializablePoint, end: SerializablePoint)
        case rectangle(origin: SerializablePoint, width: Double, height: Double, angle: Double)
        case circle(center: SerializablePoint, radius: Double)
        case arc(center: SerializablePoint, radius: Double, startAngle: Double, endAngle: Double)
        case lShape(corner: SerializablePoint, wing1End: SerializablePoint, wing2End: SerializablePoint)
        case triangle(p1: SerializablePoint, p2: SerializablePoint, p3: SerializablePoint)
        case unrecognized(points: [SerializablePoint])
    }

    /// Attempt to recognize a shape from a series of points (from a pencil stroke)
    static func recognize(points: [SerializablePoint]) -> RecognizedShape {
        guard points.count >= minPoints else {
            if points.count >= 2 {
                return .line(start: points.first!, end: points.last!)
            }
            return .unrecognized(points: points)
        }

        // Check if the stroke is closed (start ≈ end)
        let isClosed = points.first!.distance(to: points.last!) < averageSegmentLength(points) * 2.5

        if !isClosed {
            // Open stroke — check for line
            if isApproximatelyLine(points) {
                return .line(start: points.first!, end: points.last!)
            }
            // Check for arc
            if let arc = detectArc(points) {
                return arc
            }
            return .unrecognized(points: points)
        }

        // Closed stroke — find corners
        let corners = detectCorners(points)

        if corners.count == 3 {
            return .triangle(p1: corners[0], p2: corners[1], p3: corners[2])
        }

        if corners.count == 4 {
            // Check if it's a rectangle (all angles ≈ 90°)
            if isApproximatelyRectangle(corners) {
                let (origin, width, height, angle) = fitRectangle(corners)
                return .rectangle(origin: origin, width: width, height: height, angle: angle)
            }
            // Check for L-shape
            if let lShape = detectLShape(corners) {
                return lShape
            }
        }

        // Check for circle
        if let circle = detectCircle(points) {
            return circle
        }

        return .unrecognized(points: points)
    }

    // MARK: - Line Detection

    /// Check if points roughly form a straight line
    static func isApproximatelyLine(_ points: [SerializablePoint]) -> Bool {
        guard points.count >= 2 else { return false }

        let start = points.first!
        let end = points.last!
        let lineLength = start.distance(to: end)

        guard lineLength > 10 else { return false }

        // Calculate max perpendicular distance from the line
        var maxDist: Double = 0
        for point in points {
            let dist = perpendicularDistance(point: point, lineStart: start, lineEnd: end)
            maxDist = max(maxDist, dist)
        }

        // If max deviation is < 8% of line length, it's a line
        return maxDist / lineLength < 0.08
    }

    // MARK: - Circle Detection

    static func detectCircle(_ points: [SerializablePoint]) -> RecognizedShape? {
        // Find centroid
        let cx = points.map(\.x).reduce(0, +) / Double(points.count)
        let cy = points.map(\.y).reduce(0, +) / Double(points.count)
        let center = SerializablePoint(x: cx, y: cy)

        // Average radius
        let distances = points.map { center.distance(to: $0) }
        let avgRadius = distances.reduce(0, +) / Double(distances.count)

        guard avgRadius > 10 else { return nil }

        // Check variance — if all points are roughly equidistant from center, it's a circle
        let maxDeviation = distances.map { abs($0 - avgRadius) }.max() ?? .infinity

        if maxDeviation / avgRadius < 0.2 {
            return .circle(center: center, radius: avgRadius)
        }

        return nil
    }

    // MARK: - Arc Detection

    static func detectArc(_ points: [SerializablePoint]) -> RecognizedShape? {
        guard points.count >= 8 else { return nil }

        // Use three points (start, middle, end) to find a circle
        let start = points.first!
        let mid = points[points.count / 2]
        let end = points.last!

        guard let center = circumcenter(p1: start, p2: mid, p3: end) else { return nil }

        let r1 = center.distance(to: start)
        let r2 = center.distance(to: mid)
        let r3 = center.distance(to: end)
        let avgRadius = (r1 + r2 + r3) / 3.0

        // Check that all points are roughly on this circle
        let maxDev = points.map { abs(center.distance(to: $0) - avgRadius) }.max() ?? .infinity
        guard maxDev / avgRadius < 0.2 else { return nil }

        let startAngle = atan2(start.y - center.y, start.x - center.x)
        let endAngle = atan2(end.y - center.y, end.x - center.x)

        return .arc(center: center, radius: avgRadius, startAngle: startAngle, endAngle: endAngle)
    }

    // MARK: - Corner Detection (Ramer-Douglas-Peucker inspired)

    static func detectCorners(_ points: [SerializablePoint]) -> [SerializablePoint] {
        guard points.count >= 4 else { return points }

        // Calculate angle changes along the path
        var corners: [SerializablePoint] = []
        let step = max(1, points.count / 30) // sample every Nth point

        var angles: [(index: Int, angle: Double)] = []
        for i in stride(from: step, to: points.count - step, by: step) {
            let prev = points[max(0, i - step)]
            let curr = points[i]
            let next = points[min(points.count - 1, i + step)]

            let angle1 = atan2(curr.y - prev.y, curr.x - prev.x)
            let angle2 = atan2(next.y - curr.y, next.x - curr.x)
            var angleDiff = abs(angle2 - angle1)
            if angleDiff > .pi { angleDiff = 2 * .pi - angleDiff }

            angles.append((index: i, angle: angleDiff))
        }

        // Find peaks in angle change (these are corners)
        let threshold: Double = .pi / 4  // 45 degrees
        for (i, item) in angles.enumerated() {
            if item.angle > threshold {
                // Check it's a local maximum
                let prevAngle = i > 0 ? angles[i - 1].angle : 0
                let nextAngle = i < angles.count - 1 ? angles[i + 1].angle : 0
                if item.angle >= prevAngle && item.angle >= nextAngle {
                    corners.append(points[item.index])
                }
            }
        }

        return corners
    }

    // MARK: - Rectangle Fitting

    static func isApproximatelyRectangle(_ corners: [SerializablePoint]) -> Bool {
        guard corners.count == 4 else { return false }

        // Check all four angles are roughly 90°
        for i in 0..<4 {
            let prev = corners[(i + 3) % 4]
            let curr = corners[i]
            let next = corners[(i + 1) % 4]

            let v1x = prev.x - curr.x
            let v1y = prev.y - curr.y
            let v2x = next.x - curr.x
            let v2y = next.y - curr.y

            let dot = v1x * v2x + v1y * v2y
            let len1 = sqrt(v1x * v1x + v1y * v1y)
            let len2 = sqrt(v2x * v2x + v2y * v2y)

            guard len1 > 0 && len2 > 0 else { return false }

            let cosAngle = dot / (len1 * len2)
            // cos(90°) = 0, allow ±20° tolerance
            if abs(cosAngle) > 0.35 { return false }
        }

        return true
    }

    static func fitRectangle(_ corners: [SerializablePoint]) -> (origin: SerializablePoint, width: Double, height: Double, angle: Double) {
        // Use first edge to determine rotation angle
        let angle = atan2(corners[1].y - corners[0].y, corners[1].x - corners[0].x)
        let width = corners[0].distance(to: corners[1])
        let height = corners[1].distance(to: corners[2])

        // Origin is the top-left corner (smallest x+y after rotation)
        let origin = corners[0]

        return (origin, width, height, angle)
    }

    // MARK: - L-Shape Detection

    static func detectLShape(_ corners: [SerializablePoint]) -> RecognizedShape? {
        // An L-shape has one reflex angle (> 180°)
        for i in 0..<corners.count {
            let prev = corners[(i + corners.count - 1) % corners.count]
            let curr = corners[i]
            let next = corners[(i + 1) % corners.count]

            let cross = (curr.x - prev.x) * (next.y - prev.y) - (curr.y - prev.y) * (next.x - prev.x)

            if cross < 0 { // Reflex angle found
                return .lShape(corner: curr, wing1End: prev, wing2End: next)
            }
        }
        return nil
    }

    // MARK: - Geometry Helpers

    static func perpendicularDistance(point: SerializablePoint, lineStart: SerializablePoint, lineEnd: SerializablePoint) -> Double {
        let dx = lineEnd.x - lineStart.x
        let dy = lineEnd.y - lineStart.y
        let lengthSq = dx * dx + dy * dy
        guard lengthSq > 0 else { return point.distance(to: lineStart) }

        let num = abs(dy * point.x - dx * point.y + lineEnd.x * lineStart.y - lineEnd.y * lineStart.x)
        return num / sqrt(lengthSq)
    }

    static func averageSegmentLength(_ points: [SerializablePoint]) -> Double {
        guard points.count >= 2 else { return 0 }
        var total: Double = 0
        for i in 1..<points.count {
            total += points[i - 1].distance(to: points[i])
        }
        return total / Double(points.count - 1)
    }

    /// Find the circumcenter of three points (center of circle through all three)
    static func circumcenter(p1: SerializablePoint, p2: SerializablePoint, p3: SerializablePoint) -> SerializablePoint? {
        let ax = p1.x, ay = p1.y
        let bx = p2.x, by = p2.y
        let cx = p3.x, cy = p3.y

        let d = 2 * (ax * (by - cy) + bx * (cy - ay) + cx * (ay - by))
        guard abs(d) > 1e-10 else { return nil }

        let ux = ((ax * ax + ay * ay) * (by - cy) + (bx * bx + by * by) * (cy - ay) + (cx * cx + cy * cy) * (ay - by)) / d
        let uy = ((ax * ax + ay * ay) * (cx - bx) + (bx * bx + by * by) * (ax - cx) + (cx * cx + cy * cy) * (bx - ax)) / d

        return SerializablePoint(x: ux, y: uy)
    }
}
