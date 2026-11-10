import AppKit

/// Font family for the text tool — no shortcut-free UI choice like line style, picked from the
/// context menu or Option+digit. Playpen Sans/David Libre/Gveret Levin all ship as bundled Google
/// Fonts font files (see AppDelegate.registerBundledFonts); PostScript names come straight from
/// each font's name table.
enum TextFontStyle: String, CaseIterable {
    case sansSerif, serif, handwritten

    var displayName: String {
        switch self {
        case .sansSerif: return "Sans Serif"
        case .serif: return "Serif"
        case .handwritten: return "Handwritten"
        }
    }

    /// `text` picks the actual face for `.handwritten`, which has no single font covering both
    /// scripts: Playpen Sans (Latin) has no Hebrew glyphs, and Gveret Levin (Hebrew handwriting)
    /// has no Latin ones. Irrelevant for the other two styles — safe to omit (e.g. context-menu icons).
    func font(size: CGFloat, bold: Bool, text: String = "") -> NSFont {
        switch self {
        case .sansSerif:
            return bold ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size)
        case .serif:
            let name = bold ? "DavidLibre-Bold" : "DavidLibre-Regular"
            return NSFont(name: name, size: size) ?? .systemFont(ofSize: size)
        case .handwritten:
            // Neither ships a distinct bold weight, so bold is ignored here rather than faking a
            // synthetic (usually ugly) bold transform.
            let name = text.isRTLText ? "GveretLevin-Regular" : "PlaypenSans-Regular"
            return NSFont(name: name, size: size) ?? .systemFont(ofSize: size)
        }
    }
}

extension StringProtocol {
    /// True if the first strong-directional character (Unicode bidi P2/P3 approximation) belongs
    /// to an RTL script (Hebrew/Arabic). Good enough to auto-flip text-tool alignment/anchoring
    /// for Hebrew without pulling in a full bidi algorithm.
    var isRTLText: Bool {
        for scalar in unicodeScalars {
            switch scalar.value {
            case 0x0590...0x05FF, 0x0600...0x06FF, 0x0750...0x077F, 0x08A0...0x08FF, 0xFB1D...0xFDFF, 0xFE70...0xFEFF:
                return true
            case 0x0041...0x005A, 0x0061...0x007A, 0x00C0...0x02AF:
                return false
            default:
                continue
            }
        }
        return false
    }
}
