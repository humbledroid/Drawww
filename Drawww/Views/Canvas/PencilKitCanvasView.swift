import SwiftUI
import PencilKit

/// PencilKit layer for freeform sketching — sits on top of the structured geometry canvas.
/// Provides paper-like drawing with pressure sensitivity, tilt, and natural ink feel.
/// We use our own tool palette, so PKToolPicker is not shown.
struct PencilKitCanvasView: UIViewRepresentable {
    @Binding var canvasDrawing: PKDrawing
    @Binding var isActive: Bool
    var inkColor: UIColor
    var inkWidth: CGFloat
    var isErasing: Bool

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.delegate = context.coordinator
        canvas.drawing = canvasDrawing
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawingPolicy = .pencilOnly
        canvas.isScrollEnabled = false
        canvas.overrideUserInterfaceStyle = .unspecified
        canvas.minimumZoomScale = 1.0
        canvas.maximumZoomScale = 1.0

        updateTool(on: canvas)
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        if canvas.drawing != canvasDrawing {
            canvas.drawing = canvasDrawing
        }
        updateTool(on: canvas)
        canvas.isUserInteractionEnabled = isActive
    }

    private func updateTool(on canvas: PKCanvasView) {
        if isErasing {
            canvas.tool = PKEraserTool(.vector)
        } else {
            canvas.tool = PKInkingTool(.pen, color: inkColor, width: inkWidth)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(drawing: $canvasDrawing)
    }

    class Coordinator: NSObject, PKCanvasViewDelegate {
        @Binding var drawing: PKDrawing

        init(drawing: Binding<PKDrawing>) {
            self._drawing = drawing
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            drawing = canvasView.drawing
        }
    }
}
