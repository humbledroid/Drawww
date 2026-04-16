import UIKit

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

        // Calculate bounding box of all geometry
        let bounds = calculateBounds(walls: walls, shapes: shapes)
        let margin: Double = 60
        let headerHeight: Double = 50 // space for title + scale info
        let footerHeight: Double = 30

        // Available drawing area
        let availableWidth = Double(paperSize.width) - 2 * margin
        let availableHeight = Double(paperSize.height) - 2 * margin - headerHeight - footerHeight

        let boundsWidth = bounds.maxX - bounds.minX
        let boundsHeight = bounds.maxY - bounds.minY

        guard boundsWidth > 0 && boundsHeight > 0 else {
            return createEmptyPDF(size: paperSize, projectName: project.name)
        }

        let scaleX = availableWidth / boundsWidth
        let scaleY = availableHeight / boundsHeight
        let pdfScale = min(scaleX, scaleY)

        // Center the drawing in the available area
        let drawingWidth = boundsWidth * pdfScale
        let drawingHeight = boundsHeight * pdfScale
        let originX = margin + (availableWidth - drawingWidth) / 2
        let originY = margin + headerHeight + (availableHeight - drawingHeight) / 2

        // Adaptive font sizes based on how much the drawing is scaled
        // Clamp so text doesn't get absurdly large or tiny
        let baseLabelSize = min(max(9.0 * pdfScale, 7.0), 11.0)
        let baseAreaSize = min(max(10.0 * pdfScale, 8.0), 12.0)

        // Adaptive label offset — how far from the wall midpoint to place text
        let labelOffset = min(max(16.0 * pdfScale, 10.0), 24.0)

        // Minimum wall length in PDF points to show a label (skip tiny walls)
        let minLabelledLength: Double = 30.0

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: paperSize))

        let data = renderer.pdfData { context in
            context.beginPage()
            let cgContext = context.cgContext

            // ---- HEADER ----
            drawHeader(
                cgContext: cgContext,
                project: project,
                pdfScale: pdfScale,
                margin: margin,
                paperSize: paperSize
            )

            // ---- COORDINATE TRANSFORM ----
            func toPDF(_ point: SerializablePoint) -> CGPoint {
                CGPoint(
                    x: (point.x - bounds.minX) * pdfScale + originX,
                    y: (point.y - bounds.minY) * pdfScale + originY
                )
            }

            // ---- DRAW WALLS ----
            cgContext.setStrokeColor(UIColor.black.cgColor)
            cgContext.setFillColor(UIColor.black.cgColor)
            cgContext.setLineWidth(max(1.5, 2.0 * pdfScale))
            cgContext.setLineCap(.round)

            for wall in walls {
                let start = toPDF(wall.start)
                let end = toPDF(wall.end)
                cgContext.move(to: start)
                cgContext.addLine(to: end)
                cgContext.strokePath()

                // Endpoint dots
                let dotR = max(1.5, 2.5 * pdfScale)
                for pt in [start, end] {
                    cgContext.fillEllipse(in: CGRect(
                        x: pt.x - dotR, y: pt.y - dotR,
                        width: dotR * 2, height: dotR * 2
                    ))
                }
            }

            // ---- DRAW DRAFTING SHAPES ----
            drawShapes(shapes, cgContext: cgContext, pdfScale: pdfScale, toPDF: toPDF)

            // ---- DIMENSION LABELS (with collision avoidance) ----
            var placedRects: [CGRect] = []

            let labelAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: baseLabelSize, weight: .medium),
                .foregroundColor: UIColor(red: 0.1, green: 0.3, blue: 0.8, alpha: 1.0)
            ]

            for wall in walls {
                let pdfLength = wall.length * pdfScale
                guard pdfLength > minLabelledLength else { continue }

                let text = project.unitSystem.formatLength(wall.length, scale: project.pointsPerRealUnit) as NSString
                let pdfMid = toPDF(wall.midpoint)
                let angle = wall.angle
                let textSize = text.size(withAttributes: labelAttrs)

                // Try perpendicular offsets on both sides, pick first non-overlapping
                var bestRect: CGRect?
                for multiplier in [1.0, -1.0, 2.0, -2.0] {
                    let offset = labelOffset * multiplier
                    let candidate = CGPoint(
                        x: pdfMid.x + cos(angle + .pi / 2) * offset,
                        y: pdfMid.y + sin(angle + .pi / 2) * offset
                    )
                    let rect = CGRect(
                        x: candidate.x - textSize.width / 2 - 3,
                        y: candidate.y - textSize.height / 2 - 1,
                        width: textSize.width + 6,
                        height: textSize.height + 2
                    )
                    if !placedRects.contains(where: { $0.intersects(rect) }) {
                        bestRect = rect
                        break
                    }
                }

                // Fallback: place it anyway with the first offset
                if bestRect == nil {
                    let candidate = CGPoint(
                        x: pdfMid.x + cos(angle + .pi / 2) * labelOffset,
                        y: pdfMid.y + sin(angle + .pi / 2) * labelOffset
                    )
                    bestRect = CGRect(
                        x: candidate.x - textSize.width / 2 - 3,
                        y: candidate.y - textSize.height / 2 - 1,
                        width: textSize.width + 6,
                        height: textSize.height + 2
                    )
                }

                if let rect = bestRect {
                    placedRects.append(rect)

                    // White background pill
                    cgContext.setFillColor(UIColor.white.withAlphaComponent(0.9).cgColor)
                    let bgPath = UIBezierPath(roundedRect: rect, cornerRadius: 2)
                    cgContext.addPath(bgPath.cgPath)
                    cgContext.fillPath()

                    // Draw text centered in the rect
                    let textRect = CGRect(
                        x: rect.origin.x + 3,
                        y: rect.origin.y + 1,
                        width: textSize.width,
                        height: textSize.height
                    )
                    text.draw(in: textRect, withAttributes: labelAttrs)
                }
            }

            // ---- ROOM AREAS (with collision avoidance) ----
            let rooms = GeometryEngine.detectRooms(from: walls)
            let areaAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: baseAreaSize, weight: .semibold),
                .foregroundColor: UIColor(red: 0.5, green: 0.2, blue: 0.6, alpha: 1.0)
            ]

            // Only show areas for rooms large enough to be meaningful
            let minAreaInPDFPoints = 2000.0 // skip tiny detected "rooms"
            for room in rooms {
                let pdfArea = room.area * pdfScale * pdfScale
                guard pdfArea > minAreaInPDFPoints else { continue }

                let center = toPDF(room.center)
                let areaText = project.unitSystem.formatArea(room.area, scale: project.pointsPerRealUnit) as NSString
                let textSize = areaText.size(withAttributes: areaAttrs)

                let rect = CGRect(
                    x: center.x - textSize.width / 2 - 4,
                    y: center.y - textSize.height / 2 - 2,
                    width: textSize.width + 8,
                    height: textSize.height + 4
                )

                // Skip if it overlaps an existing label
                if placedRects.contains(where: { $0.intersects(rect) }) { continue }
                placedRects.append(rect)

                // Light background
                cgContext.setFillColor(UIColor(red: 0.95, green: 0.92, blue: 1.0, alpha: 0.85).cgColor)
                let bgPath = UIBezierPath(roundedRect: rect, cornerRadius: 3)
                cgContext.addPath(bgPath.cgPath)
                cgContext.fillPath()

                areaText.draw(at: CGPoint(
                    x: center.x - textSize.width / 2,
                    y: center.y - textSize.height / 2
                ), withAttributes: areaAttrs)
            }

            // ---- FOOTER ----
            let footerText = "Generated by Floor Plan Studio" as NSString
            let footerAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 8),
                .foregroundColor: UIColor.lightGray
            ]
            footerText.draw(
                at: CGPoint(x: margin, y: Double(paperSize.height) - 24),
                withAttributes: footerAttrs
            )

            // Date
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            let dateText = formatter.string(from: Date()) as NSString
            dateText.draw(
                at: CGPoint(x: Double(paperSize.width) - margin - 100, y: Double(paperSize.height) - 24),
                withAttributes: footerAttrs
            )
        }

        return data
    }

    // MARK: - Header

    private static func drawHeader(
        cgContext: CGContext,
        project: FloorPlanProject,
        pdfScale: Double,
        margin: Double,
        paperSize: CGSize
    ) {
        // Title
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 16, weight: .bold),
            .foregroundColor: UIColor.black
        ]
        (project.name as NSString).draw(
            at: CGPoint(x: margin, y: margin - 10),
            withAttributes: titleAttrs
        )

        // Compute meaningful scale info
        // pdfScale = how many PDF points per canvas point
        // project.pointsPerRealUnit = canvas points per real-world unit
        // So: PDF points per real-world unit = pdfScale * pointsPerRealUnit
        let pdfPtsPerUnit = pdfScale * project.pointsPerRealUnit
        let unitLabel = project.unitSystem.baseUnitLabel

        // Express as "1 inch on paper = X real units" (72 PDF pts = 1 inch)
        let realUnitsPerInch = 72.0 / pdfPtsPerUnit
        let scaleRatioText: String
        if project.unitSystem == .imperial {
            // e.g. "1\" = 3.5 ft"
            scaleRatioText = String(format: "1\" on paper = %.1f %@", realUnitsPerInch, unitLabel)
        } else {
            if realUnitsPerInch >= 1.0 {
                scaleRatioText = String(format: "1\" on paper = %.2f %@", realUnitsPerInch, unitLabel)
            } else {
                scaleRatioText = String(format: "1\" on paper = %.0f cm", realUnitsPerInch * 100)
            }
        }

        let infoAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10),
            .foregroundColor: UIColor.darkGray
        ]
        (scaleRatioText as NSString).draw(
            at: CGPoint(x: margin, y: margin + 14),
            withAttributes: infoAttrs
        )

        ("Units: \(project.unitSystem.shortLabel)" as NSString).draw(
            at: CGPoint(x: margin + 220, y: margin + 14),
            withAttributes: infoAttrs
        )

        // Separator line
        cgContext.setStrokeColor(UIColor.lightGray.cgColor)
        cgContext.setLineWidth(0.5)
        cgContext.move(to: CGPoint(x: margin, y: margin + 34))
        cgContext.addLine(to: CGPoint(x: Double(paperSize.width) - margin, y: margin + 34))
        cgContext.strokePath()
    }

    // MARK: - Drafting Shapes

    private static func drawShapes(
        _ shapes: [DraftingShape],
        cgContext: CGContext,
        pdfScale: Double,
        toPDF: (SerializablePoint) -> CGPoint
    ) {
        cgContext.setStrokeColor(UIColor.darkGray.cgColor)
        for shape in shapes {
            cgContext.setLineWidth(max(0.5, shape.lineWeight.width * pdfScale))
            let dash = shape.lineStyle.dashPattern.map { $0 * pdfScale }
            cgContext.setLineDash(phase: 0, lengths: dash as! [CGFloat])

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
            cgContext.setLineDash(phase: 0, lengths: [])
        }
    }

    // MARK: - Bounds

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

        // Extra breathing room around the drawing so labels don't clip at edges
        let padding = 40.0
        return (minX - padding, minY - padding, maxX + padding, maxY + padding)
    }

    // MARK: - Empty PDF

    private static func createEmptyPDF(size: CGSize, projectName: String) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: size))
        return renderer.pdfData { context in
            context.beginPage()
            let text = "\(projectName) — No walls or shapes drawn yet" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 14),
                .foregroundColor: UIColor.gray
            ]
            text.draw(at: CGPoint(x: 50, y: 50), withAttributes: attrs)
        }
    }
}
