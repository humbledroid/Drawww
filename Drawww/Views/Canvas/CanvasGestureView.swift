import SwiftUI
import UIKit

/// UIViewRepresentable that handles Apple Pencil input separately from touch gestures.
/// Pencil → drawing; Finger → pan/zoom. This is critical for the floor plan UX.
struct CanvasGestureView: UIViewRepresentable {
    @Bindable var canvasState: CanvasState
    let canvasSize: CGSize

    var onPencilBegan: (CGPoint) -> Void
    var onPencilMoved: (CGPoint) -> Void
    var onPencilEnded: (CGPoint) -> Void
    var onTapAt: (CGPoint) -> Void

    func makeUIView(context: Context) -> CanvasGestureUIView {
        let view = CanvasGestureUIView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true

        // Pan gesture (one finger)
        let panGesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        panGesture.minimumNumberOfTouches = 1
        panGesture.maximumNumberOfTouches = 1
        panGesture.allowedTouchTypes = [UITouch.TouchType.direct.rawValue as NSNumber]
        view.addGestureRecognizer(panGesture)

        // Pinch gesture (two fingers)
        let pinchGesture = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        pinchGesture.allowedTouchTypes = [UITouch.TouchType.direct.rawValue as NSNumber]
        view.addGestureRecognizer(pinchGesture)

        // Allow simultaneous gestures
        panGesture.delegate = context.coordinator
        pinchGesture.delegate = context.coordinator

        return view
    }

    func updateUIView(_ uiView: CanvasGestureUIView, context: Context) {
        context.coordinator.canvasState = canvasState
        context.coordinator.onPencilBegan = onPencilBegan
        context.coordinator.onPencilMoved = onPencilMoved
        context.coordinator.onPencilEnded = onPencilEnded
        context.coordinator.onTapAt = onTapAt
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            canvasState: canvasState,
            onPencilBegan: onPencilBegan,
            onPencilMoved: onPencilMoved,
            onPencilEnded: onPencilEnded,
            onTapAt: onTapAt
        )
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, UIGestureRecognizerDelegate, CanvasGestureUIViewDelegate {
        var canvasState: CanvasState
        var onPencilBegan: (CGPoint) -> Void
        var onPencilMoved: (CGPoint) -> Void
        var onPencilEnded: (CGPoint) -> Void
        var onTapAt: (CGPoint) -> Void

        private var lastPanTranslation: CGPoint = .zero
        private var initialZoom: CGFloat = 1.0

        init(
            canvasState: CanvasState,
            onPencilBegan: @escaping (CGPoint) -> Void,
            onPencilMoved: @escaping (CGPoint) -> Void,
            onPencilEnded: @escaping (CGPoint) -> Void,
            onTapAt: @escaping (CGPoint) -> Void
        ) {
            self.canvasState = canvasState
            self.onPencilBegan = onPencilBegan
            self.onPencilMoved = onPencilMoved
            self.onPencilEnded = onPencilEnded
            self.onTapAt = onTapAt
        }

        // MARK: - Pencil Touch Handling (from CanvasGestureUIView)

        func pencilTouchBegan(at point: CGPoint, touch: UITouch) {
            onPencilBegan(point)
        }

        func pencilTouchMoved(at point: CGPoint, touch: UITouch) {
            onPencilMoved(point)
        }

        func pencilTouchEnded(at point: CGPoint, touch: UITouch) {
            onPencilEnded(point)
        }

        func fingerTapped(at point: CGPoint) {
            onTapAt(point)
        }

        // MARK: - Pan Gesture

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            switch gesture.state {
            case .began:
                lastPanTranslation = .zero
            case .changed:
                let translation = gesture.translation(in: gesture.view)
                let delta = CGSize(
                    width: translation.x - lastPanTranslation.x,
                    height: translation.y - lastPanTranslation.y
                )
                canvasState.viewportOffset.width += delta.width
                canvasState.viewportOffset.height += delta.height
                lastPanTranslation = translation
            default:
                break
            }
        }

        // MARK: - Pinch Gesture

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            switch gesture.state {
            case .began:
                initialZoom = canvasState.viewportZoom
            case .changed:
                canvasState.viewportZoom = initialZoom * gesture.scale
                canvasState.clampZoom()
            default:
                break
            }
        }

        // MARK: - UIGestureRecognizerDelegate

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            // Allow pan + pinch simultaneously
            return true
        }
    }
}

// MARK: - Custom UIView for Touch Type Discrimination

protocol CanvasGestureUIViewDelegate: AnyObject {
    func pencilTouchBegan(at point: CGPoint, touch: UITouch)
    func pencilTouchMoved(at point: CGPoint, touch: UITouch)
    func pencilTouchEnded(at point: CGPoint, touch: UITouch)
    func fingerTapped(at point: CGPoint)
}

/// UIView subclass that distinguishes Apple Pencil touches from finger touches.
/// Pencil touches are forwarded to the delegate for drawing.
/// Finger touches are left for gesture recognizers (pan/zoom).
class CanvasGestureUIView: UIView {
    weak var delegate: CanvasGestureUIViewDelegate?
    private var activePencilTouch: UITouch?
    private var fingerTouchStart: CGPoint?
    private var fingerMoved = false

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            if touch.type == .pencil || touch.type == .stylus {
                activePencilTouch = touch
                let location = touch.location(in: self)

                // Use predicted touches for lower latency
                if let predicted = event?.predictedTouches(for: touch), let last = predicted.last {
                    delegate?.pencilTouchBegan(at: last.location(in: self), touch: touch)
                } else {
                    delegate?.pencilTouchBegan(at: location, touch: touch)
                }
            } else if touch.type == .direct {
                fingerTouchStart = touch.location(in: self)
                fingerMoved = false
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            if touch === activePencilTouch {
                // Use predicted touches for lower latency during drawing
                if let predicted = event?.predictedTouches(for: touch), let last = predicted.last {
                    delegate?.pencilTouchMoved(at: last.location(in: self), touch: touch)
                } else {
                    delegate?.pencilTouchMoved(at: touch.location(in: self), touch: touch)
                }
            } else if touch.type == .direct {
                fingerMoved = true
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            if touch === activePencilTouch {
                let location = touch.location(in: self)
                delegate?.pencilTouchEnded(at: location, touch: touch)
                activePencilTouch = nil
            } else if touch.type == .direct && !fingerMoved {
                // Finger tap (not pan/zoom)
                if let start = fingerTouchStart {
                    delegate?.fingerTapped(at: start)
                }
                fingerTouchStart = nil
            }
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        activePencilTouch = nil
        fingerTouchStart = nil
    }
}
