import AppKit
import Combine
import Foundation
import DefubarCore
import os

/// Wires the watcher, engine, stores, display system, window system and
/// notifier together. Main-queue only.
final class Coordinator: ObservableObject {
    /// One resolution combination of a monitor set, as the UI sees it.
    struct VariantSummary: Identifiable {
        let id: String                // variant id
        let setKey: String
        let variant: LayoutVariant
        let isActive: Bool
        let windowCount: Int
        let windowsCapturedAt: Date?
        var label: String { variant.label }
        var layout: SavedLayout { variant.layout }
    }

    /// One monitor set, as the UI sees it.
    struct LayoutSummary: Identifiable {
        let id: String                // set key
        let layoutSet: LayoutSet
        let isConnected: Bool
        let variants: [VariantSummary]
        var label: String { layoutSet.displayLabel }
        var activeVariant: VariantSummary? { variants.first { $0.isActive } }
    }

    /// A restore notification held back until the window restore has run, so
    /// one reconnect produces one notification.
    private struct PendingNotice {
        var title: String
        var body: String
    }

    @Published var isPaused = false
    @Published var statusLines: [String] = []
    @Published var lastAction = "none yet"
    @Published var hasSavedLayoutForCurrentSet = false
    @Published var layoutSummaries: [LayoutSummary] = []
    @Published var notificationsDenied = false
    @Published var windowPermissionGranted = false
    @Published var windowRestoreEnabled: Bool {
        didSet {
            UserDefaults.standard.set(windowRestoreEnabled, forKey: Self.windowRestoreDefaultsKey)
            if windowRestoreEnabled && !windowSystem.isPermitted {
                windowSystem.requestPermission()
            }
            refreshWindowPermission()
        }
    }

    private static let windowRestoreDefaultsKey = "windowRestoreEnabled"

    private var engine = Engine()
    private let system: DisplaySystem
    private let store: LayoutStore
    private let windowStore: WindowStore
    private let windowSystem: WindowSystem
    private let notifier = Notifier()
    private let watcher = DisplayWatcher()
    private var learnWork: DispatchWorkItem?
    private var restoreFinishWork: DispatchWorkItem?
    private var captureTimer: Timer?
    private var pendingNotice: PendingNotice?
    private var selfCausedUntil = Date.distantPast
    private var lastSettleAt = Date.distantPast
    private var nextRestoreIsInherited = false
    private let log = Logger(subsystem: "dk.ulrik.hdmi-defubar", category: "coordinator")

    private let learnSeconds: TimeInterval = 5.0
    private let selfCausedSeconds: TimeInterval = 5.0
    /// How long after the display transaction windows are put back. Long
    /// enough for WindowServer to finish its own shuffling first.
    private let windowRestoreDelay: TimeInterval = 1.5
    /// How often the current arrangement is remembered.
    private let captureInterval: TimeInterval = 20.0
    /// Quiet period after a display change during which nothing is captured,
    /// so a post-unplug pile-up cannot overwrite a good arrangement before the
    /// restore has run.
    private let captureQuietSeconds: TimeInterval = 8.0

    init(system: DisplaySystem, store: LayoutStore, windowStore: WindowStore,
         windowSystem: WindowSystem) {
        self.system = system
        self.store = store
        self.windowStore = windowStore
        self.windowSystem = windowSystem
        windowRestoreEnabled = UserDefaults.standard.bool(forKey: Self.windowRestoreDefaultsKey)
    }

    func start() {
        notifier.requestAuthorization()
        if store.recoveredFromCorruption {
            notifier.post(title: "Layout store reset",
                          body: "The layout store was unreadable and has been moved aside; starting fresh.")
        }
        if windowStore.recoveredFromCorruption {
            notifier.post(title: "Window memory reset",
                          body: "The remembered window positions were unreadable and have been moved aside; starting fresh.")
        }
        watcher.onSettled = { [weak self] sawAddOrRemove in
            self?.displaysSettled(sawAddOrRemove: sawAddOrRemove)
        }
        watcher.start()
        displaysSettled(sawAddOrRemove: false)
        refreshNotificationStatus()
        refreshWindowPermission()
        startCaptureTimer()
    }

