import AppKit

/// Solid/dashed/dotted apply to line-based tools (line/arrow/highlighter); rectangle/circle also
/// get `.filled` as a fourth option. SF Symbol names double as the context-menu row's icons.
enum LineStyle: String, CaseIterable {
    case solid, dashed, dotted, filled

    var symbolName: String {
        switch self {
        case .solid: return "circle"
        case .dashed: return "circle.dashed"
        case .dotted: return "circle.dotted"
        case .filled: return "circle.fill"
        }
    }

    var displayName: String {
        switch self {
        case .solid: return "Solid"
        case .dashed: return "Dashed"
        case .dotted: return "Dotted"
        case .filled: return "Filled"
        }
    }

    /// Shape-based tools (rectangle/circle) additionally offer `.filled`; line-based tools don't.
    static func options(allowsFilled: Bool) -> [LineStyle] {
        allowsFilled ? allCases : [.solid, .dashed, .dotted]
    }
}

/// Sync groups (per product decision): color and width are shared across pen/line/arrow/
/// rectangle/circle/text/counter EXCEPT width doesn't apply to text/counter at all — highlighter
/// keeps its own independent color and width; text and counter share one font size between them.
/// Line style follows the same shared-vs-highlighter split as width.
final class ToolSettingsStore {
    // All tool settings are in-memory only — reset to these defaults every launch, not persisted.
    var sharedColorHex: String = "FF3B30"
    var highlighterColorHex: String = "FFEB3B"
    var sharedWidth: CGFloat = 4
    var highlighterWidth: CGFloat = 8
    var eraserWidth: CGFloat = 14
    var textCounterFontSize: CGFloat = 20
    var sharedLineStyle: LineStyle = .solid
    var highlighterLineStyle: LineStyle = .solid
    var textFontStyle: TextFontStyle = .sansSerif
    var textBold: Bool = true

    func color(for tool: ToolType) -> String { tool == .highlighter ? highlighterColorHex : sharedColorHex }
    func setColor(for tool: ToolType, _ hex: String) {
        if tool == .highlighter { highlighterColorHex = hex } else { sharedColorHex = hex }
    }

    func width(for tool: ToolType) -> CGFloat {
        switch tool {
        case .highlighter: return highlighterWidth
        case .eraser: return eraserWidth
        default: return sharedWidth
        }
    }
    func setWidth(for tool: ToolType, _ value: CGFloat) {
        switch tool {
        case .highlighter: highlighterWidth = value
        case .eraser: eraserWidth = value
        default: sharedWidth = value
        }
    }

    func fontSize(for tool: ToolType) -> CGFloat { textCounterFontSize }
    func setFontSize(for tool: ToolType, _ value: CGFloat) { textCounterFontSize = value }

    func lineStyle(for tool: ToolType) -> LineStyle { tool == .highlighter ? highlighterLineStyle : sharedLineStyle }
    func setLineStyle(for tool: ToolType, _ style: LineStyle) {
        if tool == .highlighter { highlighterLineStyle = style } else { sharedLineStyle = style }
    }

    func fontStyle(for tool: ToolType) -> TextFontStyle { textFontStyle }
    func setFontStyle(for tool: ToolType, _ style: TextFontStyle) { textFontStyle = style }

    func bold(for tool: ToolType) -> Bool { textBold }
    func setBold(for tool: ToolType, _ value: Bool) { textBold = value }
}

extension NSColor {
    var hexString: String {
        guard let rgb = usingColorSpace(.sRGB) else { return "FF3B30" }
        let r = Int(rgb.redComponent * 255), g = Int(rgb.greenComponent * 255), b = Int(rgb.blueComponent * 255)
        return String(format: "%02X%02X%02X", r, g, b)
    }

    /// sRGB, not deviceRGB — the eraser rasterizes annotations through an offscreen bitmap
    /// (see OverlayView.rasterize), and deviceRGB's appearance depends on the display's actual
    /// color profile, so a color that round-trips through that bitmap on a wide-gamut (P3) display
    /// visibly shifts. sRGB is a fixed, well-defined space CoreGraphics reproduces identically
    /// wherever it's composited.
    convenience init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        let r = CGFloat((value >> 16) & 0xFF) / 255
        let g = CGFloat((value >> 8) & 0xFF) / 255
        let b = CGFloat(value & 0xFF) / 255
        self.init(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}
