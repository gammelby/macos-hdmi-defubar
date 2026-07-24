import CoreGraphics
import Foundation

/// Debounces the burst of CoreGraphics reconfiguration callbacks around a
/// connect or disconnect into one settled notification on the main queue.
final class DisplayWatcher {
    var onSettled: () -> Void = {}
    private let settleSeconds: TimeInterval
    private var pending: DispatchWorkItem?

    init(settleSeconds: TimeInterval = 2.0) {
        self.settleSeconds = settleSeconds
    }

    func start() {
        let info = Unmanaged.passUnretained(self).toOpaque()
        CGDisplayRegisterReconfigurationCallback(displayReconfigurationCallback, info)
    }

    fileprivate func eventReceived() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onSettled() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + settleSeconds, execute: work)
    }
}

private func displayReconfigurationCallback(displayID: CGDirectDisplayID,
                                            flags: CGDisplayChangeSummaryFlags,
                                            userInfo: UnsafeMutableRawPointer?) {
    guard let userInfo else { return }
    let watcher = Unmanaged<DisplayWatcher>.fromOpaque(userInfo).takeUnretainedValue()
    DispatchQueue.main.async { watcher.eventReceived() }
}
