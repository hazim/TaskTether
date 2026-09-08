//
//  SyncFailureNotifier.swift
//  TaskTether
//

import Foundation
import UserNotifications

// MARK: - SyncFailureNotifier

// Surfaces a macOS notification when sync fails repeatedly, rather than
// letting it stop silently. Fires on the 3rd consecutive failure, then
// every 10th failure thereafter so a permanently broken setup reminds the
// user occasionally without spamming them.
final class SyncFailureNotifier {

    private static let notificationIdentifier = "tasktether.syncFailed"
    private static let threshold              = 3
    private static let repeatInterval         = 10

    private var consecutiveFailures = 0

    // MARK: - Recording

    func recordFailure(_ message: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }

        consecutiveFailures += 1
        guard shouldNotify(atFailureCount: consecutiveFailures) else { return }

        requestAuthorizationIfNeeded { [weak self] granted in
            guard granted else { return }
            // getNotificationSettings/requestAuthorization completion handlers run on
            // a background queue, but this class is MainActor-isolated — hop back.
            Task { @MainActor in
                self?.postNotification(errorMessage: message)
            }
        }
    }

    func recordSuccess() {
        consecutiveFailures = 0
    }

    // MARK: - Threshold

    private func shouldNotify(atFailureCount count: Int) -> Bool {
        if count == Self.threshold { return true }
        guard count > Self.threshold else { return false }
        return (count - Self.threshold) % Self.repeatInterval == 0
    }

    // MARK: - Authorization

    private func requestAuthorizationIfNeeded(completion: @escaping (Bool) -> Void) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                completion(true)
            case .notDetermined:
                center.requestAuthorization(options: [.alert]) { granted, _ in
                    completion(granted)
                }
            default:
                completion(false)
            }
        }
    }

    // MARK: - Posting

    private func postNotification(errorMessage: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "notification.syncFailed.title")
        content.body  = String(
            format: String(localized: "notification.syncFailed.body"),
            errorMessage
        )

        let request = UNNotificationRequest(
            identifier: Self.notificationIdentifier,
            content:    content,
            trigger:    nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            #if DEBUG
            if let error {
                print("SyncFailureNotifier: failed to post notification: \(error.localizedDescription)")
            }
            #endif
        }
    }
}
