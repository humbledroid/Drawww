import Foundation
import CoreGraphics

/// Core geometry calculations for floor plan operations
struct GeometryEngine {

    // MARK: - Room Area Detection

    /// Attempts to find closed polygons from wall segments and returns their area
    static func detectRooms(from walls: [WallSegment]) -> [(polygon: [SerializablePoint], area: Double, center: SerializablePoint)] {
        // Build adjacency graph from wall endpoints
        let graph = buildAdjacencyGraph(from: walls, threshold: 5.0)
        let cycles = findMinimalCycles(in: graph)

        return cycles.map { cycle in
            let area = polygonArea(cycle)
            let center = polygonCentroid(cycle)
            return (polygon: cycle, area: abs(area), center: center)
        }
    }

    /// Calculate the area of a polygon using the shoelace formula
    static func polygonArea(_ points: [SerializablePoint]) -> Double {
        guard points.count >= 3 else { return 0 }

        var area = 0.0
        let n = points.count
        for i in 0..<n {
            let j = (i + 1) % n
            area += points[i].x * points[j].y
            area -= points[j].x * points[i].y
        }
        return area / 2.0
    }

    /// Calculate the centroid of a polygon
    static func polygonCentroid(_ points: [SerializablePoint]) -> SerializablePoint {
        guard points.count >= 3 else {
            if let first = points.first { return first }
            return SerializablePoint(x: 0, y: 0)
        }

        var cx = 0.0
        var cy = 0.0
        let area = polygonArea(points)
        guard abs(area) > 0.001 else {
            // Degenerate polygon, return average
            let avgX = points.map(\.x).reduce(0, +) / Double(points.count)
            let avgY = points.map(\.y).reduce(0, +) / Double(points.count)
            return SerializablePoint(x: avgX, y: avgY)
        }

        let n = points.count
        for i in 0..<n {
            let j = (i + 1) % n
            let cross = points[i].x * points[j].y - points[j].x * points[i].y
            cx += (points[i].x + points[j].x) * cross
            cy += (points[i].y + points[j].y) * cross
        }

        let factor = 1.0 / (6.0 * area)
        return SerializablePoint(x: cx * factor, y: cy * factor)
    }

    // MARK: - Hit Testing

    /// Test if a point is near a wall segment
    static func hitTestWall(_ point: SerializablePoint, wall: WallSegment, threshold: Double) -> Bool {
        return wall.distanceTo(point: point) < threshold
    }

    /// Find all walls near a point, sorted by distance
    static func wallsNearPoint(_ point: SerializablePoint, walls: [WallSegment], threshold: Double) -> [WallSegment] {
        return walls
            .filter { $0.distanceTo(point: point) < threshold }
            .sorted { $0.distanceTo(point: point) < $1.distanceTo(point: point) }
    }

    // MARK: - Wall Intersection

    /// Find intersection point of two wall segments (if any)
    static func wallIntersection(_ wall1: WallSegment, _ wall2: WallSegment) -> SerializablePoint? {
        return lineIntersection(
            p1: wall1.start, p2: wall1.end,
            p3: wall2.start, p4: wall2.end
        )
    }

    /// Line-line intersection using parametric form
    static func lineIntersection(
        p1: SerializablePoint, p2: SerializablePoint,
        p3: SerializablePoint, p4: SerializablePoint
    ) -> SerializablePoint? {
        let d1x = p2.x - p1.x
        let d1y = p2.y - p1.y
        let d2x = p4.x - p3.x
        let d2y = p4.y - p3.y

        let denom = d1x * d2y - d1y * d2x
        guard abs(denom) > 1e-10 else { return nil } // Parallel

        let t = ((p3.x - p1.x) * d2y - (p3.y - p1.y) * d2x) / denom
        let u = ((p3.x - p1.x) * d1y - (p3.y - p1.y) * d1x) / denom

        // Check if intersection is within both segments
        guard t >= 0 && t <= 1 && u >= 0 && u <= 1 else { return nil }

        return SerializablePoint(
            x: p1.x + t * d1x,
            y: p1.y + t * d1y
        )
    }

