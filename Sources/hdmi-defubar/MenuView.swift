import AppKit
import SwiftUI

struct MenuView: View {
    @ObservedObject var coordinator: Coordinator
    @Environment(\.openWindow) private var openWindow
    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        ForEach(coordinator.statusLines, id: \.self) { line in
            Text(line)
        }
        Text("Last action: \(coordinator.lastAction)")
            .onAppear { coordinator.refreshNotificationStatus() }
        if coordinator.notificationsDenied {
            Button("Allow notifications...") { coordinator.openNotificationSettings() }
        }
        Divider()
        Button("Save current layout") { coordinator.saveCurrentLayout() }
        Button("Restore saved layout") { coordinator.restoreSavedLayout() }
            .disabled(!coordinator.hasSavedLayoutForCurrentSet)
        Divider()
        Toggle("Pause automatic handling", isOn: $coordinator.isPaused)
        Toggle("Launch at login", isOn: Binding(
            get: { launchAtLogin },
            set: { newValue in
                LoginItem.setEnabled(newValue)
                launchAtLogin = LoginItem.isEnabled
            }))
            .disabled(!LoginItem.isAvailable)
        Button("Manage layouts...") {
            openWindow(id: "layouts")
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        Button("Quit hdmi-defubar") { NSApp.terminate(nil) }
    }
}
