import AppKit
import SwiftUI
import EditorCore

public struct WritingStyle: Equatable, Sendable {
    public var size: Double
    public var family: String
    public var spacing: Double
    public var paragraph: Double
    public var syntax: Bool
    /// Espaciado entre letras (tracking) en puntos. 0 = normal.
    public var tracking: Double
    /// Alineación: "natural", "left", "center", "justify", "right".
    public var alignment: String
    /// Grosor: "regular", "medium", "semibold", "bold".
    public var weight: String
    /// Color del texto: "auto" o hex "#RRGGBB".
    public var textHex: String
    /// Color de fondo del lienzo: "auto" o hex "#RRGGBB".
    public var backgroundHex: String
    /// Color de acento (cursor, resaltado de párrafo, enlaces): "auto" o hex.
    public var accentHex: String

    public init(
        size: Double = 18,
        family: String = "system",
        spacing: Double = 6,
        paragraph: Double = 0,
        syntax: Bool = true,
        tracking: Double = 0,
        alignment: String = "natural",
        weight: String = "regular",
        textHex: String = "auto",
        backgroundHex: String = "auto",
        accentHex: String = "auto"
    ) {
        self.size = min(36, max(12, size))
        self.family = family
        self.spacing = min(16, max(0, spacing))
        self.paragraph = min(24, max(0, paragraph))
        self.syntax = syntax
        self.tracking = min(4, max(-1, tracking))
        self.alignment = Self.availableAlignments.map(\.id).contains(alignment) ? alignment : "natural"
        self.weight = Self.availableWeights.map(\.id).contains(weight) ? weight : "regular"
        self.textHex = textHex
        self.backgroundHex = backgroundHex
        self.accentHex = accentHex
    }

    /// Atajos rápidos de tipografía: identificador guardado y nombre visible.
    /// Los identificadores antiguos se conservan para no romper documentos.
    public static let availableFamilies: [(id: String, name: String)] = [
        ("system", "Sistema"),
        ("serif", "Georgia"),
        ("palatino", "Palatino"),
        ("helvetica", "Helvetica"),
        ("verdana", "Verdana"),
        ("mono", "Monoespaciada"),
    ]

    public static let availableWeights: [(id: String, name: String)] = [
        ("regular", "Normal"),
        ("medium", "Mediana"),
        ("semibold", "Seminegrita"),
        ("bold", "Negrita"),
    ]

    public static let availableAlignments: [(id: String, name: String)] = [
        ("natural", "Automática"),
        ("left", "Izquierda"),
        ("center", "Centrada"),
        ("justify", "Justificada"),
        ("right", "Derecha"),
    ]

