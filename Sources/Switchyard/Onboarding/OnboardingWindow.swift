import AppKit
import SwiftUI

/// The first-run window. A real window rather than the menu-bar popover, because macOS
/// permission dialogs take focus and a popover closes when it loses focus.
@MainActor
final class OnboardingWindow: NSObject, NSWindowDelegate {
    static let shared = OnboardingWindow()

    private var window: NSWindow?
    private var model: OnboardingModel?

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let model = OnboardingModel()
        model.onFinish = { [weak self] in self?.close() }
        let window = NSWindow(contentViewController: NSHostingController(rootView: OnboardingView(model: model)))
        window.title = AppEnvironment.isRehearsal ? "Switchyard Setup (Rehearsal)" : "Switchyard Setup"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window
        self.model = model
        model.start()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        model?.stop()
        model = nil
        window = nil
    }
}
