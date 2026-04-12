import SwiftUI

/// Compact floating tool palette with expandable groups.
/// Core tools always visible; groups expand on tap.
struct ToolPaletteView: View {
    @Bindable var canvasState: CanvasState
    @State private var expandedGroup: ToolGroup?

    var body: some View {
        VStack(spacing: 6) {
            // Always-visible core tools
            coreToolsSection

            Divider()
                .frame(width: 44)
                .padding(.vertical, 2)

            // Expandable groups
            ForEach(ToolGroup.allCases.filter { $0 != .core }) { group in
                groupSection(group)
            }
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
    }

    // MARK: - Core Tools (always visible)

    private var coreToolsSection: some View {
        VStack(spacing: 4) {
            ForEach(ToolGroup.core.tools) { tool in
                ToolButton(
                    tool: tool,
                    isSelected: canvasState.activeTool == tool,
                    action: { canvasState.switchTool(to: tool) }
                )
            }
        }
    }

    // MARK: - Expandable Group

    private func groupSection(_ group: ToolGroup) -> some View {
        VStack(spacing: 4) {
            // Group header — tap to expand/collapse
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if expandedGroup == group {
                        expandedGroup = nil
                    } else {
                        expandedGroup = group
                    }
                }
            } label: {
                groupHeader(group)
            }
            .buttonStyle(.plain)

            // Expanded tools
            if expandedGroup == group {
                ForEach(group.tools) { tool in
                    ToolButton(
                        tool: tool,
                        isSelected: canvasState.activeTool == tool,
                        compact: true,
                        action: { canvasState.switchTool(to: tool) }
                    )
                    .transition(.scale.combined(with: .opacity))
                }
            }
        }
    }

    private func groupHeader(_ group: ToolGroup) -> some View {
        let isExpanded = expandedGroup == group
        let hasActiveTool = group.tools.contains(canvasState.activeTool)

        return HStack(spacing: 4) {
            // Show the active tool icon from this group, or the first tool's icon
            let displayTool = hasActiveTool ? canvasState.activeTool : group.tools.first!
            Image(systemName: displayTool.iconName)
                .font(.system(size: 14))
            Text(group.label)
                .font(.system(size: 9, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .bold))
                .rotationEffect(isExpanded ? .degrees(90) : .degrees(0))
        }
        .frame(width: 80, height: 28)
        .foregroundColor(hasActiveTool ? .white : .secondary)
        .background(
            hasActiveTool
                ? AnyShapeStyle(Color.accentColor.opacity(0.8))
                : AnyShapeStyle(Color.clear),
            in: RoundedRectangle(cornerRadius: 6)
        )
    }
}

// MARK: - Tool Button

struct ToolButton: View {
    let tool: DrawingTool
    let isSelected: Bool
    var compact: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if compact {
                compactLayout
            } else {
                fullLayout
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tool.label)
    }

    private var fullLayout: some View {
        VStack(spacing: 2) {
            Image(systemName: tool.iconName)
                .font(.system(size: 20))
                .frame(width: 44, height: 36)
            Text(tool.label)
                .font(.system(size: 9, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .foregroundColor(isSelected ? .white : .primary)
        .frame(width: 80, height: 52)
        .background(
            isSelected
                ? AnyShapeStyle(Color.accentColor)
                : AnyShapeStyle(Color.clear),
            in: RoundedRectangle(cornerRadius: 8)
        )
    }

    private var compactLayout: some View {
        HStack(spacing: 6) {
            Image(systemName: tool.iconName)
                .font(.system(size: 14))
                .frame(width: 20)
            Text(tool.label)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundColor(isSelected ? .white : .primary)
        .frame(width: 80, height: 30)
        .background(
            isSelected
                ? AnyShapeStyle(Color.accentColor)
                : AnyShapeStyle(Color.clear),
            in: RoundedRectangle(cornerRadius: 6)
        )
    }
}
