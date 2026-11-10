import SwiftUI
import AppKit
import Carbon

struct ShortcutRecorderView: NSViewRepresentable {
    @Binding var keyCode: Int
    @Binding var modifiers: Int
    var onChange: (UInt32, UInt32) -> Void

    func makeNSView(context: Context) -> RecorderNSView {
        let view = RecorderNSView()
        view.onCapture = { newKeyCode, newModifiers in
            keyCode = Int(newKeyCode)
            modifiers = Int(newModifiers)
            onChange(newKeyCode, newModifiers)
        }
        view.onRecordingChanged = { isRecording in
            NotificationCenter.default.post(name: .shortcutRecordingChanged, object: nil, userInfo: ["isRecording": isRecording])
        }
        view.displayString = Self.describe(keyCode: keyCode, modifiers: modifiers)
        return view
    }

    func updateNSView(_ nsView: RecorderNSView, context: Context) {
        nsView.displayString = Self.describe(keyCode: keyCode, modifiers: modifiers)
    }

    static func describe(keyCode: Int, modifiers: Int) -> String {
        let mods = UInt32(modifiers)
        var parts = ""
        if mods & UInt32(controlKey) != 0 { parts += "⌃" }
        if mods & UInt32(optionKey) != 0 { parts += "⌥" }
        if mods & UInt32(shiftKey) != 0 { parts += "⇧" }
        if mods & UInt32(cmdKey) != 0 { parts += "⌘" }
        return parts + keyName(for: keyCode)
    }

    static func keyName(for keyCode: Int) -> String {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutDataPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return "?"
        }
        let layoutData = Unmanaged<CFData>.fromOpaque(layoutDataPointer).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = layoutData.withUnsafeBytes { rawPtr -> OSStatus in
            let keyLayoutPtr = rawPtr.bindMemory(to: UCKeyboardLayout.self).baseAddress!
            return UCKeyTranslate(keyLayoutPtr, UInt16(keyCode), UInt16(kUCKeyActionDown), 0,
                                   UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                   &deadKeyState, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return "?" }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }
}

final class RecorderNSView: NSView {
    var onCapture: ((UInt32, UInt32) -> Void)?
    var onRecordingChanged: ((Bool) -> Void)?
    var displayString: String = "" { didSet { needsDisplay = true } }
    private var isRecording = false

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 200, height: 28) }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        let path = NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6)
        path.fill()
        NSColor.separatorColor.setStroke()
        path.stroke()

        let text = isRecording ? "Type a shortcut…" : displayString
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor]
        let size = (text as NSString).size(withAttributes: attrs)
        let point = CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2)
        (text as NSString).draw(at: point, withAttributes: attrs)
    }

    override func mouseDown(with event: NSEvent) {
        isRecording = true
        needsDisplay = true
        window?.makeFirstResponder(self)
        onRecordingChanged?(true)
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { return }
        let modifiers = HotKeyManager.carbonModifiers(from: event.modifierFlags)
        guard modifiers != 0 else { return }
        isRecording = false
        onCapture?(UInt32(event.keyCode), modifiers)
        needsDisplay = true
        onRecordingChanged?(false)
    }

    override func resignFirstResponder() -> Bool {
        if isRecording {
            isRecording = false
            needsDisplay = true
            onRecordingChanged?(false)
        }
        return super.resignFirstResponder()
    }
}
