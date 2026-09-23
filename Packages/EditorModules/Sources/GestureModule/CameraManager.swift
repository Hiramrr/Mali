import AVFoundation
import OSLog

/// Frame retenido por el delegate de captura. Nadie lo escribe tras la entrega.
public struct CameraFrame: @unchecked Sendable {
    public let sampleBuffer: CMSampleBuffer
    public let uptime: TimeInterval
}

public enum CameraFailure: LocalizedError {
    case permission, configuration(String)

    public var errorDescription: String? {
        switch self {
        case .permission: "Activa el acceso a la cámara para el editor en Ajustes del Sistema."
        case .configuration(let message): message
        }
    }
}

/// Sesión de captura. Las mutaciones y el estado del delegate viven en `queue`;
/// solo la vista previa toca la sesión desde el hilo principal.
/// Los frames se consumen vía `frames` (AsyncStream con buffer de 1).
///
/// El permiso de cámara se pide solo en `start()`, nunca al arrancar el
/// editor: sin la pieza de gestos (o sin activarla) no hay solicitud.
public final class CameraManager: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    public let session = AVCaptureSession()
    public let frames: AsyncStream<CameraFrame>
    private let continuation: AsyncStream<CameraFrame>.Continuation
    private let queue = DispatchQueue(label: "com.hiram.EditorFinal.camera", qos: .userInitiated)
    private let onFailure: @Sendable (String) -> Void
    private let logger = Logger(subsystem: "com.hiram.EditorFinal", category: "Camera")
    private var configured = false
    private var enabled = false
    private var cameraName = "Cámara"
    private var lastFrameTime = 0.0
    private var observers: [NSObjectProtocol] = []

    public init(onFailure: @escaping @Sendable (String) -> Void) {
        let stream = AsyncStream<CameraFrame>.makeStream(bufferingPolicy: .bufferingNewest(1))
        frames = stream.stream
        continuation = stream.continuation
        self.onFailure = onFailure
        super.init()
    }

    public func start() async throws -> String {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        var granted = status == .authorized
        if status == .notDetermined { granted = await AVCaptureDevice.requestAccess(for: .video) }
        guard granted else { throw CameraFailure.permission }

        return try await withCheckedThrowingContinuation { result in
            queue.async { [self] in
                do {
                    if !configured { try configure() }
                    lastFrameTime = 0
                    enabled = true
                    session.startRunning()
                    guard session.isRunning else {
                        throw CameraFailure.configuration("La cámara no pudo iniciarse. Cierra otras apps de cámara y reintenta.")
                    }
                    logger.info("Capture started: \(self.cameraName, privacy: .public)")
                    result.resume(returning: cameraName)
                } catch {
                    enabled = false
                    logger.error("Camera: \(error.localizedDescription, privacy: .public)")
                    result.resume(throwing: error)
                }
            }
        }
    }

    public func stop() {
        queue.async { [self] in
            enabled = false
            if session.isRunning { session.stopRunning() }
            logger.info("Capture stopped")
        }
    }

    private func configure() throws {
        guard let device = AVCaptureDevice.default(for: .video) else {
            throw CameraFailure.configuration("No se encontró una cámara. Conecta una webcam y reintenta.")
        }
        let input = try AVCaptureDeviceInput(device: device)
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String:
                                kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        output.setSampleBufferDelegate(self, queue: queue)

        session.beginConfiguration()
        defer { session.commitConfiguration() }
        if session.canSetSessionPreset(.hd1280x720) { session.sessionPreset = .hd1280x720 }
        guard session.canAddInput(input) else {
            throw CameraFailure.configuration("No se pudo conectar la entrada de cámara.")
        }
        session.addInput(input)
        guard session.canAddOutput(output) else {
            session.removeInput(input)
            throw CameraFailure.configuration("No se pudo crear la salida de vídeo.")
        }
        session.addOutput(output)
        if let connection = output.connection(with: .video) {
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = false
            }
            if connection.isVideoRotationAngleSupported(0) { connection.videoRotationAngle = 0 }
        }
        if device.activeFormat.videoSupportedFrameRateRanges.contains(where: {
            $0.minFrameRate <= 30 && $0.maxFrameRate >= 30
        }) {
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
                device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
            } catch {
                logger.error("Could not limit capture to 30 FPS: \(error.localizedDescription, privacy: .public)")
            }
        }
        cameraName = device.localizedName
        configured = true

        for name in [AVCaptureSession.runtimeErrorNotification, AVCaptureSession.wasInterruptedNotification,
                     AVCaptureSession.didStopRunningNotification] {
            let observer = NotificationCenter.default.addObserver(forName: name, object: session, queue: nil) {
                [weak self] notification in
                let message = (notification.userInfo?[AVCaptureSessionErrorKey] as? NSError)?.localizedDescription
                    ?? "La cámara se detuvo o fue interrumpida. Vuelve a activarla para reintentar."
                self?.queue.async { [weak self] in
                    guard let self, self.enabled else { return }
                    self.enabled = false
                    self.logger.error("Capture interrupted: \(message, privacy: .public)")
                    self.onFailure(message)
                }
            }
            observers.append(observer)
        }
    }

    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                              from connection: AVCaptureConnection) {
        guard enabled else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now >= lastFrameTime else { return }
        lastFrameTime = max(lastFrameTime + 1 / GestureTuning.analysisFPS, now)
        continuation.yield(CameraFrame(sampleBuffer: sampleBuffer, uptime: now))
    }

    deinit {
        continuation.finish()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }
}
