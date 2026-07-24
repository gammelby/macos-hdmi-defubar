import Combine
import Foundation
import DefubarCore
import os

/// Wires the watcher, engine, store, display system and notifier together.
/// Main-queue only.
final class Coordinator: ObservableObject {
    @Published var isPaused = false
    @Published var statusLines: [String] = []
    @Published var lastAction = "none yet"
    @Published var hasSavedLayoutForCurrentSet = false
    @Published var savedSetKeys: [String] = []

    private var engine = Engine()
    private let system: DisplaySystem
    private let store: LayoutStore
    private let notifier = Notifier()
    private let watcher = DisplayWatcher()
    private var learnWork: DispatchWorkItem?
    private var selfCausedUntil = Date.distantPast
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
    }

    // MARK: - Event handling

    private func displaysSettled(sawAddOrRemove: Bool) {
        let snapshot = system.currentSnapshot()
        let setKey = DisplayFingerprint.setKey(for: snapshot.map(\.fingerprint))
        let saved = store.layout(forSetKey: setKey)
        let selfCaused = Date() < selfCausedUntil
        log.info("settled: setKey=\(setKey, privacy: .public) selfCaused=\(selfCaused) hasSaved=\(saved != nil) sawAddOrRemove=\(sawAddOrRemove)")
        let effects = engine.displaysSettled(snapshot, selfCaused: selfCaused, savedLayout: saved,
                                             sawDisplaysAddedOrRemoved: sawAddOrRemove)
        updateStatus(snapshot: snapshot, saved: saved)
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
                lastAction = "Learned adjusted layout"
                log.info("learned layout for \(DisplayFingerprint.setKey(for: layout.displays.map(\.fingerprint)), privacy: .public)")
                refreshDerivedState()
            case .applyLayout(let layout):
                restore(layout)
            }
        }
    }

    private func restore(_ layout: SavedLayout) {
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
        lastAction = "Restored saved layout"
        var body = "\(result.applied.joined(separator: ", ")) came up with a changed configuration; restored your saved layout."
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

    func deleteLayout(setKey: String) {
        store.delete(forSetKey: setKey)
        refreshDerivedState()
    }

    // MARK: - Status

    private func updateStatus(snapshot: [DisplaySnapshot], saved: SavedLayout?) {
        statusLines = snapshot.map { display in
            "\(display.name): \(display.pointWidth)x\(display.pointHeight) @ \(Int(display.refresh.rounded())) Hz"
        }
        hasSavedLayoutForCurrentSet = saved != nil
        savedSetKeys = store.allSetKeys()
    }

    private func refreshDerivedState() {
        let snapshot = system.currentSnapshot()
        let setKey = DisplayFingerprint.setKey(for: snapshot.map(\.fingerprint))
        hasSavedLayoutForCurrentSet = store.layout(forSetKey: setKey) != nil
        savedSetKeys = store.allSetKeys()
    }
}
