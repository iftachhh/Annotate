import AppKit

/// Right-click context menu triggering, split out of OverlayView.swift.
extension OverlayView {
    override func rightMouseDown(with event: NSEvent) {
        showContextMenu(atLocal: convert(event.locationInWindow, from: nil))
    }

    func showContextMenu(atLocal local: CGPoint) {
        let global = toGlobal(local)
        let hitAnnotationID = appState.annotations.last(where: { $0.hitTest(global) })?.id
        let menu = OverlayContextMenu.build(appState: appState, target: self, hudController: hudController, hitAnnotationID: hitAnnotationID)
        menu.popUp(positioning: nil, at: local, in: self)
    }
}
