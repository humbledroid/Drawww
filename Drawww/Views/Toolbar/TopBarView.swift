import SwiftUI

/// Top toolbar with undo/redo, unit toggle, zoom indicator, grid toggle, and export
struct TopBarView: View {
    @Bindable var canvasState: CanvasState
    @Bindable var project: FloorPlanProject

    var onUndo: () -> Void
    var onRedo: () -> Void
    var onDelete: () -> Void
    var onExportPDF: () -> Void
    var onCalibrate: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Project name
            Text(project.name)
                .font(.headline)
                .lineLimit(1)

            Spacer()

            // Undo / Redo
            HStack(spacing: 4) {
                Button(action: onUndo) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 16, weight: .medium))
                }
                .disabled(!canvasState.canUndo)

                Button(action: onRedo) {
                    Image(systemName: "arrow.uturn.forward")
                        .font(.system(size: 16, weight: .medium))
                }
                .disabled(!canvasState.canRedo)
            }

            Divider().frame(height: 20)

            // Delete selected
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 16))
            }
            .disabled(canvasState.selectedItems.isEmpty)

            Divider().frame(height: 20)

            // Unit toggle
            UnitToggleView(project: project)

            Divider().frame(height: 20)

            // Scale calibration
            Button(action: onCalibrate) {
                HStack(spacing: 4) {
                    Image(systemName: "ruler")
                        .font(.system(size: 14))
                    Text("Scale")
                        .font(.system(size: 12, weight: .medium))
                }
            }

            Divider().frame(height: 20)

            // Grid toggle
            Button(action: { canvasState.showGrid.toggle() }) {
                Image(systemName: canvasState.showGrid ? "grid" : "grid.circle")
                    .font(.system(size: 16))
                    .foregroundStyle(canvasState.showGrid ? .accentColor : .secondary)
            }

            // Zoom indicator
            Text("\(canvasState.zoomPercentage)%")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 50)

            Divider().frame(height: 20)

            // Export
            Button(action: onExportPDF) {
                HStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16))
                    Text("PDF")
                        .font(.system(size: 12, weight: .medium))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Unit Toggle

struct UnitToggleView: View {
    @Bindable var project: FloorPlanProject

    var body: some View {
        HStack(spacing: 2) {
            ForEach(UnitSystem.allCases, id: \.self) { unit in
                Button(action: { project.unitSystem = unit }) {
                    Text(unit.shortLabel)
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            project.unitSystem == unit
                                ? Color.accentColor.opacity(0.2)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 4)
                        )
                        .foregroundStyle(project.unitSystem == unit ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
