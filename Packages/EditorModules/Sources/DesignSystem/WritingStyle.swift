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
            id: "sepia", name: "Sepia",
            lightTextHex: "#433422", lightBackgroundHex: "#F1E9D2", lightAccentHex: "#8A6D3B",
            darkTextHex: "#E5D6B8", darkBackgroundHex: "#241C12", darkAccentHex: "#C9A86A"
        ),
        WritingThemePreset(
            id: "night", name: "Noche",
            lightTextHex: "#23262B", lightBackgroundHex: "#EDEFF3", lightAccentHex: "#0A84FF",
            darkTextHex: "#E6E6E6", darkBackgroundHex: "#1E1E1E", darkAccentHex: "#0A84FF"
        ),
        WritingThemePreset(
            id: "graphite", name: "Grafito",
            lightTextHex: "#2B2F36", lightBackgroundHex: "#E8EBEF", lightAccentHex: "#2F6FED",
            darkTextHex: "#D7DCE2", darkBackgroundHex: "#2B2F36", darkAccentHex: "#64B5F6"
        ),
        WritingThemePreset(
            id: "forest", name: "Bosque",
            lightTextHex: "#1E2B24", lightBackgroundHex: "#E9EFE8", lightAccentHex: "#3E7D4E",
            darkTextHex: "#E8EDE6", darkBackgroundHex: "#1A2620", darkAccentHex: "#7FB685"
        ),
    ]
}

@MainActor public enum MarkdownAppearance {
    public static func decorate(_ storage: NSMutableAttributedString, document: MarkdownDocument, style: WritingStyle, lines: Range<Int>? = nil) {
        let selectedLines = document.lines[lines ?? document.lines.indices]
        let affected: NSRange
        if lines != nil {
            guard let first = selectedLines.first, let last = selectedLines.last else { return }
            affected = NSRange(location: first.range.location, length: NSMaxRange(last.range) - first.range.location)
        } else {
            affected = NSRange(location: 0, length: storage.length)
        }
        guard affected.length > 0, NSMaxRange(affected) <= storage.length else { return }
        storage.setAttributes(style.attributes, range: affected)
        guard style.syntax else { return }
        let mono = NSFont.monospacedSystemFont(ofSize: style.size - 1, weight: .regular)
        for line in selectedLines {
            guard line.range.length > 0, NSMaxRange(line.range) <= storage.length else { continue }
            switch line.kind {
            case .heading(let level):
                storage.addAttribute(.font, value: style.headingFont(level: level), range: line.range)
            case .code, .fence:
                storage.addAttribute(.font, value: mono, range: line.range)
                storage.addAttribute(.foregroundColor, value: style.secondaryTextColor, range: line.range)
            case .hidden:
                storage.addAttribute(.foregroundColor, value: style.tertiaryTextColor, range: line.range)
            case .quote:
                storage.addAttribute(.foregroundColor, value: style.secondaryTextColor, range: line.range)
            case .rule:
                storage.addAttribute(.foregroundColor, value: style.secondaryTextColor, range: line.range)
            case .text, .list, .orderedList, .taskList:
                break
            }
            if line.kind != .code, line.kind != .fence, line.kind != .hidden {
                decorateInline(in: storage, lineRange: line.range, style: style)
            }
            if line.prefixLength > 0, line.range.location + line.prefixLength <= storage.length {
                storage.addAttribute(.foregroundColor, value: style.tertiaryTextColor, range: NSRange(location: line.range.location, length: line.prefixLength))
            }
            if line.trailingLength > 0 {
                let location = NSMaxRange(line.range) - line.trailingLength
                // Evita teñir el salto de línea final como sufijo.
                let lineText = (storage.string as NSString).substring(with: line.range)
                let newlineLength = lineText.hasSuffix("\r\n") ? 2 : (lineText.hasSuffix("\n") || lineText.hasSuffix("\r") ? 1 : 0)
                if location >= line.range.location, line.trailingLength <= line.range.length - newlineLength {
                    storage.addAttribute(.foregroundColor, value: style.tertiaryTextColor, range: NSRange(location: location, length: line.trailingLength))
                }
            }
        }
    }

    // MARK: - Edición: inline sin regex

    private static func decorateInline(in storage: NSMutableAttributedString, lineRange: NSRange, style: WritingStyle) {
        let nsString = storage.string as NSString
        var effectiveLength = lineRange.length
        while effectiveLength > 0 {
            let code = nsString.character(at: lineRange.location + effectiveLength - 1)
            if code == 10 || code == 13 { effectiveLength -= 1 } else { break }
        }
        guard effectiveLength > 0 else { return }
        let effectiveRange = NSRange(location: lineRange.location, length: effectiveLength)
        let lineText = nsString.substring(with: effectiveRange)
        guard !lineText.isEmpty else { return }
        scanInline(lineText: lineText, baseOffset: effectiveRange.location, storage: storage, style: style)
    }

