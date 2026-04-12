import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - PDF FileDocument wrapper for .fileExporter
struct PDFDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf] }
    let data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// Main editor view that composes the canvas, tool palette, and top bar.
struct FloorPlanEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var project: FloorPlanProject
    @State private var canvasState = CanvasState()
    @State private var showCalibrationSheet = false
    @State private var showExportSheet = false
    @State private var showLinePropertiesPopover = false
    @State private var exportDocument: PDFDocument?

    var body: some View {
        VStack(spacing: 0) {
            TopBarView(
                canvasState: canvasState,
                project: project,
                onUndo: { undoAction() },
                onRedo: { redoAction() },
                onDelete: { deleteAction() },
                onExportPDF: { exportPDF() },
                onCalibrate: { showCalibrationSheet = true }
            )

            ZStack(alignment: .topLeading) {
                FloorPlanCanvasView(
                    project: project,
                    canvasState: canvasState
                )

                // Floating tool palette — left side
                ToolPaletteView(canvasState: canvasState)
                    .padding(.leading, 12)
                    .padding(.top, 12)

                // Line properties indicator — bottom left (when drafting tool active)
                if isDraftingToolActive {
                    linePropertiesIndicator
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .padding(12)
                }

                // Status bar — bottom right
                statusOverlay
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(12)
            }
        }
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showCalibrationSheet) {
            ScaleCalibrationSheet(project: project)
                .presentationDetents([.medium])
        }
        .fileExporter(
            isPresented: $showExportSheet,
            document: exportDocument,
            contentType: .pdf,
            defaultFilename: "\(project.name).pdf"
        ) { result in
            switch result {
            case .success(let url):
                print("PDF saved to \(url)")
            case .failure(let error):
                print("PDF export error: \(error)")
            }
        }
        .onAppear {
            canvasState.viewportOffset = CGSize(width: project.viewportOffsetX, height: project.viewportOffsetY)
            canvasState.viewportZoom = CGFloat(project.viewportZoom)
        }
        .onChange(of: canvasState.viewportOffset) { _, newValue in
            project.viewportOffsetX = Double(newValue.width)
            project.viewportOffsetY = Double(newValue.height)
        }
        .onChange(of: canvasState.viewportZoom) { _, newValue in
            project.viewportZoom = Double(newValue)
        }
    }

    private var isDraftingToolActive: Bool {
        [.line, .circle, .arc, .rectangle, .constructionLine].contains(canvasState.activeTool)
    }

    // MARK: - Line Properties Indicator

    private var linePropertiesIndicator: some View {
        Button { showLinePropertiesPopover.toggle() } label: {
            HStack(spacing: 6) {
                // Preview of current line style
                lineStylePreview
                    .frame(width: 30, height: 2)

                Text(canvasState.lineProperties.weight.label)
                    .font(.system(size: 10, weight: .medium))

                Text(canvasState.lineProperties.style.label)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
        }
        .popover(isPresented: $showLinePropertiesPopover) {
            LinePropertiesPopover(properties: canvasState.lineProperties)
                .frame(width: 220)
        }
    }

    private var lineStylePreview: some View {
        Canvas { context, size in
            var path = Path()
            path.move(to: CGPoint(x: 0, y: size.height / 2))
            path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
            context.stroke(path, with: .color(.primary),
                         style: StrokeStyle(
                            lineWidth: canvasState.lineProperties.weight.width,
                            dash: canvasState.lineProperties.style.dashPattern
                         ))
        }
    }

    // MARK: - Status Overlay

    private var statusOverlay: some View {
        HStack(spacing: 8) {
            if !canvasState.selectedItems.isEmpty {
                Text("\(canvasState.selectedItems.count) selected")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
            Text("\(project.walls.count) walls")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            if !project.draftingShapes.isEmpty {
                Text("\(project.draftingShapes.count) shapes")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Actions

    private func undoAction() {
        guard let action = canvasState.undoStack.popLast() else { return }
        switch action {
        case .addWall(let wall):
            project.walls.removeAll { $0.id == wall.id }
            modelContext.delete(wall)
            canvasState.redoStack.append(action)
        case .removeWall(let wall):
            let newWall = WallSegment(start: wall.start, end: wall.end, thickness: wall.thickness)
            newWall.project = project
            project.walls.append(newWall)
            modelContext.insert(newWall)
            canvasState.redoStack.append(.addWall(newWall))
        case .addDraftingShape(let shape):
            project.draftingShapes.removeAll { $0.id == shape.id }
            modelContext.delete(shape)
            canvasState.redoStack.append(action)
        case .removeDraftingShape(let shape):
            shape.project = project
            project.draftingShapes.append(shape)
            modelContext.insert(shape)
            canvasState.redoStack.append(.addDraftingShape(shape))
        case .addSectionCut(let cut):
            project.sectionCuts.removeAll { $0.id == cut.id }
            modelContext.delete(cut)
            canvasState.redoStack.append(action)
        case .addHeightMarker(let marker):
            project.heightMarkers.removeAll { $0.id == marker.id }
            modelContext.delete(marker)
            canvasState.redoStack.append(action)
        case .addStairSymbol(let stair):
            project.stairs.removeAll { $0.id == stair.id }
            modelContext.delete(stair)
            canvasState.redoStack.append(action)
        case .moveWall(let wall, let oldStart, let oldEnd):
            let cur = (wall.start, wall.end)
            wall.start = oldStart; wall.end = oldEnd
            canvasState.redoStack.append(.moveWall(wall: wall, oldStart: cur.0, oldEnd: cur.1))
        default:
            break
        }
        project.touch()
    }

    private func redoAction() {
        guard let action = canvasState.redoStack.popLast() else { return }
        switch action {
        case .addWall(let wall):
            wall.project = project
            project.walls.append(wall)
            modelContext.insert(wall)
            canvasState.undoStack.append(action)
        case .removeWall(let wall):
            project.walls.removeAll { $0.id == wall.id }
            modelContext.delete(wall)
            canvasState.undoStack.append(action)
        case .addDraftingShape(let shape):
            shape.project = project
            project.draftingShapes.append(shape)
            modelContext.insert(shape)
            canvasState.undoStack.append(action)
        case .removeDraftingShape(let shape):
            project.draftingShapes.removeAll { $0.id == shape.id }
            modelContext.delete(shape)
            canvasState.undoStack.append(action)
        default:
            break
        }
        project.touch()
    }

    private func deleteAction() {
        for item in canvasState.selectedItems {
            switch item {
            case .wall(let id):
                if let wall = project.walls.first(where: { $0.id == id }) {
                    canvasState.recordAction(.removeWall(wall))
                    project.walls.removeAll { $0.id == id }
                    modelContext.delete(wall)
                }
            case .draftingShape(let id):
                if let shape = project.draftingShapes.first(where: { $0.id == id }) {
                    canvasState.recordAction(.removeDraftingShape(shape))
                    project.draftingShapes.removeAll { $0.id == id }
                    modelContext.delete(shape)
                }
            default:
                break
            }
        }
        canvasState.clearSelection()
        project.touch()
    }

    private func exportPDF() {
        let pdfData = PDFExporter.exportPDF(project: project)
        exportDocument = PDFDocument(data: pdfData)
        showExportSheet = true
    }
}

// MARK: - Line Properties Popover

struct LinePropertiesPopover: View {
    @Bindable var properties: ActiveLineProperties

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Line Style")
                .font(.headline)
            styleSection
            weightSection
        }
        .padding()
    }

    private var styleSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Style").font(.subheadline).foregroundColor(.secondary)
            ForEach(LineStyle.allCases) { style in
                Button {
                    properties.style = style
                } label: {
                    HStack {
                        Text(style.label)
                            .font(.system(size: 13))
                        Spacer()
                        if properties.style == style {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var weightSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Weight").font(.subheadline).foregroundColor(.secondary)
            ForEach(LineWeight.allCases) { weight in
                Button {
                    properties.weight = weight
                } label: {
                    HStack {
                        Text(weight.label)
                            .font(.system(size: 13))
                        Spacer()
                        // Preview line
                        Canvas { ctx, size in
                            var path = Path()
                            path.move(to: CGPoint(x: 0, y: size.height / 2))
                            path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                            ctx.stroke(path, with: .color(.primary), lineWidth: weight.width)
                        }
                        .frame(width: 40, height: 12)
                        if properties.weight == weight {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}
