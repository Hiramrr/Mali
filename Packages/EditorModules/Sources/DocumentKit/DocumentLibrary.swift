import Foundation

public enum DocumentLibrary {
    /// El listado se ejecuta fuera del actor de la interfaz.
    public static func documents(in folders: [URL]) async -> [URL] {
        var documents: [URL] = []
        for folder in folders {
            guard !Task.isCancelled else { return [] }
            let access = folder.startAccessingSecurityScopedResource()
            defer { if access { folder.stopAccessingSecurityScopedResource() } }
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
            ) else { continue }
            for file in files {
                guard !Task.isCancelled else { return [] }
                if ["md", "markdown", "txt"].contains(file.pathExtension.lowercased()),
                   (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                    documents.append(file)
                }
            }
        }
        return Array(Set(documents))
    }
}
