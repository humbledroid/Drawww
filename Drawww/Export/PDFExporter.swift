import UIKit
import PDFKit

/// Exports the floor plan to a to-scale PDF with dimension labels.
struct PDFExporter {

    /// Export a floor plan project to PDF data
    static func exportPDF(
        project: FloorPlanProject,
        paperSize: CGSize = CGSize(width: 792, height: 612) // Letter landscape
    ) -> Data {
        let walls = project.walls
        let shapes = project.draftingShapes.filter { !$0.isConstructionLine }
        guard !walls.isEmpty || !shapes.isEmpty else {
            return createEmptyPDF(size: paperSize, projectName: project.name)
        }

        // Calculate bounding box of all walls + shapes
        let bounds = calculateBounds(walls: walls, shapes: shapes)
        let margin: Double = 50

        // Calculate scale to fit on page
        let availableWidth = Double(paperSize.width) - 2 * margin
        let availableHeight = Double(paperSize.height) - 2 * margin - 40 // extra space for title

        let boundsWidth = bounds.maxX - bounds.minX
        let boundsHeight = bounds.maxY - bounds.minY

        guard boundsWidth > 0 && boundsHeight > 0 else {
            return createEmptyPDF(size: paperSize, projectName: project.name)
        }

        let scaleX = availableWidth / boundsWidth
        let scaleY = availableHeight / boundsHeight
        let pdfScale = min(scaleX, scaleY)

        // Center the drawing
        let drawingWidth = boundsWidth * pdfScale
        let drawingHeight = boundsHeight * pdfScale
        let offsetX = margin + (availableWidth - drawingWidth) / 2
        let offsetY = margin + 40 + (availableHeight - drawingHeight) / 2

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: paperSize))

        let data = renderer.pdfData { context in
            context.beginPage()
            let cgContext = context.cgContext

            // Title
            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 16, weight: .bold),
                .foregroundColor: UIColor.black
            ]
            let title = project.name as NSString
            title.draw(at: CGPoint(x: margin, y: margin), withAttributes: titleAttributes)

            // Scale info
            let scaleText = "Scale: 1 pt = \(String(format: "%.2f", 1.0 / project.pointsPerRealUnit)) \(project.unitSystem == .imperial ? "ft" : "m")" as NSString
            let scaleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10),
                .foregroundColor: UIColor.darkGray
            ]
            scaleText.draw(at: CGPoint(x: margin, y: margin + 22), withAttributes: scaleAttributes)

            // Unit info
            let unitText = "Units: \(project.unitSystem.shortLabel)" as NSString
            unitText.draw(at: CGPoint(x: margin + 200, y: margin + 22), withAttributes: scaleAttributes)

            // Transform helper
            func toPDF(_ point: SerializablePoint) -> CGPoint {
                CGPoint(
                    x: (point.x - bounds.minX) * pdfScale + offsetX,
                    y: (point.y - bounds.minY) * pdfScale + offsetY
                )
            }

            // Draw walls
            cgContext.setStrokeColor(UIColor.black.cgColor)
            cgContext.setLineWidth(2.0)
            cgContext.setLineCap(.round)

            for wall in walls {
                let start = toPDF(wall.start)
                let end = toPDF(wall.end)

                cgContext.move(to: start)
                cgContext.addLine(to: end)
                cgContext.strokePath()

                // Draw endpoint dots
                for point in [start, end] {
                    cgContext.fillEllipse(in: CGRect(
                        x: point.x - 2.5,
                        y: point.y - 2.5,
                        width: 5,
                        height: 5
                    ))
                }
            }

            // Draw drafting shapes
            cgContext.setStrokeColor(UIColor.darkGray.cgColor)
            for shape in shapes {
                cgContext.setLineWidth(shape.lineWeight.width)
                let dash = shape.lineStyle.dashPattern.map { CGFloat($0) }
                cgContext.setLineDash(phase: 0, lengths: dash)

                switch shape.shapeType {
                case .line:
                    let s = toPDF(SerializablePoint(x: shape.x1, y: shape.y1))
                    let e = toPDF(SerializablePoint(x: shape.x2, y: shape.y2))
                    cgContext.move(to: s)
                    cgContext.addLine(to: e)
                    cgContext.strokePath()
                case .circle:
                    let c = toPDF(SerializablePoint(x: shape.x1, y: shape.y1))
                    let r = shape.x2 * pdfScale
                    cgContext.strokeEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
                case .rectangle:
                    let o = toPDF(SerializablePoint(x: shape.x1, y: shape.y1))
                    let w = shape.x2 * pdfScale
                    let h = shape.y2 * pdfScale
                    cgContext.stroke(CGRect(x: o.x, y: o.y, width: w, height: h))
                case .arc:
                    let c = toPDF(SerializablePoint(x: shape.x1, y: shape.y1))
                    let r = shape.x2 * pdfScale
                    cgContext.addArc(center: c, radius: r, startAngle: shape.startAngle, endAngle: shape.endAngle, clockwise: false)
                    cgContext.strokePath()
                case .triangle:
                    let p1 = toPDF(SerializablePoint(x: shape.x1, y: shape.y1))
                    let p2 = toPDF(SerializablePoint(x: shape.x2, y: shape.y2))
                    let p3 = toPDF(SerializablePoint(x: shape.x3, y: shape.y3))
                    cgContext.move(to: p1)
                    cgContext.addLine(to: p2)
                    cgContext.addLine(to: p3)
                    cgContext.closePath()
                    cgContext.strokePath()
                default:
                    break
                }
                // Reset dash
                cgContext.setLineDash(phase: 0, lengths: [])
            }

            // Reset for wall labels
            cgContext.setStrokeColor(UIColor.black.cgColor)
            cgContext.setLineWidth(2.0)

            // Draw measurement labels
            let labelAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 9, weight: .medium),
                .foregroundColor: UIColor.blue
            ]

            for wall in walls {
                let length = wall.length
                guard length > 1 else { continue }

                let text = project.unitSystem.formatLength(length, scale: project.pointsPerRealUnit) as NSString
                let mid = wall.midpoint
                let pdfMid = toPDF(mid)

                // Offset perpendicular
                let angle = wall.angle
                let labelOffset: CGFloat = 12
                let labelPoint = CGPoint(
                    x: pdfMid.x + cos(angle + .pi / 2) * labelOffset,
                    y: pdfMid.y + sin(angle + .pi / 2) * labelOffset
                )

                let textSize = text.size(withAttributes: labelAttributes)
                let textRect = CGRect(
                    x: labelPoint.x - textSize.width / 2,
                    y: labelPoint.y - textSize.height / 2,
                    width: textSize.width,
                    height: textSize.height
                )

                // White background for readability
                cgContext.setFillColor(UIColor.white.withAlphaComponent(0.8).cgColor)
                cgContext.fill(textRect.insetBy(dx: -3, dy: -1))

                text.draw(in: textRect, withAttributes: labelAttributes)
            }

            // Draw room areas
            let rooms = GeometryEngine.detectRooms(from: walls)
            let areaAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10, weight: .medium),
                .foregroundColor: UIColor.purple
            ]

            for room in rooms where room.area > 100 {
                let center = toPDF(room.center)
                let areaText = project.unitSystem.formatArea(room.area, scale: project.pointsPerRealUnit) as NSString
                let textSize = areaText.size(withAttributes: areaAttributes)
                areaText.draw(at: CGPoint(
                    x: center.x - textSize.width / 2,
                    y: center.y - textSize.height / 2
                ), withAttributes: areaAttributes)
            }

            // Footer
            let footerText = "Generated by Floor Plan Studio" as NSString
            let footerAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 8),
                .foregroundColor: UIColor.lightGray
            ]
            footerText.draw(
                at: CGPoint(x: margin, y: Double(paperSize.height) - 30),
                withAttributes: footerAttributes
            )
        }

        return data
    }

    // MARK: - Helpers

    private static func calculateBounds(walls: [WallSegment], shapes: [DraftingShape] = []) -> (minX: Double, minY: Double, maxX: Double, maxY: Double) {
        var minX = Double.infinity, minY = Double.infinity
        var maxX = -Double.infinity, maxY = -Double.infinity

        func include(_ x: Double, _ y: Double) {
            minX = min(minX, x); minY = min(minY, y)
            maxX = max(maxX, x); maxY = max(maxY, y)
        }

        for wall in walls {
            include(wall.start.x, wall.start.y)
            include(wall.end.x, wall.end.y)
        }

        for shape in shapes {
            switch shape.shapeType {
            case .line:
                include(shape.x1, shape.y1)
                include(shape.x2, shape.y2)
            case .circle:
                include(shape.x1 - shape.x2, shape.y1 - shape.x2)
                include(shape.x1 + shape.x2, shape.y1 + shape.x2)
            case .rectangle:
                include(shape.x1, shape.y1)
                include(shape.x1 + shape.x2, shape.y1 + shape.y2)
            case .arc:
                include(shape.x1 - shape.x2, shape.y1 - shape.x2)
                include(shape.x1 + shape.x2, shape.y1 + shape.x2)
            case .triangle:
                include(shape.x1, shape.y1)
                include(shape.x2, shape.y2)
                include(shape.x3, shape.y3)
            default:
                include(shape.x1, shape.y1)
                include(shape.x2, shape.y2)
            }
        }

        // Add padding
        let padding = 20.0
        return (minX - padding, minY - padding, maxX + padding, maxY + padding)
    }

    private static func createEmptyPDF(size: CGSize, projectName: String) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: size))
        return renderer.pdfData { context in
            context.beginPage()
            let text = "\(projectName) — No walls drawn yet" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 14),
                .foregroundColor: UIColor.gray
            ]
            text.draw(at: CGPoint(x: 50, y: 50), withAttributes: attrs)
        }
    }
}
