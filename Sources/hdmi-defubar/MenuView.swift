import AppKit
import SwiftUI

struct MenuView: View {
    @ObservedObject var coordinator: Coordinator
    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        ForEach(coordinator.statusLines, id: \.self) { line in
            Text(line)
        }
        Text("Last action: \(coordinator.lastAction)")
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
        Menu("Saved layouts") {
            if coordinator.savedSetKeys.isEmpty {
                Text("No saved layouts")
            }
            ForEach(coordinator.savedSetKeys, id: \.self) { setKey in
                Menu(setKey) {
                    Button("Delete") { coordinator.deleteLayout(setKey: setKey) }
                }
            }
        }
        Divider()
        Button("Quit hdmi-defubar") { NSApp.terminate(nil) }
    }
}
