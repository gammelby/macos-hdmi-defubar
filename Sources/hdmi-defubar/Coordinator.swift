import AppKit
import Combine
import Foundation
import DefubarCore
import os

/// Wires the watcher, engine, store, display system and notifier together.
/// Main-queue only.
final class Coordinator: ObservableObject {
    struct LayoutSummary: Identifiable {
        let id: String            // set key
        let layout: SavedLayout
        let isConnected: Bool
        var label: String { layout.displayLabel }
    }

    @Published var isPaused = false
    @Published var statusLines: [String] = []
    @Published var lastAction = "none yet"
    @Published var hasSavedLayoutForCurrentSet = false
    @Published var layoutSummaries: [LayoutSummary] = []
    @Published var notificationsDenied = false

    private var engine = Engine()
    private let system: DisplaySystem
    private let store: LayoutStore
    private let notifier = Notifier()
    private let watcher = DisplayWatcher()
    private var learnWork: DispatchWorkItem?
    private var selfCausedUntil = Date.distantPast
    private var nextRestoreIsInherited = false
    private let log = Logger(subsystem: "dk.ulrik.hdmi-defubar", category: "coordinator")

    private let learnSeconds: TimeInterval = 10.0
    private let selfCausedSeconds: TimeInterval = 5.0

    init(system: DisplaySystem, store: LayoutStore) {
        self.system = system
        self.store = store
    }

    func start() {
        notifier.requestAuthorization()
        if store.recoveredFromCorruption {
            notifier.post(title: "hdmi-defubar",
                          body: "The layout store was unreadable and has been moved aside; starting fresh.")
        }
        watcher.onSettled = { [weak self] sawAddOrRemove in
            self?.displaysSettled(sawAddOrRemove: sawAddOrRemove)
        }
        watcher.start()
        displaysSettled(sawAddOrRemove: false)
        refreshNotificationStatus()
    }

    func refreshNotificationStatus() {
        notifier.authorizationDenied { [weak self] denied in
            self?.notificationsDenied = denied
        }
    }

