import SwiftUI

/// Custom Canvas renderer for walls, measurements, grid, and guides
/// Uses Core Graphics for structured geometry (not PencilKit)
struct CanvasRenderer: View {
    let walls: [WallSegment]
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
    private let areaLabelColor = Color.purple.opacity(0.7)

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let offset = canvasState.viewportOffset
            let zoom = canvasState.viewportZoom

            // Helper to transform canvas points to screen points
            func toScreen(_ p: SerializablePoint) -> CGPoint {
                CGPoint(
                    x: p.x * Double(zoom) + Double(center.x) + Double(offset.width),
                    y: p.y * Double(zoom) + Double(center.y) + Double(offset.height)
                )
            }

            // 1. Draw grid
            if canvasState.showGrid {
                drawGrid(context: &context, size: size, center: center, offset: offset, zoom: zoom)
            }

            // 2. Draw guide lines
            for guide in canvasState.activeGuideLines {
                var guidePath = Path()
                guidePath.move(to: toScreen(guide.start))
                guidePath.addLine(to: toScreen(guide.end))
                context.stroke(
                    guidePath,
                    with: .color(guideColor),
                    style: StrokeStyle(lineWidth: 1, dash: [6, 4])
                )
            }

            // 3. Draw committed walls
            for wall in walls {
                let isSelected = canvasState.selectedItems.contains(.wall(wall.id))
                let color = isSelected ? wallSelectedColor : wallColor
                let lineWidth = max(2, 3 * Double(zoom))

                var wallPath = Path()
                wallPath.move(to: toScreen(wall.start))
                wallPath.addLine(to: toScreen(wall.end))
                context.stroke(wallPath, with: .color(color), lineWidth: lineWidth)

                // Draw endpoint dots
                let dotRadius = max(3, 4 * Double(zoom))
                for endpoint in [wall.start, wall.end] {
                    let screenPt = toScreen(endpoint)
                    let dotRect = CGRect(
                        x: screenPt.x - dotRadius / 2,
                        y: screenPt.y - dotRadius / 2,
                        width: dotRadius,
                        height: dotRadius
                    )
                    context.fill(Path(ellipseIn: dotRect), with: .color(color))
                }

                // Draw measurement label
                drawMeasurementLabel(
                    context: &context,
                    wall: wall,
                    toScreen: toScreen,
                    zoom: zoom
                )
            }

            // 4. Draw in-progress wall
            if canvasState.isDrawing,
               let start = canvasState.drawingStartPoint,
               let current = canvasState.drawingCurrentPoint {

                var drawingPath = Path()
                drawingPath.move(to: toScreen(start))
                drawingPath.addLine(to: toScreen(current))
                context.stroke(
                    drawingPath,
                    with: .color(drawingWallColor),
                    style: StrokeStyle(lineWidth: max(2, 3 * Double(zoom)), dash: [8, 4])
                )

                // Live measurement label
                let length = start.distance(to: current)
                if length > 5 {
                    let mid = start.midpoint(to: current)
                    let screenMid = toScreen(mid)
                    let text = unitSystem.formatLength(length, scale: scale)

                    // Background pill for readability
                    let textSize = estimateTextSize(text, fontSize: 13)
                    let pillRect = CGRect(
                        x: screenMid.x - textSize.width / 2 - 6,
                        y: screenMid.y - 22,
                        width: textSize.width + 12,
                        height: 20
                    )
                    context.fill(
                        Path(roundedRect: pillRect, cornerRadius: 4),
                        with: .color(.blue.opacity(0.9))
                    )
                    context.draw(
                        Text(text)
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white),
                        at: CGPoint(x: screenMid.x, y: screenMid.y - 12)
                    )
                }

