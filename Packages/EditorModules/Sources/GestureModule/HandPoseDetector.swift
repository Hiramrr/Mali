import CoreMedia
import Vision

public struct HandDetection: Sendable {
    public let handDetected: Bool
    public let landmarks: HandLandmarks?
    public let secondaryLandmarks: HandLandmarks?
}

public struct HandPoseDetector: Sendable {
    private let request: DetectHumanHandPoseRequest

    public init() {
        var request = DetectHumanHandPoseRequest()
        request.maximumHandCount = 2
        self.request = request
    }

    // Lo llama la tarea de procesamiento en segundo plano, nunca el hilo UI.
    // Todo el cómputo es local (Vision on-device): ningún frame sale del Mac.
    // Con dos manos se devuelven ambas ordenadas (principal + secundaria);
    // la pinza se evalúa sobre la principal y la separación alimenta el
    // gesto de longitud del párrafo.
    public func detect(_ frame: CameraFrame) async throws -> HandDetection {
        let hands = try await request.perform(on: frame.sampleBuffer, orientation: .up)
        guard !hands.isEmpty else {
            return HandDetection(handDetected: false, landmarks: nil, secondaryLandmarks: nil)
        }
        guard let buffer = CMSampleBufferGetImageBuffer(frame.sampleBuffer) else {
            return HandDetection(handDetected: true, landmarks: nil, secondaryLandmarks: nil)
        }
        let size = CGSize(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))
        let landmarks = hands.compactMap { hand -> HandLandmarks? in
            guard let wrist = hand.joint(for: .wrist),
                  let thumb = hand.joint(for: .thumbTip),
                  let index = hand.joint(for: .indexTip),
                  [thumb, index].allSatisfy({ $0.confidence >= GestureTuning.minimumConfidence })
            else { return nil }
            return HandLandmarks(wrist: wrist.location.cgPoint, thumb: thumb.location.cgPoint,
                                 index: index.location.cgPoint, imageSize: size)
        }.sorted { $0.mirroredX < $1.mirroredX }
        return HandDetection(handDetected: true, landmarks: landmarks.first,
                             secondaryLandmarks: landmarks.dropFirst().first)
    }
}
