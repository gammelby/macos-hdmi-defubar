import Foundation
import UserNotifications
import os

/// Posts user notifications when running from a real app bundle; falls back
/// to logging only when run as a bare executable (swift run), where
/// UNUserNotificationCenter is unavailable.
final class Notifier {
    private let canNotify = Bundle.main.bundleIdentifier != nil
    private let log = Logger(subsystem: "dk.ulrik.hdmi-defubar", category: "notifier")

    func requestAuthorization() {
        guard canNotify else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, error in
            if let error {
                Logger(subsystem: "dk.ulrik.hdmi-defubar", category: "notifier")
                    .error("notification authorization failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Reports on the main queue whether the user has denied notifications.
    /// Unbundled runs report false; there is no permission to fix there.
    func authorizationDenied(_ completion: @escaping (Bool) -> Void) {
        guard canNotify else {
            completion(false)
            return
        }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                completion(settings.authorizationStatus == .denied)
            }
        }
    }

    func post(title: String, body: String) {
        log.notice("notify: \(title, privacy: .public): \(body, privacy: .public)")
        guard canNotify else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