    private static func nsRange(of range: Range<String.Index>, in text: String, base: Int) -> NSRange? {
        guard let utf16Range = NSRange(range, in: text) as NSRange? else { return nil }
        return NSRange(location: base + utf16Range.location, length: utf16Range.length)
    }

    private static func isWordChar(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }

    private static func isEscapable(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1 else { return false }
        let value = scalar.value
        // Puntuación ASCII escapable en Markdown.
        if value < 128 {
            let puentes: Set<UInt32> = [33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 58, 59, 60, 61, 62, 63, 64, 91, 92, 93, 94, 95, 96, 123, 124, 125, 126]
            return puentes.contains(value)
        }
        return false
    }

    private static func fontAdding(traits wanted: NSFontTraitMask, to font: NSFont) -> NSFont {
        let current = NSFontManager.shared.traits(of: font)
        if current.contains(wanted) { return font }
        let combined = current.union(wanted)
        let converted = NSFontManager.shared.convert(font, toHaveTrait: combined)
        if NSFontManager.shared.traits(of: converted).contains(wanted) { return converted }
        // Reintento rasgo por rasgo para no perder la base cuando falta la variante combinada.
        var result = font
        if wanted.contains(.boldFontMask) {
            let candidate = NSFontManager.shared.convert(result, toHaveTrait: .boldFontMask)
            if NSFontManager.shared.traits(of: candidate).contains(.boldFontMask) { result = candidate }
        }
        if wanted.contains(.italicFontMask) {
            let candidate = NSFontManager.shared.convert(result, toHaveTrait: .italicFontMask)
            if NSFontManager.shared.traits(of: candidate).contains(.italicFontMask) { result = candidate }
        }
        return result
    }

    /// Colapsa un marcador markdown (`**`, `` ` ``, `[]()`, `\`…) para que no
    /// deje huecos en el modo editor: lo deja con tamaño mínimo y transparente
    /// pero sin borrarlo del texto (sigue editable y se copia con la fuente).
    /// Conserva negrita/cursiva para no romper el estilo exterior.
    private static func collapseMarker(in storage: NSMutableAttributedString, range: NSRange) {
        guard range.length > 0, NSMaxRange(range) <= storage.length else { return }
        let current = storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
        let base = current ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let tiny = NSFontManager.shared.convert(base, toSize: 0.1)
        let finalFont: NSFont = tiny.pointSize < 1 ? tiny : (NSFont(descriptor: base.fontDescriptor, size: 0.1) ?? tiny)
        storage.addAttribute(.font, value: finalFont, range: range)
        storage.addAttribute(.foregroundColor, value: NSColor.clear, range: range)
        storage.removeAttribute(.backgroundColor, range: range)
        storage.removeAttribute(.underlineStyle, range: range)
        storage.removeAttribute(.underlineColor, range: range)
        storage.removeAttribute(.strikethroughStyle, range: range)
        storage.removeAttribute(.strikethroughColor, range: range)
        storage.removeAttribute(.link, range: range)
    }

    private static func scanInline(lineText: String, baseOffset: Int, storage: NSMutableAttributedString, style: WritingStyle) {
        var index = lineText.startIndex
        while index < lineText.endIndex {
            let character = lineText[index]
            let nextIndex = lineText.index(after: index)
            // Escape `\*`: oculta la barra (colapsada, sin hueco) y salta el siguiente carácter.
            if character == "\\", nextIndex < lineText.endIndex, isEscapable(lineText[nextIndex]) {
                if let range = nsRange(of: index..<nextIndex, in: lineText, base: baseOffset) {
                    collapseMarker(in: storage, range: range)
                }
                index = lineText.index(after: nextIndex)
                continue
            }
            // Código `...` o ``...``.
            if character == "`" {
                if let end = handleCodeSpan(lineText: lineText, from: index, baseOffset: baseOffset, storage: storage, style: style) {
                    index = end
                    continue
                }
            }
            // Autolink `<https://…>`.
            if character == "<" {
                if let end = handleAutolink(lineText: lineText, from: index, baseOffset: baseOffset, storage: storage, style: style) {
                    index = end
                    continue
                }
            }
            // Imagen o enlace `[texto](url)`.
            let isLinkStart = character == "[" || (character == "!" && nextIndex < lineText.endIndex && lineText[nextIndex] == "[")
            if isLinkStart {
                if let end = handleLink(lineText: lineText, from: index, baseOffset: baseOffset, storage: storage, style: style) {
                    index = end
                    continue
                }
            }
            // Énfasis y tachado: prueba el marcador más largo primero.
            guard character == "*" || character == "_" || character == "~" else {
                index = nextIndex
                continue
            }
            var consumed = false
            for marker in ["***", "___", "**", "__", "~~", "*", "_"] {
                guard lineText[index...].hasPrefix(marker) else { continue }
                if let end = handleEmphasis(lineText: lineText, from: index, marker: marker, baseOffset: baseOffset, storage: storage, style: style) {
                    index = end
                    consumed = true
                    break
                }
                // Si el marcador largo no cierra, no intentes uno más corto en la misma posición
                // cuando comparte carácter (`***` fallido no es `**` + `*`).
                if marker == "***" || marker == "___" { break }
            }
            if consumed { continue }
            index = nextIndex
        }
    }

