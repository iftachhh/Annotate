import Foundation

enum ToolType: String, CaseIterable {
    case pen, line, arrow, highlighter, rectangle, circle, text, counter, select, eraser

    var displayName: String {
        switch self {
        case .pen: return "Pen"
        case .line: return "Line"
        case .arrow: return "Arrow"
        case .highlighter: return "Highlighter"
        case .rectangle: return "Rectangle"
        case .circle: return "Circle"
        case .text: return "Text"
        case .counter: return "Counter"
        case .select: return "Select"
        case .eraser: return "Eraser"
        }
    }

    var keyEquivalent: Character {
        switch self {
        case .pen: return "p"
        case .line: return "l"
        case .arrow: return "a"
        case .highlighter: return "h"
        case .rectangle: return "r"
        case .circle: return "o"
        case .text: return "t"
        case .counter: return "n"
        case .select: return "v"
        case .eraser: return "e"
        }
    }

    var usesColor: Bool {
        switch self {
        case .select, .eraser: return false
        default: return true
        }
    }

    var usesWidth: Bool {
        [.pen, .line, .arrow, .highlighter, .rectangle, .circle, .eraser].contains(self)
    }

    var usesFontSize: Bool { self == .text || self == .counter }
    var usesFontStyle: Bool { self == .text }

    /// Solid/dashed/dotted — no shortcut, picked from the context menu only.
    var usesLineStyle: Bool { [.pen, .line, .arrow, .highlighter].contains(self) }
    /// Same row as usesLineStyle, plus a "filled" option.
    var usesShapeStyle: Bool { self == .rectangle || self == .circle }

    /// The physical (ANSI-position) key code behind `keyEquivalent` — see PhysicalKeyCode. This is
    /// what shortcut MATCHING uses; `keyEquivalent` stays around purely to render a display label
    /// ("P") in the tool popup, independent of the active keyboard layout.
    var virtualKeyCode: UInt16 {
        switch self {
        case .pen: return 0x23        // kVK_ANSI_P
        case .line: return 0x25       // kVK_ANSI_L
        case .arrow: return 0x00      // kVK_ANSI_A
        case .highlighter: return 0x04 // kVK_ANSI_H
        case .rectangle: return 0x0F  // kVK_ANSI_R
        case .circle: return 0x1F     // kVK_ANSI_O
        case .text: return 0x11       // kVK_ANSI_T
        case .counter: return 0x2D    // kVK_ANSI_N
        case .select: return 0x09     // kVK_ANSI_V
        case .eraser: return 0x0E     // kVK_ANSI_E
        }
    }

    static func from(keyCode: UInt16) -> ToolType? {
        allCases.first { $0.virtualKeyCode == keyCode }
    }
}
