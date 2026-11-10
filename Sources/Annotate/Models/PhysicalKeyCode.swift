import Foundation

/// Layout-independent physical key codes (ANSI keyboard positions). `event.keyCode` reports the
/// same value for the same physical key regardless of the active input layout (Hebrew, etc.);
/// `charactersIgnoringModifiers` does not — it returns whatever character that layout maps the key
/// to (e.g. "פ" instead of "p" under Hebrew for the same physical key). Tool shortcuts are meant to
/// be positional ("the key where P sits on a US layout"), so they must match on keyCode, not character.
enum PhysicalKeyCode {
    static let b: UInt16 = 0x0B
    static let digits: [UInt16] = [0x12, 0x13, 0x14, 0x15, 0x17, 0x16, 0x1A, 0x1C] // 1-8, in order
    static let minus: UInt16 = 0x1B
    static let equal: UInt16 = 0x18 // '=' key; '+' is Shift+this same physical key
    static let leftBracket: UInt16 = 0x21  // '['
    static let rightBracket: UInt16 = 0x1E // ']'
}