    private static func runLength(in text: String, from index: String.Index, char: Character) -> Int {
        var count = 0
        var cursor = index
        while cursor < text.endIndex, text[cursor] == char {
            count += 1
            cursor = text.index(after: cursor)
        }
        return count
    }

    private static func handleCodeSpan(lineText: String, from index: String.Index, baseOffset: Int, storage: NSMutableAttributedString, style: WritingStyle) -> String.Index? {
        let openLen = runLength(in: lineText, from: index, char: "`")
        guard openLen >= 1 else { return nil }
        var cursor = lineText.index(index, offsetBy: openLen, limitedBy: lineText.endIndex) ?? lineText.endIndex
        while cursor < lineText.endIndex {
            if lineText[cursor] == "`" {
                let closeLen = runLength(in: lineText, from: cursor, char: "`")
                if closeLen == openLen {
                    let closeEnd = lineText.index(cursor, offsetBy: closeLen, limitedBy: lineText.endIndex) ?? lineText.endIndex
                    let innerStart = lineText.index(index, offsetBy: openLen, limitedBy: lineText.endIndex) ?? lineText.endIndex
                    let inner = String(lineText[innerStart..<cursor])
                    guard !inner.isEmpty, !inner.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
                    if let fullRange = nsRange(of: index..<closeEnd, in: lineText, base: baseOffset) {
                        let mono = NSFont.monospacedSystemFont(ofSize: style.size - 1, weight: .regular)
                        storage.addAttribute(.font, value: mono, range: fullRange)
                        storage.addAttribute(.backgroundColor, value: style.faintFillColor, range: fullRange)
                        storage.addAttribute(.foregroundColor, value: style.effectiveTextColor, range: fullRange)
                        if let openRange = nsRange(of: index..<innerStart, in: lineText, base: baseOffset) {
                            collapseMarker(in: storage, range: openRange)
                        }
                        if let closeRange = nsRange(of: cursor..<closeEnd, in: lineText, base: baseOffset) {
                            collapseMarker(in: storage, range: closeRange)
                        }
                    }
                    return closeEnd
                }
                cursor = lineText.index(cursor, offsetBy: closeLen, limitedBy: lineText.endIndex) ?? lineText.endIndex
            } else if lineText[cursor] == "\\" {
                let after = lineText.index(after: cursor)
                cursor = after < lineText.endIndex ? lineText.index(after: after) : lineText.endIndex
            } else {
                cursor = lineText.index(after: cursor)
            }
        }
        return nil
    }

