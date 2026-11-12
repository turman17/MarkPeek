import SwiftUI

/// The few visual constants the app's own chrome uses. The document look
/// comes from `Theme`; this is only for MarkPeek's native UI.
enum Design {
    /// Brand umber sampled from the app icon. Used only as a faint tint
    /// (hero panels, surfaces); controls follow the user's macOS accent color.
    static let brand = Color(.sRGB, red: 0.545, green: 0.373, blue: 0.243)

    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Radius {
        static let s: CGFloat = 6
        static let m: CGFloat = 10
        static let l: CGFloat = 14
    }
}

/// Behind-window blur, the translucent surface the reader and empty states sit on.
struct Glass: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}

// MARK: - Theme fonts in native UI

extension Font {
    /// Best native match for a theme's CSS font family, for small previews.
    static func themeFamily(_ family: String, size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let lower = family.lowercased()
        if lower.isEmpty || lower.hasPrefix("-apple-system") || lower == "system-ui" {
            return .system(size: size, weight: weight)
        }
        if lower.contains("mono") { return .system(size: size, weight: weight, design: .monospaced) }
        if NSFont(name: family, size: size) != nil { return .custom(family, size: size).weight(weight) }
        let serif = lower.contains("serif") || lower == "charter" || lower == "georgia" || lower == "palatino"
        return .system(size: size, weight: weight, design: serif ? .serif : .default)
    }
}

extension Theme {
    /// The palette to show in native UI for the given appearance.
    func palette(for scheme: ColorScheme) -> Palette {
        scheme == .dark && appearance != .light ? dark : light
    }

    var headingFontWeight: Font.Weight {
        switch typography.headingWeight {
        case ..<500: .regular
        case ..<600: .medium
        case ..<700: .semibold
        default: .bold
        }
    }
}

// MARK: - Color <-> hex

extension Color {
    init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&value)
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    var hexString: String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .black
        return String(
            format: "#%02X%02X%02X",
            Int(round(ns.redComponent * 255)),
            Int(round(ns.greenComponent * 255)),
            Int(round(ns.blueComponent * 255))
        )
    }
}

extension NSAppearance {
    static func forScheme(_ scheme: ThemeColorScheme?) -> NSAppearance? {
        switch scheme {
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        case nil: nil
        }
    }
}
