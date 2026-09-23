import Foundation
import Observation

/// Coordina la apertura de archivos en una única ventana.
///
/// La app usa `DocumentGroup` (multi-ventana por diseño) pero el producto
/// exige una sola ventana: todo se carga en la ventana existente, nunca se
/// crea una ventana nueva. Este coordinador es el único puente entre quien
/// pide abrir algo (biblioteca, Finder, Dock, Abrir reciente) y la ventana
/// principal, que aplica la solicitud en su propio `Binding` y reubica su
/// `NSDocument` con `saveAs`, sin crear `NSDocument` ni `NSWindow` nuevos.
@MainActor @Observable
public final class SingleWindowCoordinator {
    public static let shared = SingleWindowCoordinator()

    public struct OpenRequest: Equatable {
        /// Identificador único para que `onChange` dispare aunque se reabra
        /// el mismo archivo (misma URL y mismo texto).
        public let id = UUID()
        public let url: URL
        public let text: String

        public init(url: URL, text: String) {
            self.url = url
            self.text = text
        }

        public static func == (lhs: OpenRequest, rhs: OpenRequest) -> Bool {
            lhs.id == rhs.id
        }
    }

    public var pendingOpen: OpenRequest?
    public var newDocumentRevision = 0

    private init() {}

    public func requestOpen(url: URL, text: String) {
        pendingOpen = OpenRequest(url: url, text: text)
    }

    public func requestNew() {
        newDocumentRevision += 1
    }
}