    func openNotificationSettings() {
        guard let bundleID = Bundle.main.bundleIdentifier,
              let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications?id=\(bundleID)") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Event handling

    private func displaysSettled(sawAddOrRemove: Bool) {
        let snapshot = system.currentSnapshot()
        let setKey = DisplayFingerprint.setKey(for: snapshot.map(\.fingerprint))
        let saved = store.layout(forSetKey: setKey)
        let selfCaused = Date() < selfCausedUntil
        // Unknown set containing externals: borrow each display's known mode
        // from other layouts (applied, never saved). Built-in-only sets skip
        // this so the engine's automatic MacBook entry still happens.
        var effectiveSaved = saved
        nextRestoreIsInherited = false
        if saved == nil, snapshot.contains(where: { !$0.fingerprint.isBuiltin }),
           let synthetic = ModeInheritance.syntheticLayout(for: snapshot,
                                                           from: store.allLayouts().map(\.layout)) {
            effectiveSaved = synthetic
            nextRestoreIsInherited = true
        }
        log.info("settled: setKey=\(setKey, privacy: .public) selfCaused=\(selfCaused) hasSaved=\(saved != nil) inherited=\(self.nextRestoreIsInherited) sawAddOrRemove=\(sawAddOrRemove)")
        let effects = engine.displaysSettled(snapshot, selfCaused: selfCaused, savedLayout: effectiveSaved,
                                             sawDisplaysAddedOrRemoved: sawAddOrRemove)
        updateStatus(snapshot: snapshot, saved: saved)
        refreshNotificationStatus()
        if isPaused {
            cancelLearnTimer()
            return
        }
        run(effects)
    }

    private func run(_ effects: [EngineEffect]) {
        for effect in effects {
            switch effect {
            case .cancelLearnTimer:
                cancelLearnTimer()
            case .startLearnTimer:
                startLearnTimer()
            case .saveLayout(let layout):
                store.save(layout)
                let setKey = DisplayFingerprint.setKey(for: layout.displays.map(\.fingerprint))
                let label = store.layout(forSetKey: setKey)?.displayLabel ?? layout.displayLabel
                lastAction = "Learned layout: \(label)"
                log.info("learned layout for \(setKey, privacy: .public)")
                notifier.post(title: "hdmi-defubar", body: "Learned layout \(label).")
                refreshDerivedState()
            case .applyLayout(let layout):
                restore(layout, inherited: nextRestoreIsInherited)
            }
        }
    }

    private func restore(_ layout: SavedLayout, inherited: Bool = false) {
        selfCausedUntil = Date().addingTimeInterval(selfCausedSeconds)
        let result = system.apply(layout)
        if let failure = result.failureMessage {
            lastAction = "Restore failed"
            notifier.post(title: "hdmi-defubar", body: "Could not restore the saved layout: \(failure).")
            return
        }
        if result.applied.isEmpty {
            // Nothing needed changing; stay silent.
            lastAction = "Layout already matched"
            log.info("restore was a no-op")
            return
        }
        let names = result.applied.joined(separator: ", ")
        var body: String
        if inherited {
            lastAction = "Applied known display modes"
            body = "New monitor combination; applied the known resolution for \(names). Arrange the displays once to save this layout."
        } else {
            lastAction = "Restored saved layout"
            body = "\(names) came up with a changed configuration; restored your saved layout."
        }
        if !result.substitutions.isEmpty {
            body += " Closest available mode was used for \(result.substitutions.joined(separator: ", "))."
        }
        notifier.post(title: "hdmi-defubar", body: body)
        refreshDerivedState()
    }

    private func startLearnTimer() {
        learnWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let snapshot = self.system.currentSnapshot()
            self.run(self.engine.learnTimerFired(snapshot))
        }
        learnWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + learnSeconds, execute: work)
    }

    private func cancelLearnTimer() {
        learnWork?.cancel()
        learnWork = nil
    }

    // MARK: - Menu actions

    func saveCurrentLayout() {
        store.save(SavedLayout(from: system.currentSnapshot()))
        lastAction = "Saved current layout"
        refreshDerivedState()
    }

    func restoreSavedLayout() {
        let snapshot = system.currentSnapshot()
        let setKey = DisplayFingerprint.setKey(for: snapshot.map(\.fingerprint))
        guard let saved = store.layout(forSetKey: setKey) else { return }
        restore(saved)
    }

    /// Restores a specific layout; only meaningful for the connected set.
    func restoreLayout(setKey: String) {
        let snapshot = system.currentSnapshot()
        guard setKey == DisplayFingerprint.setKey(for: snapshot.map(\.fingerprint)),
              let saved = store.layout(forSetKey: setKey) else { return }
        restore(saved)
    }

    func deleteLayout(setKey: String) {
        store.delete(forSetKey: setKey)
        refreshDerivedState()
    }

    func renameLayout(setKey: String, to name: String) {
        store.rename(setKey: setKey, to: name)
        refreshDerivedState()
    }

    // MARK: - Status

    private func updateStatus(snapshot: [DisplaySnapshot], saved: SavedLayout?) {
        statusLines = snapshot.map { display in
            "\(display.name): \(display.pointWidth)x\(display.pointHeight) @ \(Int(display.refresh.rounded())) Hz"
        }
        hasSavedLayoutForCurrentSet = saved != nil
        rebuildSummaries(currentSetKey: DisplayFingerprint.setKey(for: snapshot.map(\.fingerprint)))
    }

    private func refreshDerivedState() {
        let snapshot = system.currentSnapshot()
        let setKey = DisplayFingerprint.setKey(for: snapshot.map(\.fingerprint))
        hasSavedLayoutForCurrentSet = store.layout(forSetKey: setKey) != nil
        rebuildSummaries(currentSetKey: setKey)
    }

    private func rebuildSummaries(currentSetKey: String) {
        layoutSummaries = store.allLayouts()
            .map { LayoutSummary(id: $0.setKey, layout: $0.layout,
                                 isConnected: $0.setKey == currentSetKey) }
            .sorted {
                if $0.isConnected != $1.isConnected { return $0.isConnected }
                return $0.label < $1.label
            }
    }
}
