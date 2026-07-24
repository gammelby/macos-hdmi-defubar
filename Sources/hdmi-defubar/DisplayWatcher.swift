import CoreGraphics
import Foundation

/// Debounces the burst of CoreGraphics reconfiguration callbacks around a
/// connect or disconnect into one settled notification on the main queue.
/// Add/remove flags are accumulated across the burst so a fast unplug/replug
/// that ends with the same displays online is still reported as a topology
/// change.
final class DisplayWatcher {
    /// Called on the main queue once events settle. The parameter is true
    /// when any display was added or removed during the burst.
    var onSettled: (Bool) -> Void = { _ in }
    private let settleSeconds: TimeInterval
    private var pending: DispatchWorkItem?
    private var sawAddOrRemove = false

    init(settleSeconds: TimeInterval = 2.0) {
        self.settleSeconds = settleSeconds
    }

    func start() {
        let info = Unmanaged.passUnretained(self).toOpaque()
        CGDisplayRegisterReconfigurationCallback(displayReconfigurationCallback, info)
    }

    fileprivate func eventReceived(flags: CGDisplayChangeSummaryFlags) {
        if flags.contains(.addFlag) || flags.contains(.removeFlag) {
            sawAddOrRemove = true
        }
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let saw = self.sawAddOrRemove
            self.sawAddOrRemove = false
            self.onSettled(saw)
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + settleSeconds, execute: work)
    }
}

private func displayReconfigurationCallback(displayID: CGDirectDisplayID,
                                            flags: CGDisplayChangeSummaryFlags,
                                            userInfo: UnsafeMutableRawPointer?) {
    guard let userInfo else { return }
    let watcher = Unmanaged<DisplayWatcher>.fromOpaque(userInfo).takeUnretainedValue()
    DispatchQueue.main.async { watcher.eventReceived(flags: flags) }
}
