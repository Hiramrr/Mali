import AppKit

/// Dibuja un `DiagramGraph` como imagen para un `NSTextAttachment`: sirve igual en lectura, PDF y Word.
@MainActor public enum DiagramRenderer {
    public struct Palette {
        public var text: NSColor
        public var secondary: NSColor
        public var fill: NSColor
        public var stroke: NSColor
        public var background: NSColor

        public init(text: NSColor, secondary: NSColor, fill: NSColor, stroke: NSColor, background: NSColor) {
            self.text = text
            self.secondary = secondary
            self.fill = fill
            self.stroke = stroke
            self.background = background
        }

        public static var print: Palette { Palette(text: .black, secondary: .darkGray, fill: .white, stroke: .black, background: .white) }
    }

    static let minWidth: CGFloat = 96
    static let maxWidth: CGFloat = 320

    /// Tamaño de cada nodo según su texto y su forma.
    public static func nodeSizes(for graph: DiagramGraph, font: NSFont) -> [CGSize] {
        graph.nodes.map { node in
            let text = measure(node.text, font: font, width: maxWidth - 24)
            switch node.shape {
            case .rounded, .stadium:
                return CGSize(width: min(maxWidth, max(minWidth, text.width + 24)), height: max(40, text.height + 20))
            case .decision:
                // Un rombo necesita casi el doble de caja que su texto para no cortarlo.
                return CGSize(width: min(maxWidth + 40, max(minWidth + 24, text.width * 1.5 + 32)), height: max(60, text.height * 2 + 20))
            case .terminal:
                let diameter = min(maxWidth, max(56, max(text.width, text.height) + 28))
                return CGSize(width: diameter, height: diameter)
            }
        }
    }

    /// Imagen del diagrama a escala 2× para que el PDF no salga borroso; su `size` va en puntos.
    public static func image(for graph: DiagramGraph, font: NSFont, palette: Palette) -> NSImage? {
        let layout = DiagramLayout(graph: graph, sizes: nodeSizes(for: graph, font: font))
        guard layout.size.width > 0, layout.size.height > 0 else { return nil }
        let scale: CGFloat = 2
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(ceil(layout.size.width * scale)), pixelsHigh: Int(ceil(layout.size.height * scale)),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let bitmapContext = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        // Contexto volteado: AppKit dibuja el texto derecho con el origen arriba.
        let context = NSGraphicsContext(cgContext: bitmapContext.cgContext, flipped: true)
        bitmap.size = layout.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: scale, y: scale)
        context.cgContext.translateBy(x: 0, y: layout.size.height)
        context.cgContext.scaleBy(x: 1, y: -1)
        draw(graph, layout: layout, font: font, palette: palette)
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: layout.size)
        image.addRepresentation(bitmap)
        image.accessibilityDescription = graph.accessibilityDescription
        return image
    }

    static func draw(_ graph: DiagramGraph, layout: DiagramLayout, font: NSFont, palette: Palette) {
        for route in layout.routes {
            let path = roundedPolyline(route.points, radius: 8)
            path.lineWidth = 1.2
            palette.secondary.setStroke()
            path.stroke()
            if route.points.count >= 2 {
                arrowHead(to: route.points[route.points.count - 1], from: route.points[route.points.count - 2], color: palette.secondary)
            }
        }
        for (node, frame) in zip(graph.nodes, layout.frames) {
            let path = shape(node.shape, in: frame)
            palette.fill.setFill()
            path.fill()
            path.lineWidth = 1.2
            palette.stroke.setStroke()
            path.stroke()
            let inset: CGFloat = node.shape == .decision ? frame.width * 0.2 : 12
            drawText(node.text, in: frame.insetBy(dx: inset, dy: 4), font: font, color: palette.text)
        }
        let labelFont = NSFont.systemFont(ofSize: max(9, font.pointSize - 2))
        for route in layout.routes {
            guard let label = route.label, let center = route.labelCenter else { continue }
            let size = measure(label, font: labelFont, width: 160)
            let box = CGRect(x: center.x - size.width / 2 - 4, y: center.y - size.height / 2 - 1, width: size.width + 8, height: size.height + 2)
            palette.background.setFill()
            NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4).fill()
            drawText(label, in: box, font: labelFont, color: palette.secondary)
        }
    }

    static func shape(_ shape: DiagramNode.Shape, in frame: CGRect) -> NSBezierPath {
        switch shape {
        case .rounded:
            return NSBezierPath(roundedRect: frame, xRadius: 8, yRadius: 8)
        case .stadium:
            return NSBezierPath(roundedRect: frame, xRadius: frame.height / 2, yRadius: frame.height / 2)
        case .terminal:
            return NSBezierPath(ovalIn: frame)
        case .decision:
            let path = NSBezierPath()
            path.move(to: CGPoint(x: frame.midX, y: frame.minY))
            path.line(to: CGPoint(x: frame.maxX, y: frame.midY))
            path.line(to: CGPoint(x: frame.midX, y: frame.maxY))
            path.line(to: CGPoint(x: frame.minX, y: frame.midY))
            path.close()
            return path
        }
    }

    /// Polilínea con esquinas redondeadas; evita quiebros bruscos en los cambios de dirección.
    static func roundedPolyline(_ points: [CGPoint], radius: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        guard let first = points.first else { return path }
        path.move(to: first)
        for index in points.indices.dropFirst().dropLast() {
            let corner = points[index]
            let before = points[index - 1]
            let after = points[index + 1]
            let incoming = hypot(corner.x - before.x, corner.y - before.y)
            let outgoing = hypot(after.x - corner.x, after.y - corner.y)
            let r = min(radius, incoming / 2, outgoing / 2)
            path.appendArc(from: corner, to: after, radius: r)
        }
        if let last = points.last, points.count > 1 { path.line(to: last) }
        return path
    }

    static func arrowHead(to tip: CGPoint, from tail: CGPoint, color: NSColor) {
        let angle = atan2(tip.y - tail.y, tip.x - tail.x)
        let length: CGFloat = 7
        let path = NSBezierPath()
        path.move(to: tip)
        path.line(to: CGPoint(x: tip.x - length * cos(angle - .pi / 7), y: tip.y - length * sin(angle - .pi / 7)))
        path.line(to: CGPoint(x: tip.x - length * cos(angle + .pi / 7), y: tip.y - length * sin(angle + .pi / 7)))
        path.close()
        color.setFill()
        path.fill()
    }

    static func attributes(font: NSFont, color: NSColor) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        return [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
    }

    static func measure(_ text: String, font: NSFont, width: CGFloat) -> CGSize {
        let bounds = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes(font: font, color: .black))
        return CGSize(width: ceil(bounds.width), height: ceil(bounds.height))
    }

    static func drawText(_ text: String, in rect: CGRect, font: NSFont, color: NSColor) {
        let size = measure(text, font: font, width: rect.width)
        let box = CGRect(x: rect.minX, y: rect.midY - size.height / 2, width: rect.width, height: size.height)
        (text as NSString).draw(with: box, options: [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine], attributes: attributes(font: font, color: color))
    }
}
