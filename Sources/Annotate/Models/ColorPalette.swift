import AppKit

struct PaletteColor {
    let name: String
    let color: NSColor
}

enum ColorPalette {
    static let entries: [PaletteColor] = [
        PaletteColor(name: "Red", color: .systemRed),
        PaletteColor(name: "Orange", color: .systemOrange),
        PaletteColor(name: "Yellow", color: .systemYellow),
        PaletteColor(name: "Green", color: .systemGreen),
        PaletteColor(name: "Blue", color: .systemBlue),
        PaletteColor(name: "Purple", color: .systemPurple),
        PaletteColor(name: "Black", color: .black),
        PaletteColor(name: "White", color: .white)
    ]

    static var colors: [NSColor] { entries.map(\.color) }
}
