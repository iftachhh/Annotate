import AppKit
import CoreGraphics
import SwiftUI

final class HUDController {
    private var window: NSWindow?
    private var hideWorkItem: DispatchWorkItem?

    func show(text: String) {
        hideWorkItem?.cancel()

        let win = window ?? makeWindow()
        let hostingView = NSHostingView(rootView: HUDView(text: text))
        win.contentView = hostingView
        // fittingSize is only accurate once the view has actually been laid out;
        // measuring it before attaching to a window was truncating longer labels.
        hostingView.layoutSubtreeIfNeeded()
        let size = hostingView.fittingSize

        position(win, size: size)
        win.alphaValue = 1
        win.orderFrontRegardless()

        let work = DispatchWorkItem { [weak win] in
            guard let win else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                win.animator().alphaValue = 0
            }
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    private func makeWindow() -> NSWindow {
        let win = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = false
        // One above the overlay's own level so the HUD always renders on top of it.
        win.level = NSWindow.Level(rawValue: OverlayWindow.maxCoveringWindowLevel.rawValue + 1)
        win.collectionBehavior = [.canJoinAllSpaces, .transient]
        win.ignoresMouseEvents = true
        window = win
        return win
    }

    private func position(_ window: NSWindow, size: CGSize) {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        guard let screen else { return }
        let x = screen.frame.midX - size.width / 2
        let y = screen.frame.minY + 100
        window.setFrame(CGRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }
}
