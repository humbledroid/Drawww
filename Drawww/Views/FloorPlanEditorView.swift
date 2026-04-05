import SwiftUI
import SwiftData

/// Main editor view that composes the canvas, tool palette, and top bar.
/// This is the primary screen of the app.
struct FloorPlanEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var project: FloorPlanProject
    @State private var canvasState = CanvasState()
    @State private var showCalibrationSheet = false
    @State private var showExportShareSheet = false
    @State private var exportedPDFURL: URL?

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            TopBarView(
                canvasState: canvasState,
                project: project,
                onUndo: { undoAction() },
                onRedo: { redoAction() },
                onDelete: { deleteAction() },
                onExportPDF: { exportPDF() },
                onCalibrate: { showCalibrationSheet = true }
            )

            // Canvas area with tool palette overlay
            ZStack(alignment: .topLeading) {
                // Main canvas
                FloorPlanCanvasView(
                    project: project,
                    canvasState: canvasState
                )

                // Floating tool palette — left side
                ToolPaletteView(canvasState: canvasState)
                    .padding(.leading, 12)
                    .padding(.top, 12)

                // Status bar — bottom right
                statusOverlay
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(12)
            }
        }
        .sheet(isPresented: $showCalibrationSheet) {
            ScaleCalibrationSheet(project: project)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showExportShareSheet) {
            if let url = exportedPDFURL {
                ShareSheetView(items: [url])
            }
        }
        .onAppear {
            // Restore viewport from project
            canvasState.viewportOffset = CGSize(
                width: project.viewportOffsetX,
                height: project.viewportOffsetY
            )
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

    // MARK: - Status Overlay

    private var statusOverlay: some View {
        HStack(spacing: 8) {
            if !canvasState.selectedItems.isEmpty {
                Text("\(canvasState.selectedItems.count) selected")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Text("\(project.walls.count) walls")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
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

        case .moveWall(let wall, let oldStart, let oldEnd):
            let currentStart = wall.start
            let currentEnd = wall.end
            wall.start = oldStart
            wall.end = oldEnd
            canvasState.redoStack.append(.moveWall(wall: wall, oldStart: currentStart, oldEnd: currentEnd))

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
            default:
                break
            }
        }
        canvasState.clearSelection()
        project.touch()
    }

    private func exportPDF() {
        let pdfData = PDFExporter.exportPDF(project: project)

        // Save to temp file for sharing
        let fileName = "\(project.name.replacingOccurrences(of: " ", with: "_")).pdf"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try? pdfData.write(to: tempURL)

        exportedPDFURL = tempURL
        showExportShareSheet = true
    }
}

// MARK: - Share Sheet

struct ShareSheetView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
