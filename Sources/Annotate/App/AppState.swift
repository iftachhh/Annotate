import AppKit

enum AppMode {
    case disabled, enabled, interactive
}

final class AppState {
    private static let lastUsedToolKey = "lastUsedTool"
    private static let defaultToolPreferenceKey = "defaultToolPreference"
    private static let interactiveModeEnabledKey = "interactiveModeEnabled"
    private static let showAlwaysTipKey = "showAlwaysTip"
    /// Fixed (not user-configurable — was a Settings stepper, now just a constant): if the shortcut
    /// is pressed again within this long of entering Interactive, it jumps back to Enabled instead
    /// of Disabled — a long stint in Interactive usually means the user wants to keep annotating.
    private static let interactiveReenableWindow: TimeInterval = 5

    var mode: AppMode = .disabled
    /// Persists every change as "last used", regardless of the current startup preference — so
    /// switching the default-tool preference to "Last Used" later has something meaningful to restore.
    var currentTool: ToolType = .pen {
        didSet { UserDefaults.standard.set(currentTool.rawValue, forKey: Self.lastUsedToolKey) }
    }
    var annotations: [Annotation] = []
    var inProgress: Annotation?
    var nextCounterValue: Int = 1
    let toolSettings = ToolSettingsStore()

    /// Toggled via the menu-bar checkbox (AppDelegate), not Settings.
    var interactiveModeEnabled: Bool {
        didSet { UserDefaults.standard.set(interactiveModeEnabled, forKey: Self.interactiveModeEnabledKey) }
    }

    /// Toggled via the menu-bar checkbox (AppDelegate) — keeps the current tool's width/size/color
    /// preview tracking the cursor at all times instead of only flashing after a shortcut change.
    var showAlwaysTip: Bool {
        didSet { UserDefaults.standard.set(showAlwaysTip, forKey: Self.showAlwaysTipKey) }
    }

    /// Set by OverlayManager; called whenever annotations/inProgress change so every
    /// per-screen overlay window redraws from the one shared canvas.
    var contentDidChange: (() -> Void)?

    /// Set by AppDelegate whenever Interactive mode is entered, so nextMode() can tell how long it's been active.
    var interactiveEnteredAt: Date?

    /// Set by AppDelegate; lets OverlayView (Esc key) force a direct mode change without a reference to it.
    var setMode: ((AppMode) -> Void)?

    private var undoStack: [(annotations: [Annotation], nextCounterValue: Int)] = []
    private var redoStack: [(annotations: [Annotation], nextCounterValue: Int)] = []

    init() {
        interactiveModeEnabled = (UserDefaults.standard.object(forKey: Self.interactiveModeEnabledKey) as? Bool) ?? true
        showAlwaysTip = (UserDefaults.standard.object(forKey: Self.showAlwaysTipKey) as? Bool) ?? false
        applyDefaultToolPreference()
    }

    /// Applied at launch, and again by AppDelegate every time Disabled → Enabled — so a specific
    /// configured default tool (not "Last Used") is restored on every activation, not just once at
    /// launch, while "Last Used" naturally leaves `currentTool` exactly as the user left it.
    func applyDefaultToolPreference() {
        let preference = UserDefaults.standard.string(forKey: Self.defaultToolPreferenceKey) ?? "pen"
        if preference == "lastUsed" {
            let lastUsed = UserDefaults.standard.string(forKey: Self.lastUsedToolKey).flatMap { ToolType(rawValue: $0) }
            currentTool = lastUsed ?? .pen
        } else {
            currentTool = ToolType(rawValue: preference) ?? .pen
        }
    }

    /// Interactive is only useful once something is drawn, so an empty canvas skips it — same as
    /// when the user has turned Interactive mode off entirely in the menu bar.
    func nextMode() -> AppMode {
        switch mode {
        case .disabled: return .enabled
        case .enabled: return (interactiveModeEnabled && !annotations.isEmpty) ? .interactive : .disabled
        case .interactive:
            guard let enteredAt = interactiveEnteredAt,
                  Date().timeIntervalSince(enteredAt) > Self.interactiveReenableWindow else {
                return .disabled
            }
            return .enabled
        }
    }

    func pushUndoSnapshot() {
        undoStack.append((annotations, nextCounterValue))
        if undoStack.count > 50 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append((annotations, nextCounterValue))
        annotations = previous.annotations
        nextCounterValue = previous.nextCounterValue
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append((annotations, nextCounterValue))
        annotations = next.annotations
        nextCounterValue = next.nextCounterValue
    }

    /// Wipes the undo/redo history along with the canvas — a clear is a fresh start, not an undoable
    /// step. Counter numbering always resets too, even if the canvas was already empty (e.g. every
    /// counter annotation was individually erased/undone already, leaving nextCounterValue stale).
    func clearAll() {
        nextCounterValue = 1
        guard !annotations.isEmpty || !undoStack.isEmpty || !redoStack.isEmpty else { return }
        annotations = []
        undoStack.removeAll()
        redoStack.removeAll()
    }
}