    private static func handleAutolink(lineText: String, from index: String.Index, baseOffset: Int, storage: NSMutableAttributedString, style: WritingStyle) -> String.Index? {
        guard let close = lineText[index...].firstIndex(of: ">") else { return nil }
        let innerStart = lineText.index(after: index)
        guard innerStart < close else { return nil }
        let inner = String(lineText[innerStart..<close])
        guard !inner.isEmpty, !inner.contains(" "), !inner.contains("\n") else { return nil }
        guard inner.contains(":") || inner.contains("@") else { return nil }
        let closeEnd = lineText.index(after: close)
        if let fullRange = nsRange(of: index..<closeEnd, in: lineText, base: baseOffset) {
            storage.addAttribute(.foregroundColor, value: style.effectiveAccentColor, range: fullRange)
            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: fullRange)
            if let openRange = nsRange(of: index..<innerStart, in: lineText, base: baseOffset) {
                collapseMarker(in: storage, range: openRange)
            }
            if let closeRange = nsRange(of: close..<closeEnd, in: lineText, base: baseOffset) {
                collapseMarker(in: storage, range: closeRange)
            }
        }
        return closeEnd
    }

    private static func findUnescaped(_ text: String, from start: String.Index, target: Character) -> String.Index? {
        var cursor = start
        while cursor < text.endIndex {
            if text[cursor] == "\\" {
                let after = text.index(after: cursor)
                cursor = after < text.endIndex ? text.index(after: after) : text.endIndex
                continue
            }
            if text[cursor] == target { return cursor }
            cursor = text.index(after: cursor)
        }
        return nil
    }

    private static func handleLink(lineText: String, from index: String.Index, baseOffset: Int, storage: NSMutableAttributedString, style: WritingStyle) -> String.Index? {
        var textStart = index
        let isImage: Bool
        if lineText[index] == "!" {
            let after = lineText.index(after: index)
            guard after < lineText.endIndex, lineText[after] == "[" else { return nil }
            isImage = true
            textStart = lineText.index(after: after)
        } else {
            isImage = false
            textStart = lineText.index(after: index)
        }
        guard let bracketClose = findUnescaped(lineText, from: textStart, target: "]") else { return nil }
        let labelRange = textStart..<bracketClose
        let afterBracket = lineText.index(after: bracketClose)
        // Enlace en línea `[texto](url)`.
        if afterBracket < lineText.endIndex, lineText[afterBracket] == "(" {
            let urlStart = lineText.index(after: afterBracket)
            guard let parenClose = findUnescaped(lineText, from: urlStart, target: ")") else { return nil }
            let urlInner = String(lineText[urlStart..<parenClose])
            // La URL puede estar vacía mientras se escribe; el título tras espacio se ignora para el estilo.
            _ = urlInner
            let linkEnd = lineText.index(after: parenClose)
            styleLink(labelRange: labelRange, bracketClose: bracketClose, parenOpen: afterBracket, urlRange: urlStart..<parenClose, end: linkEnd, start: index, isImage: isImage, lineText: lineText, baseOffset: baseOffset, storage: storage, style: style)
            // Recursión para énfasis/código dentro del texto del enlace.
            if !labelRange.isEmpty {
                let labelText = String(lineText[labelRange])
                let labelNS = NSRange(labelRange, in: lineText)
                let labelBase = baseOffset + labelNS.location
                scanInline(lineText: labelText, baseOffset: labelBase, storage: storage, style: style)
                // Reafirma el color del enlace tras la recursión (la recursión no lo pisa salvo código).
                if let reaffirm = nsRange(of: labelRange, in: lineText, base: baseOffset) {
                    if !isImage {
                        storage.addAttribute(.foregroundColor, value: style.effectiveAccentColor, range: reaffirm)
                        storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: reaffirm)
                    }
                }
            }
            return linkEnd
        }
        // Referencia `[texto][ref]` o colapsada `[texto][]`.
        if afterBracket < lineText.endIndex, lineText[afterBracket] == "[" {
            let refStart = lineText.index(after: afterBracket)
            guard let refClose = findUnescaped(lineText, from: refStart, target: "]") else { return nil }
            let linkEnd = lineText.index(after: refClose)
            if let labelNSRange = nsRange(of: labelRange, in: lineText, base: baseOffset) {
                storage.addAttribute(.foregroundColor, value: isImage ? style.secondaryTextColor : style.effectiveAccentColor, range: labelNSRange)
                if !isImage {
                    storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: labelNSRange)
                }
            }
            if let openRange = nsRange(of: index..<textStart, in: lineText, base: baseOffset) {
                collapseMarker(in: storage, range: openRange)
            }
            if let midRange = nsRange(of: bracketClose..<refStart, in: lineText, base: baseOffset) {
                collapseMarker(in: storage, range: midRange)
            }
            if let closeRange = nsRange(of: refClose..<linkEnd, in: lineText, base: baseOffset) {
                collapseMarker(in: storage, range: closeRange)
            }
            return linkEnd
        }
        return nil
    }

    private static func styleLink(labelRange: Range<String.Index>, bracketClose: String.Index, parenOpen: String.Index, urlRange: Range<String.Index>, end: String.Index, start: String.Index, isImage: Bool, lineText: String, baseOffset: Int, storage: NSMutableAttributedString, style: WritingStyle) {
        if !labelRange.isEmpty, let labelNS = nsRange(of: labelRange, in: lineText, base: baseOffset) {
            if isImage {
                storage.addAttribute(.foregroundColor, value: style.secondaryTextColor, range: labelNS)
            } else {
                storage.addAttribute(.foregroundColor, value: style.effectiveAccentColor, range: labelNS)
                storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: labelNS)
            }
        }
        // `!` + `[` en imágenes o `[` en enlaces.
        let openEnd: String.Index = {
            var cursor = lineText.index(after: start)
            if cursor < lineText.endIndex, lineText[cursor] == "[" {
                cursor = lineText.index(after: cursor)
            }
            return min(cursor, lineText.endIndex)
        }()
        if start < openEnd, let openRange = nsRange(of: start..<openEnd, in: lineText, base: baseOffset) {
            collapseMarker(in: storage, range: openRange)
        }
        if bracketClose < lineText.endIndex {
            let closeBracketEnd = lineText.index(after: bracketClose)
            if let closeBracket = nsRange(of: bracketClose..<closeBracketEnd, in: lineText, base: baseOffset) {
                collapseMarker(in: storage, range: closeBracket)
            }
        }
        if parenOpen < lineText.endIndex {
            let parenOpenEnd = lineText.index(after: parenOpen)
            if let parenOpenRange = nsRange(of: parenOpen..<parenOpenEnd, in: lineText, base: baseOffset) {
                collapseMarker(in: storage, range: parenOpenRange)
            }
        }
        if !urlRange.isEmpty, let urlNS = nsRange(of: urlRange, in: lineText, base: baseOffset) {
            collapseMarker(in: storage, range: urlNS)
        }
        if end > lineText.startIndex {
            let parenClose = lineText.index(before: end)
            if parenClose >= urlRange.upperBound, let closeRange = nsRange(of: parenClose..<end, in: lineText, base: baseOffset) {
                collapseMarker(in: storage, range: closeRange)
            }
        }
    }

    private static func handleEmphasis(lineText: String, from index: String.Index, marker: String, baseOffset: Int, storage: NSMutableAttributedString, style: WritingStyle) -> String.Index? {
        let markerLen = marker.count
        guard lineText[index...].hasPrefix(marker) else { return nil }
        let markerChar = marker.first ?? "*"
        // El marcador no debe formar parte de una racha más larga (`**` dentro de `***`).
        if index > lineText.startIndex, lineText[lineText.index(before: index)] == markerChar { return nil }
        let afterOpen = lineText.index(index, offsetBy: markerLen, limitedBy: lineText.endIndex) ?? lineText.endIndex
        guard afterOpen <= lineText.endIndex else { return nil }
        if afterOpen < lineText.endIndex, lineText[afterOpen] == markerChar { return nil }
        // Apertura: el contenido no empieza con espacio.
        guard afterOpen < lineText.endIndex, lineText[afterOpen] != " ", lineText[afterOpen] != "\t" else { return nil }
        if marker.contains("_") {
            // `_` dentro de palabra no es énfasis (`foo_bar`).
            if index > lineText.startIndex, isWordChar(lineText[lineText.index(before: index)]) { return nil }
        }
        var search = afterOpen
        while search < lineText.endIndex {
            guard let candidate = lineText[search...].range(of: marker)?.lowerBound else { return nil }
            // Cierre exacto, no parte de racha más larga.
            if candidate > lineText.startIndex, lineText[lineText.index(before: candidate)] == markerChar, markerLen == 1 {
                // Para `*` одино, el retroceso ya lo impide si venía de `**`; aquí solo evita `**` como cierre de `*`.
                // Comprueba la racha completa en el candidato.
                let run = runLength(in: lineText, from: candidate, char: markerChar)
                if run != markerLen {
                    search = lineText.index(candidate, offsetBy: run, limitedBy: lineText.endIndex) ?? lineText.endIndex
                    continue
                }
            } else {
                let run = runLength(in: lineText, from: candidate, char: markerChar)
                if run != markerLen {
                    search = lineText.index(candidate, offsetBy: max(1, run), limitedBy: lineText.endIndex) ?? lineText.endIndex
                    continue
                }
            }
            let candidateEnd = lineText.index(candidate, offsetBy: markerLen, limitedBy: lineText.endIndex) ?? lineText.endIndex
            if candidateEnd < lineText.endIndex, lineText[candidateEnd] == markerChar {
                search = candidateEnd
                continue
            }
            // Cierre: el contenido no termina con espacio.
            let contentEnd = candidate
            guard contentEnd > afterOpen else {
                search = candidateEnd
                continue
            }
            let lastContent = lineText[lineText.index(before: contentEnd)]
            guard lastContent != " ", lastContent != "\t" else {
                search = candidateEnd
                continue
            }
            if marker.contains("_") {
                if candidateEnd < lineText.endIndex, isWordChar(lineText[candidateEnd]) {
                    search = candidateEnd
                    continue
                }
            }
            // Evita que un escape anule el cierre.
            if isEscaped(in: lineText, at: candidate) {
                search = candidateEnd
                continue
            }
            let contentRange = afterOpen..<contentEnd
            let fullRange = index..<candidateEnd
            guard let fullNS = nsRange(of: fullRange, in: lineText, base: baseOffset) else { return nil }
            let baseFont = storage.attribute(.font, at: fullNS.location, effectiveRange: nil) as? NSFont ?? style.font
            switch marker {
            case "***", "___":
                let both: NSFontTraitMask = [.boldFontMask, .italicFontMask]
                storage.addAttribute(.font, value: fontAdding(traits: both, to: baseFont), range: fullNS)
            case "**", "__":
                storage.addAttribute(.font, value: fontAdding(traits: .boldFontMask, to: baseFont), range: fullNS)
            case "*", "_":
                storage.addAttribute(.font, value: fontAdding(traits: .italicFontMask, to: baseFont), range: fullNS)
            case "~~":
                storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: fullNS)
                storage.addAttribute(.foregroundColor, value: style.secondaryTextColor, range: fullNS)
            default:
                break
            }
            // Colapsa los marcadores (sin huecos) en vez de atenuarlos.
            if let openNS = nsRange(of: index..<afterOpen, in: lineText, base: baseOffset) {
                collapseMarker(in: storage, range: openNS)
            }
            if let closeNS = nsRange(of: candidate..<candidateEnd, in: lineText, base: baseOffset) {
                collapseMarker(in: storage, range: closeNS)
            }
            // Recursión para anidado (`**negrita *cursiva* **`).
            if !contentRange.isEmpty {
                let innerText = String(lineText[contentRange])
                let innerNS = NSRange(contentRange, in: lineText)
                let innerBase = baseOffset + innerNS.location
                // Evita recursión infinita con el mismo marcador en los extremos.
                if innerText.count < lineText.count {
                    scanInline(lineText: innerText, baseOffset: innerBase, storage: storage, style: style)
                    // Reafirma el estilo exterior tras la recursión (el interior ya combinó rasgos).
                    if let reaffirm = nsRange(of: contentRange, in: lineText, base: baseOffset) {
                        switch marker {
                        case "***", "___":
                            let current = storage.attribute(.font, at: reaffirm.location, effectiveRange: nil) as? NSFont ?? baseFont
                            storage.addAttribute(.font, value: fontAdding(traits: [.boldFontMask, .italicFontMask], to: current), range: reaffirm)
                        case "**", "__":
                            let current = storage.attribute(.font, at: reaffirm.location, effectiveRange: nil) as? NSFont ?? baseFont
                            storage.addAttribute(.font, value: fontAdding(traits: .boldFontMask, to: current), range: reaffirm)
                        case "*", "_":
                            let current = storage.attribute(.font, at: reaffirm.location, effectiveRange: nil) as? NSFont ?? baseFont
                            storage.addAttribute(.font, value: fontAdding(traits: .italicFontMask, to: current), range: reaffirm)
                        default:
                            break
                        }
                    }
                }
            }
            return candidateEnd
        }
        return nil
    }

    private static func isEscaped(in text: String, at index: String.Index) -> Bool {
        var backslashes = 0
        var cursor = index
        while cursor > text.startIndex {
            cursor = text.index(before: cursor)
            if text[cursor] == "\\" { backslashes += 1 } else { break }
        }
        return backslashes % 2 == 1
    }

    // MARK: - Lectura

    public static func readingText(_ source: String, document: MarkdownDocument, style: WritingStyle, forPrint: Bool = false) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let color = forPrint ? NSColor.black : style.effectiveTextColor
        let secondary = forPrint ? NSColor.darkGray : style.secondaryTextColor
        var paragraphBuffer: [String] = []
        var quoteBuffer: [String] = []
        var listBuffer: [(kind: MarkdownLine.Kind, content: String, indent: Int)] = []
        var codeBuffer: [String] = []

        func flushParagraph() {
            guard !paragraphBuffer.isEmpty else { return }
            let joined = paragraphBuffer.joined(separator: " ")
            paragraphBuffer.removeAll()
            guard !joined.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            result.append(renderBlock(content: joined, style: style, color: color, secondary: secondary, forPrint: forPrint, block: .paragraph))
        }

        func flushQuote() {
            guard !quoteBuffer.isEmpty else { return }
            // Agrupa citas separadas por `>` vacías en párrafos distintos.
            var groups: [[String]] = [[]]
            for entry in quoteBuffer {
                if entry.trimmingCharacters(in: .whitespaces).isEmpty {
                    groups.append([])
                } else {
                    groups[groups.count - 1].append(entry)
                }
            }
            quoteBuffer.removeAll()
            for group in groups {
                guard !group.isEmpty else { continue }
                let joined = group.joined(separator: " ")
                guard !joined.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
                result.append(renderBlock(content: joined, style: style, color: secondary, secondary: secondary, forPrint: forPrint, block: .quote))
            }
        }

        func flushList() {
            guard !listBuffer.isEmpty else { return }
            for (kind, content, indent) in listBuffer {
                let prefix: String
                switch kind {
                case .orderedList(let number):
                    prefix = "\(number). "
                case .taskList(let checked, let number):
                    let box = checked ? "☑ " : "☐ "
                    if let number {
                        prefix = "\(number). " + box
                    } else {
                        prefix = box
                    }
                default:
                    prefix = "• "
                }
                let display = prefix + content
                result.append(renderBlock(content: display, style: style, color: color, secondary: secondary, forPrint: forPrint, block: .listItem(indent: indent, task: isTask(kind))))
            }
            listBuffer.removeAll()
        }

        func flushCode() {
            guard !codeBuffer.isEmpty else { return }
            let joined = codeBuffer.joined(separator: "\n")
            codeBuffer.removeAll()
            result.append(renderCodeBlock(content: joined, style: style, forPrint: forPrint))
        }

        func isTask(_ kind: MarkdownLine.Kind) -> Bool {
            if case .taskList = kind { return true }
            return false
        }

        for line in document.lines {
            switch line.kind {
            case .fence, .hidden:
                flushParagraph(); flushQuote(); flushList(); flushCode()
                continue
            case .code:
                flushParagraph(); flushQuote(); flushList()
                codeBuffer.append(line.content)
                continue
            case .heading:
                flushParagraph(); flushQuote(); flushList(); flushCode()
            case .rule:
                flushParagraph(); flushQuote(); flushList(); flushCode()
            case .quote:
                flushParagraph(); flushList(); flushCode()
            case .list, .orderedList, .taskList:
                flushParagraph(); flushQuote(); flushCode()
            case .text:
                flushQuote(); flushList(); flushCode()
            }
            switch line.kind {
            case .heading(let level):
                let title = line.content.isEmpty ? " " : line.content
                result.append(renderBlock(content: title, style: style, color: color, secondary: secondary, forPrint: forPrint, block: .heading(level: level)))
            case .rule:
                result.append(renderRule(style: style, forPrint: forPrint))
            case .quote:
                quoteBuffer.append(line.content)
            case .list, .orderedList, .taskList:
                let indent = max(0, line.prefixLength - markerWidth(for: line.kind, content: line.content))
                listBuffer.append((line.kind, line.content, indent))
            case .text:
                if line.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    flushParagraph()
                } else {
                    paragraphBuffer.append(line.content.trimmingCharacters(in: .whitespaces))
                }
            case .code, .fence, .hidden:
                break
            }
        }
        flushParagraph(); flushQuote(); flushList(); flushCode()
        // Garantiza al menos un salto final sin acumular líneas vacías por bloques vacíos.
        if result.length == 0 {
            result.append(NSAttributedString(string: "\n", attributes: style.attributes))
        }
        return result
    }

    private static func markerWidth(for kind: MarkdownLine.Kind, content: String) -> Int {
        switch kind {
        case .list: return 2
        case .orderedList(let number): return "\(number)".count + 2
        case .taskList(_, let number):
            if let number { return "\(number)".count + 6 }
            return 6
        default: return 0
        }
    }

    private enum ReadingBlock {
        case paragraph
        case heading(level: Int)
        case quote
        case listItem(indent: Int, task: Bool)
    }

    private static func renderBlock(content: String, style: WritingStyle, color: NSColor, secondary: NSColor, forPrint: Bool, block: ReadingBlock) -> NSAttributedString {
        let output: NSMutableAttributedString
        if let parsed = try? AttributedString(markdown: content, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            output = NSMutableAttributedString(attributedString: NSAttributedString(parsed))
        } else {
            output = NSMutableAttributedString(string: content)
        }
        output.append(NSAttributedString(string: "\n"))
        let range = NSRange(location: 0, length: output.length)
        output.addAttributes(style.attributes, range: range)
        output.addAttribute(.foregroundColor, value: color, range: range)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = style.spacing
        paragraph.paragraphSpacing = style.paragraph
        paragraph.alignment = style.textAlignment
        switch block {
        case .heading(let level):
            let headingFont = style.headingFont(level: level)
            output.addAttribute(.font, value: headingFont, range: range)
            paragraph.headerLevel = level
            paragraph.paragraphSpacingBefore = 12
            paragraph.paragraphSpacing = 6
            // Reaplica cursiva/código/tachado con el tamaño del título (la base ya es seminegrita).
            output.enumerateAttribute(.inlinePresentationIntent, in: range) { value, run, _ in
                guard let intent = intent(from: value) else { return }
                if intent.contains(.emphasized) {
                    let current = output.attribute(.font, at: run.location, effectiveRange: nil) as? NSFont ?? headingFont
                    output.addAttribute(.font, value: fontAdding(traits: .italicFontMask, to: current), range: run)
                }
                if intent.contains(.code) {
                    output.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: headingFont.pointSize - 1, weight: .regular), range: run)
                    output.addAttribute(.backgroundColor, value: forPrint ? NSColor(white: 0.95, alpha: 1) : style.faintFillColor, range: run)
                }
                if intent.contains(.strikethrough) {
                    output.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: run)
                }
            }
        case .quote:
            paragraph.headIndent = 22
            paragraph.firstLineHeadIndent = 22
            paragraph.paragraphSpacing = max(style.paragraph, 4)
            output.addAttribute(.foregroundColor, value: secondary, range: range)
            // Barra lateral tenue `│ ` delante del texto citado.
            output.insert(NSAttributedString(string: "│ ", attributes: [
                .font: style.font,
                .foregroundColor: style.tertiaryTextColor,
            ]), at: 0)
            let full = NSRange(location: 0, length: output.length)
            output.addAttribute(.paragraphStyle, value: paragraph, range: full)
            fixInline(output: output, style: style, forPrint: forPrint, range: full)
            sanitizeLinks(in: output, style: style, forPrint: forPrint, range: full)
            return output
        case .listItem(let indent, _):
            let extra = min(48, indent * 4)
            paragraph.headIndent = 20 + CGFloat(extra)
            paragraph.firstLineHeadIndent = 20 + CGFloat(extra)
            paragraph.paragraphSpacing = max(style.paragraph, 2)
            output.addAttribute(.paragraphStyle, value: paragraph, range: range)
            fixInline(output: output, style: style, forPrint: forPrint, range: range)
            sanitizeLinks(in: output, style: style, forPrint: forPrint, range: range)
            return output
        case .paragraph:
            output.addAttribute(.paragraphStyle, value: paragraph, range: range)
            fixInline(output: output, style: style, forPrint: forPrint, range: range)
            sanitizeLinks(in: output, style: style, forPrint: forPrint, range: range)
            return output
        }
        output.addAttribute(.paragraphStyle, value: paragraph, range: range)
        // En títulos no se llama a fixInline genérico (usa tamaño de título); enlaces sí.
        sanitizeLinks(in: output, style: style, forPrint: forPrint, range: range)
        return output
    }

    private static func renderCodeBlock(content: String, style: WritingStyle, forPrint: Bool) -> NSAttributedString {
        let output = NSMutableAttributedString(string: content + "\n")
        let range = NSRange(location: 0, length: output.length)
        output.addAttributes(style.attributes, range: range)
        output.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: style.size - 1, weight: .regular), range: range)
        output.addAttribute(.foregroundColor, value: forPrint ? NSColor.darkGray : style.secondaryTextColor, range: range)
        output.addAttribute(.backgroundColor, value: forPrint ? NSColor(white: 0.95, alpha: 1) : style.faintFillColor, range: range)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = style.spacing
        paragraph.paragraphSpacing = max(style.paragraph, 4)
        paragraph.alignment = style.textAlignment
        paragraph.headIndent = 12
        paragraph.firstLineHeadIndent = 12
        output.addAttribute(.paragraphStyle, value: paragraph, range: range)
        return output
    }

    private static func renderRule(style: WritingStyle, forPrint: Bool) -> NSAttributedString {
        let output = NSMutableAttributedString(string: "────────────\n")
        let range = NSRange(location: 0, length: output.length)
        output.addAttributes(style.attributes, range: range)
        output.addAttribute(.foregroundColor, value: forPrint ? NSColor.darkGray : style.tertiaryTextColor, range: range)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineSpacing = style.spacing
        paragraph.paragraphSpacing = 8
        paragraph.paragraphSpacingBefore = 8
        output.addAttribute(.paragraphStyle, value: paragraph, range: range)
        return output
    }

    private static func intent(from value: Any?) -> InlinePresentationIntent? {
        if let direct = value as? InlinePresentationIntent { return direct }
        if let number = value as? NSNumber {
            return InlinePresentationIntent(rawValue: number.uintValue)
        }
        return nil
    }

    private static func fixInline(output: NSMutableAttributedString, style: WritingStyle, forPrint: Bool, range: NSRange) {
        output.enumerateAttribute(.inlinePresentationIntent, in: range) { value, run, _ in
            guard let intent = intent(from: value) else { return }
            var font = output.attribute(.font, at: run.location, effectiveRange: nil) as? NSFont ?? style.font
            var traits = NSFontTraitMask()
            if intent.contains(.stronglyEmphasized) { traits.insert(.boldFontMask) }
            if intent.contains(.emphasized) { traits.insert(.italicFontMask) }
            if !traits.isEmpty {
                font = fontAdding(traits: traits, to: font)
            }
            if intent.contains(.code) {
                font = .monospacedSystemFont(ofSize: style.size - 1, weight: .regular)
                output.addAttribute(.backgroundColor, value: forPrint ? NSColor(white: 0.95, alpha: 1) : style.faintFillColor, range: run)
            }
            output.addAttribute(.font, value: font, range: run)
            if intent.contains(.strikethrough) {
                output.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: run)
            }
        }
    }

    private static func sanitizeLinks(in output: NSMutableAttributedString, style: WritingStyle, forPrint: Bool, range: NSRange) {
        output.enumerateAttribute(.link, in: range) { value, run, _ in
            guard let url = value as? URL else { return }
            if !["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") {
                output.removeAttribute(.link, range: run)
            } else {
                output.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: run)
                if !forPrint {
                    output.addAttribute(.foregroundColor, value: style.effectiveAccentColor, range: run)
                }
            }
        }
    }
}
