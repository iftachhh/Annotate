import AppKit

/// Cmd/Option held-modifier temporary-tool-switch behavior, split out of OverlayView.swift.
extension OverlayView {
    /// Holding Cmd or Option temporarily switches to Select (to move/duplicate a layer) without
    /// leaving whatever tool was active; releasing it restores that tool. Mirrors common "modifier
    /// held = temporary tool" UX (e.g. spacebar-to-pan elsewhere). Option-drag additionally
    /// duplicates the hit shape — see mouseDown's .select case. Guarded off mid-draw/mid-text-edit
    /// to avoid orphaning an in-progress shape or hijacking Cmd+B / Cmd+digit / Option+digit / Cmd+Z
    /// while those are in use.
    override func flagsChanged(with event: NSEvent) {
        if suppressModifierOverrideUntilRelease {
            if !event.modifierFlags.contains(.command), !event.modifierFlags.contains(.option) {
                suppressModifierOverrideUntilRelease = false
            }
            super.flagsChanged(with: event)
            return
        }

        let cmdHeld = event.modifierFlags.contains(.command)
        if cmdHeld {
            if !isCommandTemporarySelect, appState.currentTool != .select, activeTextField == nil, appState.inProgress == nil {
                isCommandTemporarySelect = true
                toolBeforeCommandOverride = appState.currentTool
                appState.currentTool = .select
            }
        } else if isCommandTemporarySelect {
            if selectedAnnotationID == nil {
                revertCommandTemporarySelect()
            } else {
                // A select-drag is actively in progress — switching tools out from under it would
                // cut the move short. Defer until mouseUp finishes it.
                pendingCommandRevert = true
            }
        }

        let optionHeld = event.modifierFlags.contains(.option)
        if optionHeld {
            if !isOptionTemporarySelect, appState.currentTool != .select, activeTextField == nil, appState.inProgress == nil {
                isOptionTemporarySelect = true
                toolBeforeOptionOverride = appState.currentTool
                appState.currentTool = .select
            }
        } else if isOptionTemporarySelect {
            if selectedAnnotationID == nil {
                revertOptionTemporarySelect()
            } else {
                pendingOptionRevert = true
            }
        }

        // Visual hint for the option-drag-to-duplicate feature above — only when Select was already
        // the active tool (manually), Option is held alone, not stacked with Cmd. Excluding
        // isOptionTemporarySelect specifically matters: an Option+digit style shortcut on some other
        // tool also flips currentTool to .select via the override above, which isn't a duplicate-drag
        // and shouldn't flash the copy cursor.
        if activeTextField == nil {
            (optionHeld && !cmdHeld && !isOptionTemporarySelect && appState.currentTool == .select) ? NSCursor.dragCopy.set() : NSCursor.arrow.set()
        }
        super.flagsChanged(with: event)
    }

    /// Called by OverlayManager whenever leaving Enabled — if the user disables (Esc, or the
    /// activation shortcut) while still physically holding Cmd/Option (e.g. mid duplicate-drag),
    /// this view is about to be torn down and will never see the eventual release's flagsChanged
    /// event, so the normal revert-on-release above would never run. That left `appState.currentTool`
    /// (long-lived, not recreated per activation) stuck on `.select` for good, surfacing as "every
    /// now and then Select is checked right after enabling" — the corruption actually happened on
    /// the PRIOR disable, not the activation itself.
    func revertAnyActiveModifierOverride() {
        if isCommandTemporarySelect { revertCommandTemporarySelect() }
        if isOptionTemporarySelect { revertOptionTemporarySelect() }
    }

    func revertCommandTemporarySelect() {
        isCommandTemporarySelect = false
        pendingCommandRevert = false
        if let previous = toolBeforeCommandOverride {
            appState.currentTool = previous
        }
        toolBeforeCommandOverride = nil
    }

    func revertOptionTemporarySelect() {
        isOptionTemporarySelect = false
        pendingOptionRevert = false
        if let previous = toolBeforeOptionOverride {
            appState.currentTool = previous
        }
        toolBeforeOptionOverride = nil
    }
}
