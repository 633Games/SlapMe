import AppKit

enum StatusItemIcon {
    static let symbolName = "hand.raised.fill"
    static let pointSize: CGFloat = 15

    static func image(color: NSColor) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        guard var symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: "SlapMe") else {
            return fallback(color: color)
        }
        if let configured = symbol.withSymbolConfiguration(config) {
            symbol = configured
        }

        // Prefer multicolor/palette rendering when available (macOS 12+).
        if let palette = symbol.withSymbolConfiguration(
            NSImage.SymbolConfiguration(paletteColors: [color])
        ) {
            let copy = palette.copy() as? NSImage ?? palette
            copy.isTemplate = false
            return copy
        }

        return tintedMask(symbol, color: color)
    }

    static func prideColor(at date: Date = Date()) -> NSColor {
        let t = date.timeIntervalSinceReferenceDate
        let hue = CGFloat((t * 0.18).truncatingRemainder(dividingBy: 1.0))
        return NSColor(calibratedHue: hue, saturation: 0.9, brightness: 1.0, alpha: 1.0)
    }

    private static func tintedMask(_ symbol: NSImage, color: NSColor) -> NSImage {
        let size = NSSize(
            width: max(symbol.size.width, pointSize),
            height: max(symbol.size.height, pointSize)
        )
        let out = NSImage(size: size)
        out.lockFocus()
        let rect = NSRect(origin: .zero, size: size)
        symbol.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
        color.setFill()
        rect.fill(using: .sourceAtop)
        out.unlockFocus()
        out.isTemplate = false
        return out
    }

    private static func fallback(color: NSColor) -> NSImage {
        let size = NSSize(width: pointSize + 2, height: pointSize + 2)
        let out = NSImage(size: size)
        out.lockFocus()
        color.setFill()
        NSBezierPath(ovalIn: NSRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2)).fill()
        out.unlockFocus()
        out.isTemplate = false
        return out
    }
}
