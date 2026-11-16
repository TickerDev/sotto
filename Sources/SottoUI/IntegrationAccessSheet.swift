import SwiftUI

/// The original intent stays in the suspended runtime task, only in memory.
/// Cancellation, expiry, or revocation prevents it from resuming.
public struct IntegrationAccessRequest: Identifiable, Sendable {
    public let id = UUID()
    public let kind: PermissionKind
    public init(kind: PermissionKind = .reminders) { self.kind = kind }
}
struct IntegrationAccessSheet: View {
    @Bindable var model: AppModel
    let request: IntegrationAccessRequest
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Connect \(request.kind.title)", systemImage: request.kind == .calendar ? "calendar" : "checklist").font(.title2.weight(.semibold))
            Text(request.kind == .calendar ? "See what’s coming up without leaving what you’re doing." : "To complete your request, Sotto needs permission to access your reminders.")
            Text(request.kind == .calendar ? "macOS calls this full access. Sotto only reads events for the dates you ask about; it doesn’t change them. After you allow access, your original request will continue." : "macOS grants access to read and change your reminder lists. Sotto will continue your original request after access is verified.")
                .font(.callout).foregroundStyle(.secondary)
            Text(request.kind == .calendar ? "Today and tomorrow’s basic calendar questions stay on this Mac. More flexible requests may share event titles and times with your selected intelligence provider." : "With a chosen AI provider, reminder details are shared with it to complete your request.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Cancel", role: .cancel) { model.resolveIntegration(request.id, allowed: false) }
                Spacer()
                Button(model.permissions.state(request.kind).canRequest ? "Allow access…" : "Open System Settings…") { Task { await model.connectIntegration(request.id) } }
                    .buttonStyle(.borderedProminent).disabled(model.permissions.requesting != nil)
            }
        }.padding(28).frame(width: 440)
        .interactiveDismissDisabled()
    }
}
