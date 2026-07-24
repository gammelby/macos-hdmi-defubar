import AppKit
import SwiftUI
import DefubarCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menubar-only, also when running unbundled where LSUIElement
        // does not apply.
        NSApp.setActivationPolicy(.accessory)
    }
}

struct DefubarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var coordinator: Coordinator

    init() {
        let coordinator = Coordinator(system: CGDisplaySystem(),
                                      store: LayoutStore(url: LayoutStore.defaultURL))
        _coordinator = StateObject(wrappedValue: coordinator)
        coordinator.start()
    }

    var body: some Scene {
        MenuBarExtra("HDMI Defubar", systemImage: "display.2") {
            MenuView(coordinator: coordinator)
        }
        Window("Manage layouts", id: "layouts") {
            LayoutsPanel(coordinator: coordinator)
        }
        .windowResizability(.contentSize)
    }
}
