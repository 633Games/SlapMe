import AppKit
import SwiftUI

extension Color {
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt64(s, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self = Color(red: r, green: g, blue: b)
    }

    func toHex() -> String? {
        #if canImport(AppKit)
        let ns = NSColor(self)
        guard let rgb = ns.usingColorSpace(.deviceRGB) ?? ns.usingColorSpace(.sRGB) else {
            return nil
        }
        let r = Int(round(rgb.redComponent * 255))
        let g = Int(round(rgb.greenComponent * 255))
        let b = Int(round(rgb.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
        #else
        return nil
        #endif
    }
}

enum IconPresets {
    static let colors: [(String, Color)] = [
        ("Pink", Color(hex: "#FF4D6D")!),
        ("Hot", Color(hex: "#FF2D55")!),
        ("Orange", Color(hex: "#FF9F0A")!),
        ("Violet", Color(hex: "#BF5AF2")!),
        ("Cyan", Color(hex: "#64D2FF")!),
        ("Mint", Color(hex: "#30D158")!),
        ("White", .white),
    ]
}