    /// Todas las familias instaladas en el sistema, ordenadas. El `family`
    /// puede ser cualquiera de estos nombres además de los atajos de arriba.
    @MainActor public static var systemFontFamilies: [String] {
        NSFontManager.shared.availableFontFamilies.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    /// Nombre visible para cualquier identificador (atajo o familia real).
    public static func displayName(for id: String) -> String {
        if let preset = availableFamilies.first(where: { $0.id == id }) { return preset.name }
        return id
    }

    /// ¿Es un atajo interno o una familia real del sistema?
    public static func isPresetFamily(_ id: String) -> Bool {
        availableFamilies.map(\.id).contains(id)
    }

    // MARK: - Pesos y fuentes

    @MainActor public var fontWeight: NSFont.Weight {
        switch weight {
        case "medium": return .medium
        case "semibold": return .semibold
        case "bold": return .bold
        default: return .regular
        }
    }

    private var numericWeight: Int {
        switch weight {
        case "medium": return 7
        case "semibold": return 9
        case "bold": return 11
        default: return 5
        }
    }

    @MainActor public var font: NSFont { baseFont(ofSize: size) }

    /// Fuente base de la familia elegida. Acepta los atajos históricos
    /// ("system", "mono", "serif"…) y cualquier familia instalada
    /// (p. ej. "Times New Roman", "Avenir Next", "Courier").
    /// Los identificadores desconocidos usan la fuente del sistema.
    @MainActor public func baseFont(ofSize pointSize: Double) -> NSFont {
        switch family {
        case "mono":
            return .monospacedSystemFont(ofSize: pointSize, weight: fontWeight)
        case "system":
            return .systemFont(ofSize: pointSize, weight: fontWeight)
        default:
            // 1) Atajos históricos con nombres PostScript conocidos.
            for candidate in postScriptNames {
                if let font = NSFont(name: candidate, size: pointSize) {
                    return withWeight(font)
                }
            }
            // 2) Familia real del sistema (nombre de NSFontManager).
            if let familyName = self.familyName ?? family as String?,
               NSFontManager.shared.availableFontFamilies.contains(familyName),
               let managed = NSFontManager.shared.font(withFamily: familyName, traits: traitsForWeight, weight: numericWeight, size: pointSize) {
                return managed
            }
            // 3) Intento directo por nombre PostScript (por si se guardó uno).
            if let direct = NSFont(name: family, size: pointSize) {
                return withWeight(direct)
            }
            // 4) Miembros de la familia: elige el que mejor encaje con el grosor.
            if let familyName = self.familyName,
               let members = NSFontManager.shared.availableMembers(ofFontFamily: familyName) {
                let target = numericWeight
                let sorted = members.sorted {
                    abs(($0[1] as? Int ?? 5) - target) < abs(($1[1] as? Int ?? 5) - target)
                }
                if let name = sorted.first?[0] as? String, let font = NSFont(name: name, size: pointSize) {
                    return font
                }
            }
            return .systemFont(ofSize: pointSize, weight: fontWeight)
        }
    }

    @MainActor private func withWeight(_ font: NSFont) -> NSFont {
        switch weight {
        case "regular", "medium":
            // NSFontManager no distingue bien medium de regular en todas las
            // familias; se devuelve la base salvo que se pida seminegrita/negrita.
            if weight == "regular" { return font }
            if let managed = tryMedium(font) { return managed }
            return font
        case "semibold", "bold":
            let converted = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
            // Si la conversión no cambió nada, al menos devuelve la base.
            return converted
        default:
            return font
        }
    }

    @MainActor private func tryMedium(_ font: NSFont) -> NSFont? {
        // Busca una variante Medium/Semibold dentro de la misma familia.
        let familyName = font.familyName ?? self.familyName ?? self.family
        guard let members = NSFontManager.shared.availableMembers(ofFontFamily: familyName) else { return nil }
        let wants = weight == "semibold" ? ["SemiBold", "Semibold", "DemiBold", "Bold"] : ["Medium", "Semibold", "Bold"]
        for member in members {
            guard let name = member[0] as? String else { continue }
            for suffix in wants where name.localizedCaseInsensitiveContains(suffix) {
                if let candidate = NSFont(name: name, size: font.pointSize) { return candidate }
            }
        }
        return nil
    }

    @MainActor private var traitsForWeight: NSFontTraitMask {
        switch weight {
        case "bold", "semibold": return .boldFontMask
        default: return []
        }
    }

    /// Títulos con la misma familia del cuerpo, en negrita y mayor tamaño.
    @MainActor public func headingFont(level: Int) -> NSFont {
        let pointSize = size + Double(max(2, 16 - level * 3))
        if family == "system" {
            return .systemFont(ofSize: pointSize, weight: .semibold)
        }
        let base = baseFont(ofSize: pointSize)
        let bolded = NSFontManager.shared.convert(base, toHaveTrait: .boldFontMask)
        return bolded.pointSize == pointSize ? bolded : base
    }

    private var familyName: String? {
        switch family {
        case "serif": return "Georgia"
        case "palatino": return "Palatino"
        case "helvetica": return "Helvetica Neue"
        case "verdana": return "Verdana"
        case "mono", "system": return nil
        default: return family
        }
    }

    private var postScriptNames: [String] {
        switch family {
        case "serif": return ["Georgia"]
        case "palatino": return ["Palatino-Roman", "Palatino"]
        case "helvetica": return ["HelveticaNeue", "Helvetica Neue"]
        case "verdana": return ["Verdana"]
        default: return []
        }
    }

    // MARK: - Colores

    @MainActor public var effectiveTextColor: NSColor {
        Self.nsColor(fromHex: textHex) ?? .textColor
    }

    @MainActor public var effectiveBackgroundColor: NSColor {
        Self.nsColor(fromHex: backgroundHex) ?? .textBackgroundColor
    }

    @MainActor public var effectiveAccentColor: NSColor {
        Self.nsColor(fromHex: accentHex) ?? .controlAccentColor
    }

    @MainActor public var secondaryTextColor: NSColor {
        effectiveTextColor.withAlphaComponent(0.72)
    }

    @MainActor public var tertiaryTextColor: NSColor {
        effectiveTextColor.withAlphaComponent(0.48)
    }

    @MainActor public var faintFillColor: NSColor {
        effectiveTextColor.withAlphaComponent(0.08)
    }

    // MARK: - Cromado de la app (sidebar, outline, inspector, inicio)

    /// Solo cuando hay fondo personalizado se tiñe el cromado; en "auto"
    /// se conserva el aspecto nativo (materiales del sistema).
    public var usesCustomBackground: Bool {
        backgroundHex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() != "AUTO"
    }

    public var usesCustomText: Bool {
        textHex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() != "AUTO"
    }

    public var usesCustomAccent: Bool {
        accentHex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() != "AUTO"
    }

    @MainActor public var chromeSidebar: NSColor {
        effectiveBackgroundColor.shaded(by: -0.055)
    }

    @MainActor public var chromeOutline: NSColor {
        effectiveBackgroundColor.shaded(by: -0.028)
    }

    @MainActor public var chromeCard: NSColor {
        // Tarjetas legibles tanto en fondos claros como oscuros.
        effectiveBackgroundColor.shaded(by: effectiveBackgroundColor.isDark ? 0.07 : 0.045)
    }

    @MainActor public var chromeCardBorder: NSColor {
        effectiveTextColor.withAlphaComponent(0.16)
    }

    @MainActor public var chromeSearchFill: NSColor {
        effectiveTextColor.withAlphaComponent(0.07)
    }

    /// Hex "#RRGGBB" a NSColor. Devuelve nil para "auto" o valores inválidos.
    public static func nsColor(fromHex hex: String) -> NSColor? {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard cleaned != "AUTO", cleaned != "" else { return nil }
        var value = cleaned
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let rgb = UInt32(value, radix: 16) else { return nil }
        let red = CGFloat((rgb & 0xFF0000) >> 16) / 255
        let green = CGFloat((rgb & 0x00FF00) >> 8) / 255
        let blue = CGFloat(rgb & 0x0000FF) / 255
        return NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }

    /// Hex a Color de SwiftUI (nil si es "auto").
    public static func swiftUIColor(fromHex hex: String) -> Color? {
        guard let ns = nsColor(fromHex: hex) else { return nil }
        return Color(nsColor: ns)
    }

    /// Color de SwiftUI a hex "#RRGGBB".
    @MainActor public static func hex(from color: Color) -> String {
        hex(from: NSColor(color))
    }

    public static func hex(from color: NSColor) -> String {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        let red = Int((rgb.redComponent * 255).rounded())
        let green = Int((rgb.greenComponent * 255).rounded())
        let blue = Int((rgb.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", max(0, min(255, red)), max(0, min(255, green)), max(0, min(255, blue)))
    }

    // MARK: - Atributos

    @MainActor public var textAlignment: NSTextAlignment {
        switch alignment {
        case "left": return .left
        case "center": return .center
        case "justify": return .justified
        case "right": return .right
        default: return .natural
        }
    }

    @MainActor public var attributes: [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = spacing
        paragraphStyle.paragraphSpacing = paragraph
        paragraphStyle.alignment = textAlignment
        var result: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: effectiveTextColor,
            .paragraphStyle: paragraphStyle,
        ]
        if tracking != 0 {
            result[.kern] = tracking
        }
        return result
    }
}

public extension NSColor {
    /// Luminancia relativa aproximada (0 = negro, 1 = blanco).
    var isDark: Bool {
        let rgb = usingColorSpace(.sRGB) ?? self
        let lum = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
        return lum < 0.45
    }

    /// Aclara (>0) u oscurece (<0) en el rango -1...1.
    func shaded(by amount: CGFloat) -> NSColor {
        let clamped = max(-1, min(1, amount))
        let rgb = usingColorSpace(.sRGB) ?? self
        let target: CGFloat = clamped > 0 ? 1 : 0
        let mix = abs(clamped)
        let red = rgb.redComponent + (target - rgb.redComponent) * mix
        let green = rgb.greenComponent + (target - rgb.greenComponent) * mix
        let blue = rgb.blueComponent + (target - rgb.blueComponent) * mix
        return NSColor(srgbRed: red, green: green, blue: blue, alpha: rgb.alphaComponent)
    }
}

// MARK: - Presets de color

public struct WritingThemePreset: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var lightTextHex: String
    public var lightBackgroundHex: String
    public var lightAccentHex: String
    public var darkTextHex: String
    public var darkBackgroundHex: String
    public var darkAccentHex: String
    public init(
        id: String, name: String,
        lightTextHex: String, lightBackgroundHex: String, lightAccentHex: String,
        darkTextHex: String, darkBackgroundHex: String, darkAccentHex: String
    ) {
        self.id = id
        self.name = name
        self.lightTextHex = lightTextHex
        self.lightBackgroundHex = lightBackgroundHex
        self.lightAccentHex = lightAccentHex
        self.darkTextHex = darkTextHex
        self.darkBackgroundHex = darkBackgroundHex
        self.darkAccentHex = darkAccentHex
    }

    /// Compatibilidad: los presets antiguos de un solo tono se exponen como
    /// variante clara.
    public var textHex: String { lightTextHex }
    public var backgroundHex: String { lightBackgroundHex }
    public var accentHex: String { lightAccentHex }

    public func hexes(for scheme: ColorScheme) -> (text: String, background: String, accent: String) {
        scheme == .dark
            ? (darkTextHex, darkBackgroundHex, darkAccentHex)
            : (lightTextHex, lightBackgroundHex, lightAccentHex)
    }
}

public extension WritingStyle {
    /// Cada combinación define variante clara y oscura para que el tema
    /// cambie con el modo. "Sistema" respeta los colores del Mac en ambos.
    static let themePresets: [WritingThemePreset] = [
        WritingThemePreset(
            id: "auto", name: "Sistema",
            lightTextHex: "auto", lightBackgroundHex: "auto", lightAccentHex: "auto",
            darkTextHex: "auto", darkBackgroundHex: "auto", darkAccentHex: "auto"
        ),
        WritingThemePreset(
            id: "paper", name: "Papel",
            lightTextHex: "#24211C", lightBackgroundHex: "#FAF7F0", lightAccentHex: "#8A6D3B",
            darkTextHex: "#EDE4D3", darkBackgroundHex: "#1F1B15", darkAccentHex: "#C9A86A"
        ),
        WritingThemePreset(
            id: "jasmine", name: "Jazmín",
            lightTextHex: "#2D3228", lightBackgroundHex: "#FBF9EA", lightAccentHex: "#63733B",
            darkTextHex: "#F1EFD9", darkBackgroundHex: "#252A22", darkAccentHex: "#C4D486"
        ),
        WritingThemePreset(
            id: "sepia", name: "Sepia",
            lightTextHex: "#433422", lightBackgroundHex: "#F1E9D2", lightAccentHex: "#8A6D3B",
            darkTextHex: "#E5D6B8", darkBackgroundHex: "#241C12", darkAccentHex: "#C9A86A"
        ),
        WritingThemePreset(
            id: "terracotta", name: "Terracota",
            lightTextHex: "#3A2A23", lightBackgroundHex: "#FAF1E9", lightAccentHex: "#9A4B30",
            darkTextHex: "#F1E3D7", darkBackgroundHex: "#2B211D", darkAccentHex: "#E29B7D"
        ),
        WritingThemePreset(
            id: "forest", name: "Bosque",
            lightTextHex: "#1E2B24", lightBackgroundHex: "#E9EFE8", lightAccentHex: "#3E7D4E",
            darkTextHex: "#E8EDE6", darkBackgroundHex: "#1A2620", darkAccentHex: "#7FB685"
        ),
        WritingThemePreset(
            id: "coast", name: "Costa",
            lightTextHex: "#1F3538", lightBackgroundHex: "#EDF5F4", lightAccentHex: "#286B72",
            darkTextHex: "#DDEDEF", darkBackgroundHex: "#17292D", darkAccentHex: "#81C4CC"
        ),
        WritingThemePreset(
            id: "lavender", name: "Lavanda",
            lightTextHex: "#342B43", lightBackgroundHex: "#F5F1F8", lightAccentHex: "#6B4F95",
            darkTextHex: "#EDE6F4", darkBackgroundHex: "#241D30", darkAccentHex: "#BCA2DF"
        ),
        WritingThemePreset(
            id: "graphite", name: "Grafito",
            lightTextHex: "#2B2F36", lightBackgroundHex: "#E8EBEF", lightAccentHex: "#2F6FED",
            darkTextHex: "#D7DCE2", darkBackgroundHex: "#2B2F36", darkAccentHex: "#64B5F6"
        ),
        WritingThemePreset(
            id: "night", name: "Noche",
            lightTextHex: "#23262B", lightBackgroundHex: "#EDEFF3", lightAccentHex: "#0A84FF",
            darkTextHex: "#E6E6E6", darkBackgroundHex: "#1E1E1E", darkAccentHex: "#0A84FF"
        ),
    ]
}