                // Snap indicator dot
                let endScreen = toScreen(current)
                let snapDotSize: CGFloat = 10
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: endScreen.x - snapDotSize / 2,
                        y: endScreen.y - snapDotSize / 2,
                        width: snapDotSize,
                        height: snapDotSize
                    )),
                    with: .color(snapPointColor)
                )
            }

            // 5. Draw detected room areas
            drawRoomAreas(context: &context, toScreen: toScreen)

        } // end Canvas
    }

    // MARK: - Grid Drawing

    private func drawGrid(
        context: inout GraphicsContext,
        size: CGSize,
        center: CGPoint,
        offset: CGSize,
        zoom: CGFloat
    ) {
        let gridSize = canvasState.gridSpacing * Double(zoom)
        guard gridSize > 8 else { return } // Don't draw grid when too zoomed out

        let startX = (Double(center.x) + Double(offset.width)).truncatingRemainder(dividingBy: gridSize)
        let startY = (Double(center.y) + Double(offset.height)).truncatingRemainder(dividingBy: gridSize)

        var gridPath = Path()

        // Vertical lines
        var x = startX
        while x < Double(size.width) {
            gridPath.move(to: CGPoint(x: x, y: 0))
            gridPath.addLine(to: CGPoint(x: x, y: Double(size.height)))
            x += gridSize
        }

        // Horizontal lines
        var y = startY
        while y < Double(size.height) {
            gridPath.move(to: CGPoint(x: 0, y: y))
            gridPath.addLine(to: CGPoint(x: Double(size.width), y: y))
            y += gridSize
        }

        context.stroke(gridPath, with: .color(gridColor), lineWidth: 0.5)

        // Draw origin crosshair
        let originScreen = CGPoint(
            x: Double(center.x) + Double(offset.width),
            y: Double(center.y) + Double(offset.height)
        )
        var originPath = Path()
        originPath.move(to: CGPoint(x: originScreen.x - 12, y: originScreen.y))
        originPath.addLine(to: CGPoint(x: originScreen.x + 12, y: originScreen.y))
        originPath.move(to: CGPoint(x: originScreen.x, y: originScreen.y - 12))
        originPath.addLine(to: CGPoint(x: originScreen.x, y: originScreen.y + 12))
        context.stroke(originPath, with: .color(.gray.opacity(0.4)), lineWidth: 1)
    }

    // MARK: - Measurement Labels

    private func drawMeasurementLabel(
        context: inout GraphicsContext,
        wall: WallSegment,
        toScreen: (SerializablePoint) -> CGPoint,
        zoom: CGFloat
    ) {
        let length = wall.length
        guard length > 1 else { return }

        let text = unitSystem.formatLength(length, scale: scale)
        let mid = wall.midpoint
        let screenMid = toScreen(mid)

        // Offset label perpendicular to wall
        let wallAngle = wall.angle
        let offsetDist: Double = 16
        let labelPos = CGPoint(
            x: screenMid.x + cos(wallAngle + .pi / 2) * offsetDist,
            y: screenMid.y + sin(wallAngle + .pi / 2) * offsetDist
        )

        // Background pill
        let textSize = estimateTextSize(text, fontSize: 11)
        let pillRect = CGRect(
            x: labelPos.x - textSize.width / 2 - 4,
            y: labelPos.y - textSize.height / 2 - 2,
            width: textSize.width + 8,
            height: textSize.height + 4
        )
        context.fill(
            Path(roundedRect: pillRect, cornerRadius: 3),
            with: .color(Color(.systemBackground).opacity(0.85))
        )
        context.stroke(
            Path(roundedRect: pillRect, cornerRadius: 3),
            with: .color(measurementColor.opacity(0.5)),
            lineWidth: 0.5
        )
        context.draw(
            Text(text)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(measurementColor),
            at: labelPos
        )
    }

    // MARK: - Room Areas

    private func drawRoomAreas(
        context: inout GraphicsContext,
        toScreen: (SerializablePoint) -> CGPoint
    ) {
        let rooms = GeometryEngine.detectRooms(from: walls)
        for room in rooms where room.area > 100 {
            let screenCenter = toScreen(room.center)
            let areaText = unitSystem.formatArea(room.area, scale: scale)

            context.draw(
                Text(areaText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(areaLabelColor),
                at: screenCenter
            )
        }
    }

    // MARK: - Helpers

    private func estimateTextSize(_ text: String, fontSize: Double) -> CGSize {
        let charWidth = fontSize * 0.62
        return CGSize(
            width: charWidth * Double(text.count),
            height: fontSize + 2
        )
    }
}
