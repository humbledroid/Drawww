import SwiftUI

/// Compact floating tool palette for the floor plan canvas.
/// Designed for iPad — sits on the left side, minimal footprint.
struct ToolPaletteView: View {
    @Bindable var canvasState: CanvasState

    var body: some View {
        VStack(spacing: 4) {
            ForEach(DrawingTool.allCases) { tool in
                ToolButton(
                    tool: tool,
                    isSelected: canvasState.activeTool == tool,
                    action: { canvasState.switchTool(to: tool) }
                )
            }
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
    }
}

struct ToolButton: View {
    let tool: DrawingTool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: tool.iconName)
                    .font(.system(size: 20))
                    .frame(width: 44, height: 36)

                Text(tool.label)
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(isSelected ? .white : .primary)
            .frame(width: 56, height: 52)
            .background(
                isSelected
                    ? AnyShapeStyle(Color.accentColor)
                    : AnyShapeStyle(Color.clear),
                in: RoundedRectangle(cornerRadius: 8)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tool.label)
    }
}
