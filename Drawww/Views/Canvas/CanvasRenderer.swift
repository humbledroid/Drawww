import SwiftUI

/// Custom Canvas renderer for walls, shapes, measurements, elevation symbols, and guides.
struct CanvasRenderer: View {
    let walls: [WallSegment]
    let draftingShapes: [DraftingShape]
    let sectionCuts: [SectionCutLine]
    let heightMarkers: [HeightMarker]
    let stairs: [StairSymbol]
    let hatchRegions: [HatchRegion]
    let elevationArrows: [ElevationArrow]
    let canvasState: CanvasState
    let unitSystem: UnitSystem
    let scale: Double
    let canvasSize: CGSize

    // Theme colors
    private let wallColor = Color.primary
    private let wallSelectedColor = Color.blue
    private let gridColor = Color.gray.opacity(0.15)
    private let guideColor = Color.orange.opacity(0.6)
    private let measurementColor = Color.blue
    private let snapPointColor = Color.green
    private let drawingWallColor = Color.blue.opacity(0.8)
    private let constructionColor = Color.cyan.opacity(0.35)
    private let sectionCutColor = Color.red
    private let elevationColor = Color.purple
    private let hatchColor = Color.gray.opacity(0.4)
    private let stairColor = Color.brown

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let offset = canvasState.viewportOffset
            let zoom = canvasState.viewportZoom

            func toScreen(_ p: SerializablePoint) -> CGPoint {
                CGPoint(
                    x: p.x * Double(zoom) + Double(center.x) + Double(offset.width),
                    y: p.y * Double(zoom) + Double(center.y) + Double(offset.height)
                )
            }

            // 1. Grid
            if canvasState.showGrid {
                drawGrid(context: &context, size: size, center: center, offset: offset, zoom: zoom)
            }

            // 2. Hatch regions
            drawHatchRegions(context: &context, toScreen: toScreen, zoom: zoom)