    func refreshNotificationStatus() {
        notifier.authorizationDenied { [weak self] denied in
            self?.notificationsDenied = denied
        }
    }

    func refreshWindowPermission() {
        windowPermissionGranted = windowSystem.isPermitted
    }

    func openNotificationSettings() {
        guard let bundleID = Bundle.main.bundleIdentifier,
              let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications?id=\(bundleID)") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// Prompts for the Accessibility permission and opens the pane, since the
    /// prompt alone is easy to miss and cannot be re-shown.
    func requestWindowPermission() {
        windowSystem.requestPermission()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        refreshWindowPermission()
    }

    // MARK: - Event handling

    private func displaysSettled(sawAddOrRemove: Bool) {
        lastSettleAt = Date()
        let snapshot = system.currentSnapshot()
        let setKey = DisplayFingerprint.setKey(for: snapshot.map(\.fingerprint))
        let saved = store.activeLayout(forSetKey: setKey)
        let selfCaused = Date() < selfCausedUntil
        // Unknown set containing externals: borrow each display's known mode
        // from other layouts (applied, never saved). Built-in-only sets skip
        // this so the engine's automatic MacBook entry still happens.
        var effectiveSaved = saved
        nextRestoreIsInherited = false
        if saved == nil, snapshot.contains(where: { !$0.fingerprint.isBuiltin }),
           let synthetic = ModeInheritance.syntheticLayout(for: snapshot,
                                                           from: store.allLayouts()) {
            effectiveSaved = synthetic
            nextRestoreIsInherited = true
        }
        log.info("settled: setKey=\(setKey, privacy: .public) selfCaused=\(selfCaused) hasSaved=\(saved != nil) inherited=\(self.nextRestoreIsInherited) sawAddOrRemove=\(sawAddOrRemove)")
        let effects = engine.displaysSettled(snapshot, selfCaused: selfCaused, savedLayout: effectiveSaved,
                                             sawDisplaysAddedOrRemoved: sawAddOrRemove)
        updateStatus(snapshot: snapshot, hasSaved: saved != nil)
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
                learn(layout)
            case .applyLayout(let layout):
                restore(layout, inherited: nextRestoreIsInherited)
            case .restoreWindows:
                scheduleRestoreFinish()
            }
        }
    }

    private func learn(_ layout: SavedLayout) {
        let result = store.learn(layout)
        let label = store.set(forSetKey: result.setKey)?.displayLabel ?? layout.derivedName
        if result.isNewVariant && !result.isNewSet {
            let variant = store.set(forSetKey: result.setKey)?.variant(withID: result.variantID)
            let modes = variant?.label ?? layout.derivedVariantName
            lastAction = "Learned new variant: \(modes)"
            log.info("learned new variant for \(result.setKey, privacy: .public)")
            notifier.post(title: "Resolution variant learned",
                          body: "Remembered \(modes) as a new variant of \(label).")
        } else {
            lastAction = "Learned layout: \(label)"
            log.info("learned layout for \(result.setKey, privacy: .public)")
            notifier.post(title: "Layout learned", body: "Learned layout \(label).")
        }
        refreshDerivedState()
    }

    private func restore(_ layout: SavedLayout, inherited: Bool = false) {
        selfCausedUntil = Date().addingTimeInterval(selfCausedSeconds)
        let result = system.apply(layout)
        if let failure = result.failureMessage {
            lastAction = "Restore failed"
            notifier.post(title: "Restore failed", body: "Could not restore the saved layout: \(failure).")
            return
        }
        if result.applied.isEmpty {
            // Nothing needed changing; the windows may still be wrong, so the
            // restore finish still runs, it just has nothing to announce.
            lastAction = "Layout already matched"
            log.info("restore was a no-op")
            scheduleRestoreFinish()
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
        pendingNotice = PendingNotice(title: inherited ? "Applied known modes" : "Layout restored",
                                      body: body)
        scheduleRestoreFinish()
        refreshDerivedState()
    }

    /// Runs the window restore once the displays have stopped moving, then
    /// posts the single notification for the whole reconnect.
    private func scheduleRestoreFinish() {
        guard restoreFinishWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.restoreFinishWork = nil
            self.finishRestore()
        }
        restoreFinishWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + windowRestoreDelay, execute: work)
    }

    private func finishRestore() {
        let notice = pendingNotice
        pendingNotice = nil
        let windows = restoreWindows()
        var body = notice?.body
        if let windows, windows.moved > 0 {
            let sentence = "Put \(windows.moved) \(windows.moved == 1 ? "window" : "windows") back."
            body = body.map { "\($0) \(sentence)" } ?? sentence
            lastAction = notice == nil ? "Restored windows" : lastAction
        }
        if let windows, !windows.failed.isEmpty {
            let count = windows.failed.count
            body = (body ?? "") + " \(count) \(count == 1 ? "window" : "windows") would not move."
        }
        guard let body, !body.isEmpty else { return }
        notifier.post(title: notice?.title ?? "Windows restored", body: body)
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

    // MARK: - Windows

    private func startCaptureTimer() {
        captureTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: captureInterval, repeats: true) { [weak self] _ in
            self?.captureWindowsIfStable()
        }
        timer.tolerance = captureInterval / 4
        captureTimer = timer
    }

    private func captureWindowsIfStable() {
        guard windowRestoreEnabled, !isPaused, windowSystem.isPermitted else { return }
        let now = Date()
        guard now >= lastSettleAt.addingTimeInterval(captureQuietSeconds),
              now >= selfCausedUntil else { return }
        captureWindows()
    }

    /// Remembers the current arrangement for the active variant of the
    /// connected set. Returns how many windows were seen, or nil when there is
    /// no variant to attach them to.
    @discardableResult
    private func captureWindows() -> Int? {
        let snapshot = system.currentSnapshot()
        let setKey = DisplayFingerprint.setKey(for: snapshot.map(\.fingerprint))
        guard let variantID = store.set(forSetKey: setKey)?.activeVariant?.id else { return nil }
        let windows = WindowPlacement.capture(windowSystem.currentWindows(), displays: snapshot)
        if windowStore.save(windows, forVariantID: variantID) {
            log.info("remembered \(windows.count) windows for \(setKey, privacy: .public)")
            refreshDerivedState()
        }
        return windows.count
    }

    private func restoreWindows() -> WindowRestoreResult? {
        guard windowRestoreEnabled, windowSystem.isPermitted else { return nil }
        let snapshot = system.currentSnapshot()
        let setKey = DisplayFingerprint.setKey(for: snapshot.map(\.fingerprint))
        guard let variantID = store.set(forSetKey: setKey)?.activeVariant?.id,
              let remembered = windowStore.snapshot(forVariantID: variantID),
              !remembered.windows.isEmpty else { return nil }
        let moves = WindowPlacement.plan(saved: remembered.windows,
                                         live: windowSystem.currentWindows(),
                                         displays: snapshot)
        guard !moves.isEmpty else { return nil }
        let result = windowSystem.apply(moves)
        log.info("restored \(result.moved) windows, \(result.failed.count) refused")
        return result
    }

    // MARK: - Menu actions

    func saveCurrentLayout() {
        let result = store.learn(SavedLayout(from: system.currentSnapshot()))
        lastAction = result.isNewVariant ? "Saved as new variant" : "Saved current layout"
        captureWindows()
        refreshDerivedState()
    }

    /// Records the current state as an extra variant even when its resolutions
    /// are already known, for deliberately keeping two arrangements of the
    /// same modes.
    func saveCurrentAsNewVariant() {
        store.saveAsNewVariant(SavedLayout(from: system.currentSnapshot()))
        lastAction = "Saved as new variant"
        captureWindows()
        refreshDerivedState()
    }

    func restoreSavedLayout() {
        let snapshot = system.currentSnapshot()
        let setKey = DisplayFingerprint.setKey(for: snapshot.map(\.fingerprint))
        guard let saved = store.activeLayout(forSetKey: setKey) else { return }
        restore(saved)
    }

    /// Restores a specific layout; only meaningful for the connected set.
    func restoreLayout(setKey: String) {
        let snapshot = system.currentSnapshot()
        guard setKey == DisplayFingerprint.setKey(for: snapshot.map(\.fingerprint)),
              let saved = store.activeLayout(forSetKey: setKey) else { return }
        restore(saved)
    }

    /// Makes a variant active and applies it, which is what picking a
    /// resolution combination from the menu means.
    func useVariant(setKey: String, variantID: String) {
        let snapshot = system.currentSnapshot()
        guard setKey == DisplayFingerprint.setKey(for: snapshot.map(\.fingerprint)) else { return }
        store.setActiveVariant(setKey: setKey, variantID: variantID)
        refreshDerivedState()
        guard let layout = store.set(forSetKey: setKey)?.variant(withID: variantID)?.layout else {
            return
        }
        restore(layout)
    }

    func deleteLayout(setKey: String) {
        store.deleteSet(forSetKey: setKey)
        windowStore.prune(keeping: store.allVariantIDs())
        refreshDerivedState()
    }

    func deleteVariant(setKey: String, variantID: String) {
        store.deleteVariant(setKey: setKey, variantID: variantID)
        windowStore.prune(keeping: store.allVariantIDs())
        refreshDerivedState()
    }

    func renameLayout(setKey: String, to name: String) {
        store.renameSet(setKey: setKey, to: name)
        refreshDerivedState()
    }

    func renameVariant(setKey: String, variantID: String, to name: String) {
        store.renameVariant(setKey: setKey, variantID: variantID, to: name)
        refreshDerivedState()
    }

    func rememberWindowsNow() {
        guard windowSystem.isPermitted else {
            requestWindowPermission()
            return
        }
        guard let count = captureWindows() else {
            lastAction = "No layout to attach windows to"
            return
        }
        lastAction = "Remembered \(count) \(count == 1 ? "window" : "windows")"
        refreshDerivedState()
    }

    func restoreWindowsNow() {
        guard windowSystem.isPermitted else {
            requestWindowPermission()
            return
        }
        guard let result = restoreWindows() else {
            lastAction = "Windows already in place"
            return
        }
        lastAction = "Put \(result.moved) \(result.moved == 1 ? "window" : "windows") back"
    }

    func forgetWindows(variantID: String) {
        windowStore.delete(forVariantID: variantID)
        refreshDerivedState()
    }

    // MARK: - Status

    private func updateStatus(snapshot: [DisplaySnapshot], hasSaved: Bool) {
        statusLines = snapshot.map { display in
            "\(display.name): \(display.pointWidth)x\(display.pointHeight) @ \(Int(display.refresh.rounded())) Hz"
        }
        hasSavedLayoutForCurrentSet = hasSaved
        rebuildSummaries(currentSetKey: DisplayFingerprint.setKey(for: snapshot.map(\.fingerprint)))
    }

    private func refreshDerivedState() {
        let snapshot = system.currentSnapshot()
        let setKey = DisplayFingerprint.setKey(for: snapshot.map(\.fingerprint))
        hasSavedLayoutForCurrentSet = store.set(forSetKey: setKey) != nil
        rebuildSummaries(currentSetKey: setKey)
    }

    private func rebuildSummaries(currentSetKey: String) {
        layoutSummaries = store.allSets()
            .map { setKey, set in
                let variants = set.variants.map { variant in
                    let windows = windowStore.snapshot(forVariantID: variant.id)
                    return VariantSummary(id: variant.id, setKey: setKey, variant: variant,
                                          isActive: variant.id == set.activeVariantID,
                                          windowCount: windows?.windows.count ?? 0,
                                          windowsCapturedAt: windows?.capturedAt)
                }
                return LayoutSummary(id: setKey, layoutSet: set,
                                     isConnected: setKey == currentSetKey, variants: variants)
            }
            .sorted {
                if $0.isConnected != $1.isConnected { return $0.isConnected }
                return $0.label < $1.label
            }
    }
}
