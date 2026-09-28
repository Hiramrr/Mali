import Foundation

/// Guardado en iCloud Drive. Un equipo personal de Apple Developer no puede
/// firmar un contenedor iCloud propio, así que la app usa una carpeta de
/// iCloud Drive que el usuario autoriza una vez y conserva con un marcador de
/// seguridad. macOS sincroniza esa carpeta; la app solo lee y escribe archivos.
public enum CloudDocumentsError: LocalizedError {
    case outsideDrive

    public var errorDescription: String? { "La carpeta no está en iCloud Drive." }
    public var recoverySuggestion: String? {
        "Elige iCloud Drive o una carpeta dentro de iCloud Drive. Si no aparece, activa iCloud Drive en Ajustes del Sistema › Apple ID › iCloud."
    }
}

@MainActor public enum CloudDocuments {
    public static let enabledKey = "editor.saveToICloud"
    /// Ruta visible de la carpeta elegida; también sirve para que las vistas se actualicen.
    public static let pathKey = "editor.iCloudFolderPath"
    static let bookmarkKey = "editor.iCloudFolderBookmark"
    // Se conserva el acceso hasta cerrar la app, como `DocumentImageAccess`.
    private static var activeFolder: URL?

    /// Raíz de iCloud Drive del usuario (fuera del contenedor de la sandbox).
    public static var driveURL: URL { driveURL(home: userHome) }

    nonisolated static func driveURL(home: URL) -> URL {
        home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
    }

    /// Con sandbox, `homeDirectoryForCurrentUser` apunta al contenedor de la app.
    nonisolated static var userHome: URL {
        if let entry = getpwuid(getuid()), let directory = entry.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: directory), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    nonisolated static func isInsideDrive(_ url: URL, home: URL) -> Bool {
        let root = driveURL(home: home).standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path == root || path.hasPrefix(root + "/")
    }

    /// Carpeta de iCloud con acceso activo; `nil` si está desactivado o se perdió el permiso.
    public static var folder: URL? {
        guard UserDefaults.standard.bool(forKey: enabledKey) else { return nil }
        if let activeFolder { return activeFolder }
        guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope,
                                 relativeTo: nil, bookmarkDataIsStale: &stale),
              url.startAccessingSecurityScopedResource() else { return nil }
        if stale, let fresh = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(fresh, forKey: bookmarkKey)
        }
        let normalized = URL(fileURLWithPath: url.path, isDirectory: true).standardizedFileURL
        activeFolder = normalized
        return normalized
    }

    /// Guarda el permiso de una carpeta elegida en un panel y activa el guardado en iCloud.
    public static func remember(_ folder: URL) throws {
        guard isInsideDrive(folder, home: userHome) else { throw CloudDocumentsError.outsideDrive }
        let bookmark = try folder.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        activeFolder?.stopAccessingSecurityScopedResource()
        activeFolder = nil
        UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
        UserDefaults.standard.set(folder.path, forKey: pathKey)
        UserDefaults.standard.set(true, forKey: enabledKey)
    }

    /// Reactiva iCloud con la carpeta ya autorizada. Devuelve `false` si hay que elegirla.
    public static func enableIfAuthorized() -> Bool {
        guard UserDefaults.standard.data(forKey: bookmarkKey) != nil else { return false }
        UserDefaults.standard.set(true, forKey: enabledKey)
        return true
    }

    /// Los documentos nuevos vuelven a guardarse en el Mac. Se conserva el
    /// permiso para reactivar iCloud sin volver a elegir la carpeta.
    public static func disable() {
        UserDefaults.standard.set(false, forKey: enabledKey)
    }
}
