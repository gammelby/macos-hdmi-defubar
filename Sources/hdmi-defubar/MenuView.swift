import AppKit
import SwiftUI

struct MenuView: View {
    @ObservedObject var coordinator: Coordinator
    @Environment(\.openWindow) private var openWindow
    @State private var launchAtLogin = LoginItem.isEnabled

    private var windowActionsUsable: Bool {
        coordinator.windowRestoreEnabled && coordinator.windowPermissionGranted
    }

    var body: some View {
        ForEach(coordinator.statusLines, id: \.self) { line in
            Text(line)
        }
        Text("Last action: \(coordinator.lastAction)")
            .onAppear {
                coordinator.refreshNotificationStatus()
                coordinator.refreshWindowPermission()
            }
        if coordinator.notificationsDenied {
            Button("Allow notifications...") { coordinator.openNotificationSettings() }
        }
        Divider()
        Button("Save current layout") { coordinator.saveCurrentLayout() }
        Button("Save current as new variant") { coordinator.saveCurrentAsNewVariant() }
        Button("Restore saved layout") { coordinator.restoreSavedLayout() }
            .disabled(!coordinator.hasSavedLayoutForCurrentSet)
        Divider()
        ForEach(coordinator.layoutSummaries) { summary in
            if summary.variants.count > 1 {
                Menu {
                    ForEach(summary.variants) { variant in
                        Button {
                            coordinator.useVariant(setKey: summary.id, variantID: variant.id)
                        } label: {
                            if variant.isActive {
                                Label(variant.label, systemImage: "checkmark")
                            } else {
                                Text(variant.label)
                            }
                        }
                        .disabled(!summary.isConnected)
                    }
                } label: {
                    Text(summary.isConnected ? "\(summary.label) ✓" : summary.label)
                }
            } else {
                Button {
                    coordinator.restoreLayout(setKey: summary.id)
                } label: {
                    if summary.isConnected {
                        Label(summary.label, systemImage: "checkmark")
                    } else {
                        Text(summary.label)
                    }
                }
                .disabled(!summary.isConnected)
            }
        }
        Button("Manage layouts...") {
            openWindow(id: "layouts")
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        Toggle("Remember window positions", isOn: $coordinator.windowRestoreEnabled)
        if coordinator.windowRestoreEnabled && !coordinator.windowPermissionGranted {
            Button("Grant Accessibility access...") { coordinator.requestWindowPermission() }
        }
        Button("Remember windows now") { coordinator.rememberWindowsNow() }
            .disabled(!windowActionsUsable)
        Button("Put windows back") { coordinator.restoreWindowsNow() }
            .disabled(!windowActionsUsable)
        Divider()
        Toggle("Pause automatic handling", isOn: $coordinator.isPaused)
        Toggle("Launch at login", isOn: Binding(
            get: { launchAtLogin },
            set: { newValue in
                LoginItem.setEnabled(newValue)
                launchAtLogin = LoginItem.isEnabled
            }))
            .disabled(!LoginItem.isAvailable)
        Divider()
        Button("Quit HDMI Defubar") { NSApp.terminate(nil) }
    }
}
