import Foundation
import UserNotifications

/// Turns Daybloom reminders and timers into iPhone notifications, so they go off even when the app is closed.
enum Reminders {
    private static let center = UNUserNotificationCenter.current()
    private static let reminderPrefix = "reminder:"
    private static let timerID = "timer"

    /// Checks permission. Only asks the person when `ask` is true, which is when they just set a reminder or started a timer.
    private static func allowed(ask: Bool = true) async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            guard ask else { return false }
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        case .authorized, .provisional, .ephemeral:
            return true
        default:
            return false
        }
    }

    /// Replaces every scheduled reminder with this list. Each item is {id, title, body, at} where `at` is milliseconds since 1970.
    static func schedule(_ items: [[String: Any]], sound: Bool, ask: Bool) async {
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(reminderPrefix) })
        guard !items.isEmpty, await allowed(ask: ask) else { return }

        for item in items.prefix(60) {   // iOS keeps at most 64 waiting notifications; leave room for the timer
            guard let id = item["id"] as? String,
                  let title = item["title"] as? String,
                  let at = item["at"] as? Double else { continue }
            let date = Date(timeIntervalSince1970: at / 1000)
            guard date > Date() else { continue }

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = item["body"] as? String ?? ""
            if sound { content.sound = .default }
            try? await center.add(UNNotificationRequest(identifier: reminderPrefix + id, content: content, trigger: trigger(for: date)))
        }
    }

    /// Schedules the running timer, or clears it when `at` is nil.
    static func scheduleTimer(at date: Date?, body: String) async {
        center.removePendingNotificationRequests(withIdentifiers: [timerID])
        guard let date, date > Date(), await allowed() else { return }
        let content = UNMutableNotificationContent()
        content.title = "Timer done"
        content.body = body
        content.sound = .default
        try? await center.add(UNNotificationRequest(identifier: timerID, content: content, trigger: trigger(for: date)))
    }

    private static func trigger(for date: Date) -> UNCalendarNotificationTrigger {
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
    }
}