    // MARK: - Angle Between Walls

    /// Returns the angle in degrees between two walls at their shared endpoint
    static func angleBetweenWalls(_ wall1: WallSegment, _ wall2: WallSegment, at point: SerializablePoint) -> Double? {
        let threshold = 5.0

        // Determine direction vectors pointing away from the shared point
        let dir1: SerializablePoint
        if wall1.start.distance(to: point) < threshold {
            dir1 = SerializablePoint(x: wall1.end.x - wall1.start.x, y: wall1.end.y - wall1.start.y)
        } else if wall1.end.distance(to: point) < threshold {
            dir1 = SerializablePoint(x: wall1.start.x - wall1.end.x, y: wall1.start.y - wall1.end.y)
        } else {
            return nil
        }

        let dir2: SerializablePoint
        if wall2.start.distance(to: point) < threshold {
            dir2 = SerializablePoint(x: wall2.end.x - wall2.start.x, y: wall2.end.y - wall2.start.y)
        } else if wall2.end.distance(to: point) < threshold {
            dir2 = SerializablePoint(x: wall2.start.x - wall2.end.x, y: wall2.start.y - wall2.end.y)
        } else {
            return nil
        }

        let dot = dir1.x * dir2.x + dir1.y * dir2.y
        let len1 = sqrt(dir1.x * dir1.x + dir1.y * dir1.y)
        let len2 = sqrt(dir2.x * dir2.x + dir2.y * dir2.y)
        guard len1 > 0 && len2 > 0 else { return nil }

        let cosAngle = max(-1, min(1, dot / (len1 * len2)))
        return acos(cosAngle) * 180.0 / .pi
    }

    // MARK: - Adjacency Graph (for room detection)

    struct GraphNode: Hashable {
        let x: Double
        let y: Double

        init(_ point: SerializablePoint) {
            // Round to avoid floating point issues
            self.x = (point.x * 10).rounded() / 10
            self.y = (point.y * 10).rounded() / 10
        }

        var point: SerializablePoint {
            SerializablePoint(x: x, y: y)
        }
    }

    private static func buildAdjacencyGraph(from walls: [WallSegment], threshold: Double) -> [GraphNode: Set<GraphNode>] {
        var graph: [GraphNode: Set<GraphNode>] = [:]

        for wall in walls {
            let startNode = GraphNode(wall.start)
            let endNode = GraphNode(wall.end)

            graph[startNode, default: []].insert(endNode)
            graph[endNode, default: []].insert(startNode)
        }

        return graph
    }

    private static func findMinimalCycles(in graph: [GraphNode: Set<GraphNode>]) -> [[SerializablePoint]] {
        // Simple cycle detection: find all triangles and quads
        // Full implementation would use a proper minimal cycle basis algorithm
        var cycles: [[SerializablePoint]] = []
        let nodes = Array(graph.keys)

        // Find triangles
        for i in 0..<nodes.count {
            for j in (i+1)..<nodes.count {
                guard graph[nodes[i]]?.contains(nodes[j]) == true else { continue }
                for k in (j+1)..<nodes.count {
                    guard graph[nodes[j]]?.contains(nodes[k]) == true,
                          graph[nodes[k]]?.contains(nodes[i]) == true else { continue }
                    cycles.append([nodes[i].point, nodes[j].point, nodes[k].point])
                }
            }
        }

        // Find quads
        for i in 0..<nodes.count {
            let neighbors = Array(graph[nodes[i]] ?? [])
            for j in 0..<neighbors.count {
                for k in (j+1)..<neighbors.count {
                    let commonNeighbors = (graph[neighbors[j]] ?? []).intersection(graph[neighbors[k]] ?? [])
                    for common in commonNeighbors where common != nodes[i] {
                        let cycle = [nodes[i].point, neighbors[j].point, common.point, neighbors[k].point]
                        cycles.append(cycle)
                    }
                }
            }
        }

        return cycles
    }
}
