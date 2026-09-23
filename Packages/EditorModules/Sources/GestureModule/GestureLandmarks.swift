import CoreGraphics
import Foundation

/// Articulaciones de una mano en coordenadas Vision (origen abajo-izquierda,
/// sin espejar). Portado de EditorTDAH.
public struct HandLandmarks: Sendable {
    public let wrist: CGPoint
    public let thumb: CGPoint
    public let index: CGPoint
    public let imageSize: CGSize

    public init(wrist: CGPoint, thumb: CGPoint, index: CGPoint, imageSize: CGSize) {
        self.wrist = wrist
        self.thumb = thumb
        self.index = index
        self.imageSize = imageSize
    }

    public var isValid: Bool {
        imageSize.width.isFinite && imageSize.height.isFinite
            && imageSize.width > 0 && imageSize.height > 0
            && [wrist, thumb, index].allSatisfy({
                $0.x.isFinite && $0.y.isFinite
                    && (0...1).contains($0.x) && (0...1).contains($0.y)
            })
    }

    /// Distancia pulgar–índice con corrección de aspecto.
    public var distance: Double {
        hypot(thumb.x - index.x, (thumb.y - index.y) * imageSize.height / imageSize.width)
    }

    /// Posición X central, espejada para que coincida con la vista previa.
    public var mirroredX: Double { 1 - (thumb.x + index.x) / 2 }
    public var y: Double { (thumb.y + index.y) / 2 }

    public func displayPoint(_ point: CGPoint, in size: CGSize) -> CGPoint {
        let scale = min(size.width / imageSize.width, size.height / imageSize.height)
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        return CGPoint(x: (size.width - width) / 2 + (1 - point.x) * width,
                       y: (size.height - height) / 2 + (1 - point.y) * height)
    }
}

public enum PinchEvent: Sendable {
    case none, started, changed, ended, trackingLost
}

public struct GestureState: Sendable {
    public var event = PinchEvent.none
    public var handDetected = false
    public var pinch = false
    public var distance: Double?
    public var x: Double?
    public var y: Double?
    public var landmarks: HandLandmarks?
    /// Segunda mano (gesto de longitud). Nil con una sola mano.
    public var secondaryLandmarks: HandLandmarks?
    /// Separación horizontal entre ambas manos (unidades de ancho de imagen).
    public var handSpan: Double?

    public init() {}

    public var landmarksValid: Bool { landmarks?.isValid ?? false }
    /// Dos manos distintas y separadas: puerta del gesto de longitud.
    public var hasTwoDistinctHands: Bool { handSpan.map { $0 >= GestureTuning.minimumHandSpan } ?? false }
}

/// Autómata de pinza con histéresis: se activa cerca, se libera lejos.
/// Así el temblor de la mano no abre/cierra la pinza a cada frame.
/// La pinza se evalúa solo sobre la mano principal; la secundaria
/// alimenta `handSpan` para el gesto a dos manos.
public struct GestureRecognizer: Sendable {
    public private(set) var state = GestureState()

    public init() {}

    public mutating func update(handDetected: Bool, landmarks: HandLandmarks?,
                               secondaryLandmarks: HandLandmarks? = nil) -> GestureState {
        let wasPinching = state.pinch
        state.event = .none
        state.handDetected = handDetected
        guard let landmarks, landmarks.isValid else {
            state.event = wasPinching ? .trackingLost : .none
            state.pinch = false
            state.distance = nil
            state.x = nil
            state.y = nil
            state.landmarks = nil
            state.secondaryLandmarks = nil
            state.handSpan = nil
            return state
        }

        state.landmarks = landmarks
        state.distance = landmarks.distance
        state.x = landmarks.mirroredX
        state.y = landmarks.y
        if let second = secondaryLandmarks, second.isValid {
            state.secondaryLandmarks = second
            state.handSpan = abs(landmarks.mirroredX - second.mirroredX)
        } else {
            state.secondaryLandmarks = nil
            state.handSpan = nil
        }
        if state.pinch {
            if landmarks.distance > GestureThresholds.release { state.pinch = false }
        } else if landmarks.distance < GestureThresholds.activation {
            state.pinch = true
        }
        state.event = state.pinch ? (wasPinching ? .changed : .started) : (wasPinching ? .ended : .none)
        return state
    }
}
