import SwiftUI

/// Radial tool-switching menu triggered by Apple Pencil Pro squeeze gesture.
/// Shows a ring of tool icons around the squeeze point for quick switching.
struct RadialMenuView: View {
    @Bindable var canvasState: CanvasState
    let position: CGPoint
    let onDismiss: () -> Void

    private let tools = DrawingTool.radialMenuTools
    private let radius: CGFloat = 80
    private let itemSize: CGFloat = 48

    @State private var appeared = false
    @State private var hoveredTool: DrawingTool?

    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.15)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            // Center indicator
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: canvasState.activeTool.iconName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.accentColor)
                )
                .position(position)

            // Radial tool buttons
            ForEach(Array(tools.enumerated()), id: \.element.id) { index, tool in
                let angle = angleForIndex(index, total: tools.count)
                let x = position.x + cos(angle) * radius
                let y = position.y + sin(angle) * radius

                radialButton(tool: tool)
                    .position(x: x, y: y)
                    .scaleEffect(appeared ? 1.0 : 0.3)
                    .opacity(appeared ? 1.0 : 0)
                    .animation(
                        .spring(response: 0.3, dampingFraction: 0.7)
                            .delay(Double(index) * 0.03),
                        value: appeared
                    )
            }

            // Undo button at the bottom of the ring
            undoButton
                .position(
                    x: position.x,
                    y: position.y + radius + 50
                )
                .scaleEffect(appeared ? 1.0 : 0.3)
                .opacity(appeared ? 1.0 : 0)
                .animation(
                    .spring(response: 0.3, dampingFraction: 0.7).delay(0.15),
                    value: appeared
                )
        }
        .onAppear {
            withAnimation { appeared = true }
        }
    }

    private func radialButton(tool: DrawingTool) -> some View {
        let isActive = canvasState.activeTool == tool
        let isHovered = hoveredTool == tool

        return Button {
            canvasState.switchTool(to: tool)
            dismiss()
        } label: {
            VStack(spacing: 2) {
                Image(systemName: tool.iconName)
                    .font(.system(size: 20, weight: isActive ? .bold : .medium))
                Text(tool.label)
                    .font(.system(size: 9, weight: .medium))
            }
            .frame(width: itemSize, height: itemSize)
            .foregroundColor(isActive ? .white : .primary)
            .background(
                Circle()
                    .fill(isActive ? Color.accentColor : Color(.systemBackground))
                    .shadow(color: .black.opacity(0.15), radius: isHovered ? 8 : 4)
            )
            .scaleEffect(isHovered ? 1.15 : 1.0)
        }
        .buttonStyle(.plain)
    }

    private var undoButton: some View {
        Button {
            // Trigger undo — handled by parent
            canvasState.undoStack.isEmpty ? () : ()
            dismiss()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 14, weight: .medium))
                Text("Undo")
                    .font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!canvasState.canUndo)
    }

    private func angleForIndex(_ index: Int, total: Int) -> CGFloat {
        // Start from top (-π/2), distribute evenly
        let startAngle: CGFloat = -.pi / 2
        let step = (2 * .pi) / CGFloat(total)
        return startAngle + step * CGFloat(index)
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.15)) {
            appeared = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            onDismiss()
        }
    }
}
