import UserNotifications
import SottoIntegrations

/// Foreground timer alerts are distinct from optional ordinary task-completion
/// notifications. macOS still controls authorization, Focus and delivery.
public enum TimerNotificationPresentation {
    public static func options(for identifier: String) async -> UNNotificationPresentationOptions {
        await SottoTimerMaintenance.isTimerNotification(identifier) ? [.banner, .list, .sound] : []
    }
}
