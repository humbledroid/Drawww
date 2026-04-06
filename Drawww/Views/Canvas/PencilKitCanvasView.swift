import SwiftUI
import PencilKit

/// PencilKit layer for freeform sketching — sits on top of the structured geometry canvas.
/// Provides paper-like drawing with pressure sensitivity, tilt, and natural ink feel.
struct PencilKitCanvasView: UIViewRepresentable {
    @Binding var canvasDrawing: PKDrawing
    @Binding var isActive: Bool
    let toolPicker: PKToolPicker
    var inkColor: UIColor
    var inkWidth: CGFloat
    var isErasing: Bool

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.delegate = context.coordinator
        canvas.drawing = canvasDrawing
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawingPolicy = .pencilOnly  // Finger gestures reserved for pan/zoom
        canvas.isScrollEnabled = false       // We handle our own pan/zoom
        canvas.overrideUserInterfaceStyle = .unspecified
        canvas.minimumZoomScale = 1.0
        canvas.maximumZoomScale = 1.0

        // Configure tool
        updateTool(on: canvas)

        // Show tool picker when active
        if isActive {
            toolPicker.setVisible(true, forFirstResponder: canvas)
            toolPicker.addObserver(canvas)
            canvas.becomeFirstResponder()
        }

        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        // Update drawing if changed externally
        if canvas.drawing != canvasDrawing {
            canvas.drawing = canvasDrawing
        }

        updateTool(on: canvas)

        // Toggle tool picker visibility
        if isActive {
            toolPicker.setVisible(false, forFirstResponder: canvas)
            // We use our own tool palette, not Apple's PKToolPicker
            canvas.isUserInteractionEnabled = true
        } else {
            canvas.isUserInteractionEnabled = false
        }
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
