import Foundation

/// Fase de la calibración guiada: se muestrea la distancia pulgar–índice
/// con la mano abierta y con la pinza cerrada, y el umbral se coloca en medio.
/// Portado de EditorTDAH.
public enum GestureCalibrationPhase: Sendable {
    case openHand
    case pinch

    public var instruction: String {
        switch self {
        case .openHand: "Muestra la mano abierta y quédate quieto"
        case .pinch: "Cierra la pinza (pulgar e índice) y quédate quieto"
        }
    }
}

public struct GestureCalibrationRun: Sendable {
    public var phase: GestureCalibrationPhase
    public var endsAt: TimeInterval
    public var samples: [Double] = []

    public init(phase: GestureCalibrationPhase, endsAt: TimeInterval) {
        self.phase = phase
        self.endsAt = endsAt
    }
}

/// Matemática pura de la calibración (testeable).
public struct GestureCalibrationMath: Sendable {
    /// Ventana de muestreo en segundos.
    public static let window = 3.0
    /// Muestras mínimas para una mediana fiable.
    public static let minimumSamples = 10
    /// Separación relativa mínima sana entre ambas medianas (25%).
    /// Relativa (no absoluta) para valer a cualquier distancia de la cámara.
    public static let minimumRelativeGap = 0.25

    public static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 1 { return sorted[mid] }
        return (sorted[mid - 1] + sorted[mid]) / 2
    }

    /// Umbral sugerido a medio camino, sujeto a los límites.
    /// Devuelve nil si las muestras se solapan (no calibrable así).
    public static func suggestedThreshold(open: Double, pinch: Double) -> (value: Double, gapWarning: Bool)? {
        guard pinch < open else { return nil }
        let mid = (open + pinch) / 2
        let clamped = min(max(mid, GestureThresholds.min), GestureThresholds.max)
        return (clamped, (open - pinch) < minimumRelativeGap * open)
    }
}
