import SwiftUI
import AppKit

struct SettingsView: View {
    @AppStorage("shortcutKeyCode") private var keyCode: Int = Int(HotKeyManager.defaultKeyCode)
    @AppStorage("shortcutModifiers") private var modifiers: Int = Int(HotKeyManager.defaultModifiers)

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Activation Shortcut")
                    Spacer()
                    ShortcutRecorderView(keyCode: $keyCode, modifiers: $modifiers) { newKeyCode, newModifiers in
                        NotificationCenter.default.post(
                            name: .shortcutDidChange, object: nil,
                            userInfo: ["keyCode": newKeyCode, "modifiers": newModifiers]
                        )
                    }
                }
            } footer: {
                Text("Cycles Disabled → Enabled → Interactive. Interactive mode and the default tool are set from the menu bar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
    }
}

extension Notification.Name {
    static let shortcutDidChange = Notification.Name("shortcutDidChange")
    static let shortcutRecordingChanged = Notification.Name("shortcutRecordingChanged")
}