            // 3. Guide lines
            for guide in canvasState.activeGuideLines {
                var path = Path()
                path.move(to: toScreen(guide.start))
                path.addLine(to: toScreen(guide.end))
                context.stroke(path, with: .color(guideColor), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
            }

            // 4. Construction lines (if visible)
            if canvasState.showConstructionLines {
                drawConstructionLines(context: &context, toScreen: toScreen, zoom: zoom)
            }

            // 5. Committed walls
            for wall in walls {
                drawWall(context: &context, wall: wall, toScreen: toScreen, zoom: zoom)
            }

            // 5b. Angle annotations at wall junctions
            if canvasState.showAngles {
                drawAngleAnnotations(context: &context, toScreen: toScreen, zoom: zoom)
            }

            // 6. Drafting shapes
            drawDraftingShapes(context: &context, toScreen: toScreen, zoom: zoom)

            // 7. Section cut lines
            drawSectionCuts(context: &context, toScreen: toScreen, zoom: zoom)

            // 8. Stair symbols
            drawStairs(context: &context, toScreen: toScreen, zoom: zoom)

            // 9. Height markers
            drawHeightMarkers(context: &context, toScreen: toScreen, zoom: zoom)

            // 10. Elevation arrows
            drawElevationArrows(context: &context, toScreen: toScreen, zoom: zoom)

            // 11. In-progress drawing
            drawInProgress(context: &context, toScreen: toScreen, zoom: zoom)

            // 12. Room areas
            drawRoomAreas(context: &context, toScreen: toScreen)
        }
    }

    // MARK: - Grid

    private func drawGrid(context: inout GraphicsContext, size: CGSize, center: CGPoint, offset: CGSize, zoom: CGFloat) {
        let gridSize = canvasState.gridSpacing * Double(zoom)
        guard gridSize > 8 else { return }

        let startX = (Double(center.x) + Double(offset.width)).truncatingRemainder(dividingBy: gridSize)
        let startY = (Double(center.y) + Double(offset.height)).truncatingRemainder(dividingBy: gridSize)

        var gridPath = Path()
        var x = startX
        while x < Double(size.width) {
            gridPath.move(to: CGPoint(x: x, y: 0))
            gridPath.addLine(to: CGPoint(x: x, y: Double(size.height)))
            x += gridSize
        }
        var y = startY
        while y < Double(size.height) {
            gridPath.move(to: CGPoint(x: 0, y: y))
            gridPath.addLine(to: CGPoint(x: Double(size.width), y: y))
            y += gridSize
        }
        context.stroke(gridPath, with: .color(gridColor), lineWidth: 0.5)

        // Origin crosshair
        let originScreen = CGPoint(x: Double(center.x) + Double(offset.width), y: Double(center.y) + Double(offset.height))
        var originPath = Path()
        originPath.move(to: CGPoint(x: originScreen.x - 12, y: originScreen.y))
        originPath.addLine(to: CGPoint(x: originScreen.x + 12, y: originScreen.y))
        originPath.move(to: CGPoint(x: originScreen.x, y: originScreen.y - 12))
        originPath.addLine(to: CGPoint(x: originScreen.x, y: originScreen.y + 12))
        context.stroke(originPath, with: .color(.gray.opacity(0.4)), lineWidth: 1)
    }

    // MARK: - Walls

    private func drawWall(context: inout GraphicsContext, wall: WallSegment, toScreen: (SerializablePoint) -> CGPoint, zoom: CGFloat) {
        let isSelected = canvasState.selectedItems.contains(.wall(wall.id))
        let color = isSelected ? wallSelectedColor : wallColor
        let lineWidth = max(2, 3 * Double(zoom))

        var path = Path()
        path.move(to: toScreen(wall.start))
        path.addLine(to: toScreen(wall.end))
        context.stroke(path, with: .color(color), lineWidth: lineWidth)

        // Endpoint dots
        let dotRadius = max(3, 4 * Double(zoom))
        for endpoint in [wall.start, wall.end] {
            let pt = toScreen(endpoint)
            context.fill(Path(ellipseIn: CGRect(x: pt.x - dotRadius/2, y: pt.y - dotRadius/2, width: dotRadius, height: dotRadius)), with: .color(color))
        }

        // Measurement label
        drawMeasurementLabel(context: &context, start: wall.start, end: wall.end, length: wall.length, angle: wall.angle, toScreen: toScreen)
    }

    // MARK: - Measurement Labels

    private func drawMeasurementLabel(context: inout GraphicsContext, start: SerializablePoint, end: SerializablePoint, length: Double, angle: Double, toScreen: (SerializablePoint) -> CGPoint) {
        guard length > 1 else { return }
        let text = unitSystem.formatLength(length, scale: scale)
        let mid = start.midpoint(to: end)
        let screenMid = toScreen(mid)

        let offsetDist: Double = 16
        let labelPos = CGPoint(x: screenMid.x + cos(angle + .pi/2) * offsetDist, y: screenMid.y + sin(angle + .pi/2) * offsetDist)

        let textSize = estimateTextSize(text, fontSize: 11)
        let pill = CGRect(x: labelPos.x - textSize.width/2 - 4, y: labelPos.y - textSize.height/2 - 2, width: textSize.width + 8, height: textSize.height + 4)

        context.fill(Path(roundedRect: pill, cornerRadius: 3), with: .color(Color(.systemBackground).opacity(0.85)))
        context.stroke(Path(roundedRect: pill, cornerRadius: 3), with: .color(measurementColor.opacity(0.5)), lineWidth: 0.5)
        context.draw(
            Text(text).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundColor(measurementColor),
            at: labelPos
        )
    }

    // MARK: - Drafting Shapes

    private func drawDraftingShapes(context: inout GraphicsContext, toScreen: (SerializablePoint) -> CGPoint, zoom: CGFloat) {
        for shape in draftingShapes {
            if shape.isConstructionLine { continue } // drawn separately

            let style = shape.lineStyle
            let weight = shape.lineWeight
            let strokeStyle = StrokeStyle(lineWidth: weight.width * Double(zoom), dash: style.dashPattern)

            switch shape.shapeType {
            case .line:
                let s = toScreen(SerializablePoint(x: shape.x1, y: shape.y1))
                let e = toScreen(SerializablePoint(x: shape.x2, y: shape.y2))
                var path = Path()
                path.move(to: s)
                path.addLine(to: e)
                context.stroke(path, with: .color(.primary), style: strokeStyle)

            case .circle:
                let c = toScreen(SerializablePoint(x: shape.x1, y: shape.y1))
                let r = shape.x2 * Double(zoom)
                let rect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
                context.stroke(Path(ellipseIn: rect), with: .color(.primary), style: strokeStyle)

            case .arc:
                let c = toScreen(SerializablePoint(x: shape.x1, y: shape.y1))
                let r = shape.x2 * Double(zoom)
                var path = Path()
                path.addArc(center: c, radius: r, startAngle: .radians(shape.startAngle), endAngle: .radians(shape.endAngle), clockwise: false)
                context.stroke(path, with: .color(.primary), style: strokeStyle)

            case .rectangle:
                let origin = toScreen(SerializablePoint(x: shape.x1, y: shape.y1))
                let w = shape.x2 * Double(zoom)
                let h = shape.y2 * Double(zoom)
                let rect = CGRect(x: origin.x, y: origin.y, width: w, height: h)
                context.stroke(Path(rect), with: .color(.primary), style: strokeStyle)

            case .triangle:
                let p1 = toScreen(SerializablePoint(x: shape.x1, y: shape.y1))
                let p2 = toScreen(SerializablePoint(x: shape.x2, y: shape.y2))
                let p3 = toScreen(SerializablePoint(x: shape.x3, y: shape.y3))
                var path = Path()
                path.move(to: p1)
                path.addLine(to: p2)
                path.addLine(to: p3)
                path.closeSubpath()
                context.stroke(path, with: .color(.primary), style: strokeStyle)

            default:
                break
            }
        }
    }

    // MARK: - Construction Lines

    private func drawConstructionLines(context: inout GraphicsContext, toScreen: (SerializablePoint) -> CGPoint, zoom: CGFloat) {
        for shape in draftingShapes where shape.isConstructionLine {
            let s = toScreen(SerializablePoint(x: shape.x1, y: shape.y1))
            let e = toScreen(SerializablePoint(x: shape.x2, y: shape.y2))
            var path = Path()
            path.move(to: s)
            path.addLine(to: e)
            context.stroke(path, with: .color(constructionColor), style: StrokeStyle(lineWidth: 0.5 * Double(zoom), dash: [6, 8]))
        }
    }

    // MARK: - Section Cuts

    private func drawSectionCuts(context: inout GraphicsContext, toScreen: (SerializablePoint) -> CGPoint, zoom: CGFloat) {
        for cut in sectionCuts {
            let s = toScreen(cut.start)
            let e = toScreen(cut.end)

            // Thick dash-dot line
            var path = Path()
            path.move(to: s)
            path.addLine(to: e)
            context.stroke(path, with: .color(sectionCutColor), style: StrokeStyle(lineWidth: 2.5 * Double(zoom), dash: [12, 4, 2, 4]))

            // Arrow heads at both ends
            let arrowSize: Double = 10 * Double(zoom)
            let angle = cut.start.angle(to: cut.end)
            let perpAngle = cut.viewDirectionAngle

            for (point, screenPoint) in [(cut.start, s), (cut.end, e)] {
                // Triangle arrow pointing in view direction
                let tip = CGPoint(x: screenPoint.x + cos(perpAngle) * arrowSize, y: screenPoint.y + sin(perpAngle) * arrowSize)
                let left = CGPoint(x: screenPoint.x + cos(perpAngle + 2.5) * arrowSize * 0.6, y: screenPoint.y + sin(perpAngle + 2.5) * arrowSize * 0.6)
                let right = CGPoint(x: screenPoint.x + cos(perpAngle - 2.5) * arrowSize * 0.6, y: screenPoint.y + sin(perpAngle - 2.5) * arrowSize * 0.6)

                var arrow = Path()
                arrow.move(to: tip)
                arrow.addLine(to: left)
                arrow.addLine(to: right)
                arrow.closeSubpath()
                context.fill(arrow, with: .color(sectionCutColor))
            }

            // Labels at endpoints
            context.draw(
                Text(cut.label).font(.system(size: 12 * Double(zoom), weight: .bold)).foregroundColor(sectionCutColor),
                at: CGPoint(x: s.x - 15 * Double(zoom), y: s.y)
            )
        }
    }

    // MARK: - Stairs

    private func drawStairs(context: inout GraphicsContext, toScreen: (SerializablePoint) -> CGPoint, zoom: CGFloat) {
        for stair in stairs {
            let origin = toScreen(stair.origin)
            let w = stair.width * Double(zoom)
            let totalLen = stair.totalLength * Double(zoom)
            let treadD = stair.treadDepth * Double(zoom)

            // Stair outline
            let rect = CGRect(x: origin.x, y: origin.y, width: w, height: totalLen)
            context.stroke(Path(rect), with: .color(stairColor), lineWidth: 1.5 * Double(zoom))

            // Tread lines
            for i in 1..<stair.riserCount {
                let yOffset = Double(i) * treadD
                var tread = Path()
                tread.move(to: CGPoint(x: origin.x, y: origin.y + yOffset))
                tread.addLine(to: CGPoint(x: origin.x + w, y: origin.y + yOffset))
                context.stroke(tread, with: .color(stairColor), lineWidth: 0.5 * Double(zoom))
            }

            // Direction arrow (diagonal line with arrowhead)
            let arrowStartY = stair.goesUp ? origin.y + totalLen : origin.y
            let arrowEndY = stair.goesUp ? origin.y : origin.y + totalLen
            let midX = origin.x + w / 2

            var arrowPath = Path()
            arrowPath.move(to: CGPoint(x: midX, y: arrowStartY))
            arrowPath.addLine(to: CGPoint(x: midX, y: arrowEndY))
            context.stroke(arrowPath, with: .color(stairColor), lineWidth: 1.5 * Double(zoom))

            // "UP" or "DN" label
            let label = stair.goesUp ? "UP" : "DN"
            context.draw(
                Text(label).font(.system(size: 9 * Double(zoom), weight: .bold)).foregroundColor(stairColor),
                at: CGPoint(x: midX, y: (arrowStartY + arrowEndY) / 2)
            )
        }
    }

    // MARK: - Height Markers

    private func drawHeightMarkers(context: inout GraphicsContext, toScreen: (SerializablePoint) -> CGPoint, zoom: CGFloat) {
        for marker in heightMarkers {
            let pos = toScreen(marker.position)
            let r: Double = 14 * Double(zoom)

            // Circle
            let circleRect = CGRect(x: pos.x - r, y: pos.y - r, width: r * 2, height: r * 2)
            context.stroke(Path(ellipseIn: circleRect), with: .color(elevationColor), lineWidth: 1.5 * Double(zoom))

            // Crosshair inside
            var cross = Path()
            cross.move(to: CGPoint(x: pos.x - r * 0.6, y: pos.y))
            cross.addLine(to: CGPoint(x: pos.x + r * 0.6, y: pos.y))
            context.stroke(cross, with: .color(elevationColor), lineWidth: 0.5 * Double(zoom))

            // Label below
            context.draw(
                Text(marker.label).font(.system(size: 10 * Double(zoom), weight: .medium)).foregroundColor(elevationColor),
                at: CGPoint(x: pos.x, y: pos.y + r + 10 * Double(zoom))
            )
        }
    }

    // MARK: - Elevation Arrows

    private func drawElevationArrows(context: inout GraphicsContext, toScreen: (SerializablePoint) -> CGPoint, zoom: CGFloat) {
        for arrow in elevationArrows {
            let pos = toScreen(arrow.position)
            let r: Double = 16 * Double(zoom)
            let angle = arrow.directionAngle

            // Circle
            let circleRect = CGRect(x: pos.x - r, y: pos.y - r, width: r * 2, height: r * 2)
            context.fill(Path(ellipseIn: circleRect), with: .color(elevationColor.opacity(0.15)))
            context.stroke(Path(ellipseIn: circleRect), with: .color(elevationColor), lineWidth: 1.5 * Double(zoom))

            // Arrow inside circle pointing in direction
            let tipX = pos.x + cos(angle) * r * 0.7
            let tipY = pos.y + sin(angle) * r * 0.7
            let baseX = pos.x - cos(angle) * r * 0.3
            let baseY = pos.y - sin(angle) * r * 0.3

            var arrowPath = Path()
            arrowPath.move(to: CGPoint(x: baseX, y: baseY))
            arrowPath.addLine(to: CGPoint(x: tipX, y: tipY))
            context.stroke(arrowPath, with: .color(elevationColor), lineWidth: 2 * Double(zoom))

            // Label
            context.draw(
                Text(arrow.label).font(.system(size: 11 * Double(zoom), weight: .bold)).foregroundColor(elevationColor),
                at: CGPoint(x: pos.x, y: pos.y + r + 12 * Double(zoom))
            )
        }
    }

    // MARK: - Hatch Regions

    private func drawHatchRegions(context: inout GraphicsContext, toScreen: (SerializablePoint) -> CGPoint, zoom: CGFloat) {
        for region in hatchRegions {
            let screenPoints = region.points.map { toScreen($0) }
            guard screenPoints.count >= 3 else { continue }

            // Draw boundary
            var boundary = Path()
            boundary.move(to: screenPoints[0])
            for pt in screenPoints.dropFirst() { boundary.addLine(to: pt) }
            boundary.closeSubpath()
            context.stroke(boundary, with: .color(hatchColor), lineWidth: 0.5 * Double(zoom))

            // Draw hatch lines inside (simplified — parallel lines clipped to polygon)
            drawHatchPattern(context: &context, polygon: screenPoints, pattern: region.patternType, spacing: region.patternSpacing * Double(zoom))
        }
    }

    private func drawHatchPattern(context: inout GraphicsContext, polygon: [CGPoint], pattern: HatchPatternType, spacing: Double) {
        guard let bounds = boundingBox(polygon) else { return }
        let angle: Double
        switch pattern {
        case .diagonal: angle = .pi / 4
        case .crosshatch: angle = .pi / 4
        case .horizontal: angle = 0
        case .brick: angle = 0
        case .concrete: angle = .pi / 6
        case .insulation: angle = .pi / 4
        }

        // Generate parallel lines at the given angle
        let diagLength = sqrt(bounds.width * bounds.width + bounds.height * bounds.height)
        let cx = bounds.midX
        let cy = bounds.midY

        var y = -diagLength / 2
        while y < diagLength / 2 {
            let x1 = cx - diagLength / 2
            let x2 = cx + diagLength / 2

            let cos_a = cos(angle)
            let sin_a = sin(angle)

            let p1 = CGPoint(x: cx + x1 * cos_a - y * sin_a, y: cy + x1 * sin_a + y * cos_a)
            let p2 = CGPoint(x: cx + x2 * cos_a - y * sin_a, y: cy + x2 * sin_a + y * cos_a)

            var line = Path()
            line.move(to: p1)
            line.addLine(to: p2)
            context.stroke(line, with: .color(hatchColor), lineWidth: 0.5)

            y += max(spacing, 4)
        }
    }

    // MARK: - In-Progress Drawing

    private func drawInProgress(context: inout GraphicsContext, toScreen: (SerializablePoint) -> CGPoint, zoom: CGFloat) {
        guard canvasState.isDrawing,
              let start = canvasState.drawingStartPoint,
              let current = canvasState.drawingCurrentPoint else { return }

        let tool = canvasState.activeTool

        // Draw the in-progress shape
        switch tool {
        case .wall, .line, .constructionLine, .sectionCut:
            var path = Path()
            path.move(to: toScreen(start))
            path.addLine(to: toScreen(current))
            let color: Color = tool == .constructionLine ? constructionColor :
                                tool == .sectionCut ? sectionCutColor : drawingWallColor
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: max(2, 3 * Double(zoom)), dash: [8, 4]))

        case .circle:
            let c = toScreen(start)
            let r = start.distance(to: current) * Double(zoom)
            let rect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
            context.stroke(Path(ellipseIn: rect), with: .color(drawingWallColor), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))

        case .rectangle:
            let s = toScreen(start)
            let e = toScreen(current)
            let rect = CGRect(x: min(s.x, e.x), y: min(s.y, e.y), width: abs(e.x - s.x), height: abs(e.y - s.y))
            context.stroke(Path(rect), with: .color(drawingWallColor), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))

        case .arc:
            let c = toScreen(start)
            let r = start.distance(to: current) * Double(zoom)
            var path = Path()
            let startAngle = start.angle(to: current)
            path.addArc(center: c, radius: r, startAngle: .radians(startAngle), endAngle: .radians(startAngle + .pi), clockwise: false)
            context.stroke(path, with: .color(drawingWallColor), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))

        case .smartSketch:
            // Draw collected points as a polyline
            let points = canvasState.smartSketchPoints
            if points.count >= 2 {
                var path = Path()
                path.move(to: toScreen(points[0]))
                for pt in points.dropFirst() { path.addLine(to: toScreen(pt)) }
                context.stroke(path, with: .color(.orange.opacity(0.6)), lineWidth: 1.5)
            }

        default:
            break
        }

        // Live measurement for line-based tools
        if [.wall, .line, .constructionLine, .sectionCut].contains(tool) {
            let length = start.distance(to: current)
            if length > 5 {
                let mid = start.midpoint(to: current)
                let screenMid = toScreen(mid)
                let text = unitSystem.formatLength(length, scale: scale)

                let textSize = estimateTextSize(text, fontSize: 13)
                let pill = CGRect(x: screenMid.x - textSize.width/2 - 6, y: screenMid.y - 22, width: textSize.width + 12, height: 20)
                context.fill(Path(roundedRect: pill, cornerRadius: 4), with: .color(.blue.opacity(0.9)))
                context.draw(
                    Text(text).font(.system(size: 13, weight: .semibold, design: .monospaced)).foregroundColor(.white),
                    at: CGPoint(x: screenMid.x, y: screenMid.y - 12)
                )
            }
        }

        // Live angle display when drawing from an existing wall endpoint
        if canvasState.showAngles && [.wall, .line, .constructionLine].contains(tool) {
            drawLiveAngle(context: &context, start: start, current: current, toScreen: toScreen, zoom: zoom)
        }

        // Snap indicator dot
        let endScreen = toScreen(current)
        context.fill(
            Path(ellipseIn: CGRect(x: endScreen.x - 5, y: endScreen.y - 5, width: 10, height: 10)),
            with: .color(snapPointColor)
        )
    }

    // MARK: - Angle Annotations

    private let angleColor = Color.orange
    private let angleArcRadius: Double = 28 // base radius in canvas pts

    /// Draw angle arcs at every junction where two or more walls/lines share an endpoint.
    private func drawAngleAnnotations(context: inout GraphicsContext, toScreen: (SerializablePoint) -> CGPoint, zoom: CGFloat) {
        let threshold = 5.0 // max distance to consider endpoints "shared"

        // Collect all line segments (endpoint, direction) from walls, lines, rectangle edges, triangle edges
        struct Segment {
            let endpoint: SerializablePoint
            let dir: Double
        }
        var allSegments: [Segment] = []

        // Walls
        for wall in walls {
            let dir = atan2(wall.end.y - wall.start.y, wall.end.x - wall.start.x)
            allSegments.append(Segment(endpoint: wall.start, dir: dir))
            allSegments.append(Segment(endpoint: wall.end, dir: dir + .pi))
        }

        // Drafting lines
        for shape in draftingShapes where !shape.isConstructionLine {
            switch shape.shapeType {
            case .line:
                let sp = SerializablePoint(x: shape.x1, y: shape.y1)
                let ep = SerializablePoint(x: shape.x2, y: shape.y2)
                let dir = atan2(ep.y - sp.y, ep.x - sp.x)
                allSegments.append(Segment(endpoint: sp, dir: dir))
                allSegments.append(Segment(endpoint: ep, dir: dir + .pi))

            case .rectangle:
                // 4 corners, 4 edges
                let o = SerializablePoint(x: shape.x1, y: shape.y1)
                let w = shape.x2, h = shape.y2
                let corners = [
                    o,
                    SerializablePoint(x: o.x + w, y: o.y),
                    SerializablePoint(x: o.x + w, y: o.y + h),
                    SerializablePoint(x: o.x, y: o.y + h)
                ]
                for i in 0..<4 {
                    let a = corners[i]
                    let b = corners[(i + 1) % 4]
                    let dir = atan2(b.y - a.y, b.x - a.x)
                    allSegments.append(Segment(endpoint: a, dir: dir))
                    allSegments.append(Segment(endpoint: b, dir: dir + .pi))
                }

            case .triangle:
                let pts = [
                    SerializablePoint(x: shape.x1, y: shape.y1),
                    SerializablePoint(x: shape.x2, y: shape.y2),
                    SerializablePoint(x: shape.x3, y: shape.y3)
                ]
                for i in 0..<3 {
                    let a = pts[i]
                    let b = pts[(i + 1) % 3]
                    let dir = atan2(b.y - a.y, b.x - a.x)
                    allSegments.append(Segment(endpoint: a, dir: dir))
                    allSegments.append(Segment(endpoint: b, dir: dir + .pi))
                }

            default:
                break
            }
        }

        // Cluster segments by proximity into junctions
        var junctions: [(point: SerializablePoint, dirs: [Double])] = []

        for seg in allSegments {
            var found = false
            for i in 0..<junctions.count {
                if junctions[i].point.distance(to: seg.endpoint) < threshold {
                    junctions[i].dirs.append(seg.dir)
                    found = true
                    break
                }
            }
            if !found {
                junctions.append((point: seg.endpoint, dirs: [seg.dir]))
            }
        }

        // For each junction with 2+ lines, draw angle arcs between consecutive pairs
        for junction in junctions {
            let directions = junction.dirs
            let point = junction.point
            guard directions.count >= 2 else { continue }

            // Normalize all directions to [0, 2π) and deduplicate near-identical angles
            let normalized = directions.map { d -> Double in
                var a = d
                while a < 0 { a += 2 * .pi }
                while a >= 2 * .pi { a -= 2 * .pi }
                return a
            }
            let unique = normalized.reduce(into: [Double]()) { result, angle in
                if !result.contains(where: { abs($0 - angle) < 0.05 }) {
                    result.append(angle)
                }
            }
            guard unique.count >= 2 else { continue }

            // Sort directions by angle
            let sorted = unique.sorted()

            // Draw angle arc between each consecutive pair
            for i in 0..<sorted.count {
                let j = (i + 1) % sorted.count
                let startAngle = sorted[i]
                let endAngle = sorted[j]

                // Ensure we get the smaller angle between the two
                var sweep = endAngle - startAngle
                if sweep < 0 { sweep += 2 * .pi }

                // Only show angles < 180° (the acute/right side)
                if sweep > .pi { continue }

                let degrees = sweep * 180.0 / .pi
                // Skip very small or very large (near-straight) angles
                if degrees < 2 || degrees > 178 { continue }

                let screenPt = toScreen(point)
                let r = angleArcRadius * Double(zoom)

                // Draw the arc
                var arcPath = Path()
                arcPath.addArc(
                    center: screenPt,
                    radius: r,
                    startAngle: .radians(startAngle),
                    endAngle: .radians(startAngle + sweep),
                    clockwise: false
                )
                context.stroke(arcPath, with: .color(angleColor), lineWidth: 1.5)

                // Right angle indicator: small square instead of arc
                if abs(degrees - 90) < 2 {
                    let sq: Double = 8 * Double(zoom)
                    let bisector = startAngle + sweep / 2
                    let cx = screenPt.x + cos(bisector) * sq * 0.9
                    let cy = screenPt.y + sin(bisector) * sq * 0.9

                    let corner1 = CGPoint(x: screenPt.x + cos(startAngle) * sq, y: screenPt.y + sin(startAngle) * sq)
                    let corner2 = CGPoint(x: cx, y: cy)
                    let corner3 = CGPoint(x: screenPt.x + cos(startAngle + sweep) * sq, y: screenPt.y + sin(startAngle + sweep) * sq)

                    var sqPath = Path()
                    sqPath.move(to: corner1)
                    sqPath.addLine(to: corner2)
                    sqPath.addLine(to: corner3)
                    context.stroke(sqPath, with: .color(angleColor), lineWidth: 1.5)
                }

                // Angle label
                let bisectorAngle = startAngle + sweep / 2
                let labelR = r + 14
                let labelPos = CGPoint(
                    x: screenPt.x + cos(bisectorAngle) * labelR,
                    y: screenPt.y + sin(bisectorAngle) * labelR
                )

                let angleText = String(format: "%.0f°", degrees)
                context.draw(
                    Text(angleText)
                        .font(.system(size: max(9, 10 * Double(zoom)), weight: .semibold, design: .rounded))
                        .foregroundColor(angleColor),
                    at: labelPos
                )
            }
        }
    }

    /// Show the angle between a wall being drawn and the existing wall it connects to.
    private func drawLiveAngle(context: inout GraphicsContext, start: SerializablePoint, current: SerializablePoint, toScreen: (SerializablePoint) -> CGPoint, zoom: CGFloat) {
        let threshold = 5.0
        let drawDir = atan2(current.y - start.y, current.x - start.x)

        // Find all existing walls whose endpoint matches the draw start
        var connectedDirs: [Double] = []
        for wall in walls {
            if wall.start.distance(to: start) < threshold {
                connectedDirs.append(atan2(wall.end.y - wall.start.y, wall.end.x - wall.start.x))
            } else if wall.end.distance(to: start) < threshold {
                connectedDirs.append(atan2(wall.start.y - wall.end.y, wall.start.x - wall.end.x))
            }
        }
        for shape in draftingShapes where shape.shapeType == .line && !shape.isConstructionLine {
            let sp = SerializablePoint(x: shape.x1, y: shape.y1)
            let ep = SerializablePoint(x: shape.x2, y: shape.y2)
            if sp.distance(to: start) < threshold {
                connectedDirs.append(atan2(ep.y - sp.y, ep.x - sp.x))
            } else if ep.distance(to: start) < threshold {
                connectedDirs.append(atan2(sp.y - ep.y, sp.x - ep.x))
            }
        }

        guard !connectedDirs.isEmpty else { return }

        let screenStart = toScreen(start)
        let r = angleArcRadius * Double(zoom)

        for existingDir in connectedDirs {
            var sweep = drawDir - existingDir
            // Normalize to [-pi, pi]
            while sweep > .pi { sweep -= 2 * .pi }
            while sweep < -.pi { sweep += 2 * .pi }

            let absSweep = abs(sweep)
            let degrees = absSweep * 180.0 / .pi
            if degrees < 2 || degrees > 178 { continue }

            let arcStart = sweep > 0 ? existingDir : drawDir
            let arcEnd = sweep > 0 ? drawDir : existingDir

            // Live arc
            var arcPath = Path()
            arcPath.addArc(center: screenStart, radius: r, startAngle: .radians(arcStart), endAngle: .radians(arcEnd), clockwise: false)
            context.stroke(arcPath, with: .color(angleColor.opacity(0.9)), lineWidth: 2)

            // Live angle label
            let bisector = arcStart + absSweep / 2
            let labelR = r + 16
            let labelPos = CGPoint(
                x: screenStart.x + cos(bisector) * labelR,
                y: screenStart.y + sin(bisector) * labelR
            )
            let angleText = String(format: "%.1f°", degrees)

            let textSize = estimateTextSize(angleText, fontSize: 13)
            let pill = CGRect(
                x: labelPos.x - textSize.width / 2 - 5,
                y: labelPos.y - textSize.height / 2 - 3,
                width: textSize.width + 10,
                height: textSize.height + 6
            )
            context.fill(Path(roundedRect: pill, cornerRadius: 4), with: .color(angleColor.opacity(0.9)))
            context.draw(
                Text(angleText).font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundColor(.white),
                at: labelPos
            )
        }
    }

    // MARK: - Room Areas

    private func drawRoomAreas(context: inout GraphicsContext, toScreen: (SerializablePoint) -> CGPoint) {
        let rooms = GeometryEngine.detectRooms(from: walls)
        for room in rooms where room.area > 100 {
            let screenCenter = toScreen(room.center)
            let areaText = unitSystem.formatArea(room.area, scale: scale)
            context.draw(
                Text(areaText).font(.system(size: 12, weight: .medium)).foregroundColor(.purple.opacity(0.7)),
                at: screenCenter
            )
        }
    }

    // MARK: - Helpers

    private func estimateTextSize(_ text: String, fontSize: Double) -> CGSize {
        CGSize(width: fontSize * 0.62 * Double(text.count), height: fontSize + 2)
    }

    private func boundingBox(_ points: [CGPoint]) -> CGRect? {
        guard !points.isEmpty else { return nil }
        var minX = Double.infinity, minY = Double.infinity
        var maxX = -Double.infinity, maxY = -Double.infinity
        for p in points {
            minX = min(minX, p.x); minY = min(minY, p.y)
            maxX = max(maxX, p.x); maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
