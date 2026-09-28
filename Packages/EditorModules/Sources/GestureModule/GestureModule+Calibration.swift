import EditorCore
import Foundation

extension GestureModule {
    // MARK: - Calibración

    /// Muestrea una fase durante ~3 s. Congela la interacción mientras tanto
    /// para no abrir sesiones accidentales con la pinza de muestra.
    public func startCalibration(phase: GestureCalibrationPhase) {
        guard running else {
            message = "Activa la cámara primero."
            return
        }
        // Ronda nueva: las medianas anteriores no se mezclan.
        openMedian = nil
        pinchMedian = nil
        calibration = GestureCalibrationRun(
            phase: phase,
            endsAt: ProcessInfo.processInfo.systemUptime + GestureCalibrationMath.window)
        calibrationMessage = "\(phase.instruction)…"
    }

    public func cancelCalibration() {
        calibration = nil
        calibrationMessage = nil
        message = "Calibración cancelada."
    }

    func sampleCalibration(_ vision: GestureState, at uptime: TimeInterval) {
        guard var run = calibration else { return }
        if uptime >= run.endsAt {
            finishCalibration(run)
            return
        }
        if let d = vision.distance {
            run.samples.append(d)
            calibration = run
        }
    }

    private func finishCalibration(_ run: GestureCalibrationRun) {
        calibration = nil
        calibrationMessage = nil
        guard let med = GestureCalibrationMath.median(run.samples),
              run.samples.count >= GestureCalibrationMath.minimumSamples else {
            message = "Muy pocas muestras. Mejora la luz y reintenta."
            return
        }
        switch run.phase {
        case .openHand:
            openMedian = med
            message = String(format: "Abierta: %.3f. Ahora muestrea la pinza (botón 2).", med)
        case .pinch:
            pinchMedian = med
            guard let open = openMedian else {
                message = String(format: "Pinza: %.3f. Primero muestrea la mano abierta (botón 1).", med)
                return
            }
            applyCalibration(open: open, pinch: med)
        }
    }

    private func applyCalibration(open: Double, pinch: Double) {
        guard let suggested = GestureCalibrationMath.suggestedThreshold(open: open, pinch: pinch) else {
            message = "Las muestras se solapan: repite abriendo bien la mano y cerrando bien la pinza."
            return
        }
        GestureThresholds.activation = suggested.value
        message = String(format: "Umbral ajustado a %.3f (abierta %.3f · pinza %.3f).%@",
                         suggested.value, open, pinch,
                         suggested.gapWarning ? " Poca separación: acerca la mano a la cámara." : "")
    }
}
