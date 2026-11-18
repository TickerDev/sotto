import Foundation
import UserNotifications
import SottoTools

enum TimerAlertPermission: Sendable {
    case alerts, quiet, denied, notRequested
    var canSchedule: Bool { self == .alerts || self == .quiet }
}
struct PendingTimerAlert: Sendable {
    let id: String
    let date: Date?
}
protocol TimerNotifications: Sendable {
    func checkAvailability() throws
    func permission(request: Bool) async throws -> TimerAlertPermission
    func pending() async -> [PendingTimerAlert]
    func schedule(_ timer: SottoTimer, remaining: TimeInterval) async throws
    /// Remove pending and delivered alerts, then verify absence from both lists.
    func remove(_ id: String) async -> Bool
}
extension TimerNotifications { func checkAvailability() throws {} }
struct NativeTimerNotifications: TimerNotifications {
    private var bundled: Bool { Bundle.main.bundleURL.pathExtension == "app" }
    func checkAvailability() throws {
        guard bundled else { throw ToolError.unavailable("Timers must be started from the Sotto app") }
    }
    func permission(request: Bool) async throws -> TimerAlertPermission {
        guard bundled else { throw ToolError.unavailable("Timer notifications require the Sotto app, not a command-line runner") }
        let center = UNUserNotificationCenter.current()
        var settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined, request {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
            settings = await center.notificationSettings()
        }
        switch settings.authorizationStatus {
        case .authorized: return settings.alertSetting == .enabled ? .alerts : .quiet
        case .provisional, .ephemeral: return .quiet
        case .notDetermined: return .notRequested
        default: return .denied
        }
    }
    func pending() async -> [PendingTimerAlert] {
        guard bundled else { return [] }
        return await UNUserNotificationCenter.current().pendingNotificationRequests().map {
            // Absolute calendar triggers permit reliable deadline read-back.
            // Legacy interval requests are replaced once at their saved deadline.
            let trigger = $0.trigger as? UNCalendarNotificationTrigger
            return .init(id: $0.identifier, date: trigger?.repeats == false ? trigger?.nextTriggerDate() : nil)
        }
    }
    func schedule(_ timer: SottoTimer, remaining: TimeInterval) async throws {
        guard bundled else { throw ToolError.unavailable("Start timers from the Sotto app") }
        try Task.checkCancellation()
        guard remaining > 0 else { throw ToolError.unavailable("This timer's deadline has already passed") }
        try await UNUserNotificationCenter.current().add(Self.request(timer))
    }
    static func request(_ timer: SottoTimer) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = timer.name; content.body = "Your timer has finished."; content.sound = .default
        content.userInfo = ["sotto_timer_id": timer.id]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = Date(timeIntervalSince1970: timer.deadline.timeIntervalSince1970.rounded(.up))
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        components.calendar = calendar; components.timeZone = calendar.timeZone
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: timer.id, content: content, trigger: trigger)
    }
    func remove(_ id: String) async -> Bool {
        guard bundled else { return true } // No notification center belongs to a CLI fixture.
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.removeDeliveredNotifications(withIdentifiers: [id])
        let pending = await center.pendingNotificationRequests()
        let delivered = await center.deliveredNotifications()
        return !pending.contains { $0.identifier == id } && !delivered.contains { $0.request.identifier == id }
    }
}
