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
    private var iconName: String {
        switch request.kind {
        case .appleNotes: "note.text"
        case .contacts: "person.crop.circle"
        case .calendar: "calendar"
        case .accessibility: "accessibility"
        case .automation: "gearshape.2"
        default: "checklist"
        }
    }
    private var leadText: String {
        switch request.kind {
        case .appleNotes: "Find or save your Apple Notes without repeating your request."
        case .contacts: "Find the person you mean without leaving your request."
        case .calendar: "Check your calendar or add an event without leaving what you’re doing."
        case .accessibility: "To inspect the page, selection or window, or change a requested control, Sotto needs Accessibility access."
        case .automation: "To adjust this setting, Sotto needs Automation access in System Settings."
        default: "To complete your request, Sotto needs permission to access your reminders."
        }
    }
    private var bodyText: String {
        switch request.kind {
        case .appleNotes: "Allow Sotto to control Notes in the macOS prompt. Your original request resumes after access is checked. Saving or changing a note requires a separate review."
        case .contacts: "Allow Contacts access in the macOS prompt. Sotto will resume your original request after access is verified. Creating or changing a card requires a separate review."
        case .calendar: "macOS calls this full access. Sotto reads the dates you ask about and creates events you request. It never sends invitations, edits or deletes events. After access is allowed, your original request will continue."
        case .accessibility: "Enable Sotto in System Settings → Privacy & Security → Accessibility. Sotto checks automatically and will continue your request as soon as access is enabled."
        case .automation: "Allow Sotto under System Settings → Privacy & Security → Automation, then ask again."
        default: "macOS grants access to read and change your reminder lists. Sotto will continue your original request after access is verified."
        }
    }
    private var privacyNote: String {
        switch request.kind {
        case .appleNotes: "Requested note text may be processed by your selected intelligence. Sotto never reads the private Notes database and cannot edit locked, shared or attachment-bearing notes."
        case .contacts: "Names, phone numbers and email addresses returned for your request may be processed by your selected intelligence. Sotto does not send messages or email through Contacts."
        case .calendar: "Today and tomorrow’s basic calendar questions stay on this Mac. More flexible requests may share event titles and times with your selected intelligence provider."
        case .accessibility: "Sotto uses Accessibility for actions you request. Reading browser pages or selected text requires separate approval before content enters your conversation. It does not monitor your apps in the background."
        case .automation: "Sotto only sends commands to System Events or supported apps when you ask."
        default: "With a chosen AI provider, reminder details are shared with it to complete your request."
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Connect \(request.kind.title)", systemImage: iconName).font(.title2.weight(.semibold))
            Text(leadText)
            Text(bodyText)
                .font(.callout).foregroundStyle(.secondary)
            Text(privacyNote)
                .font(.caption).foregroundStyle(.secondary)
            if model.awaitingAccessibilityGrant && [.accessibility, .appleNotes].contains(request.kind) {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for \(request.kind.title) permission in System Settings…")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                Button("Cancel", role: .cancel) { model.resolveIntegration(request.id, allowed: false) }
                Spacer()
                if model.awaitingAccessibilityGrant && [.accessibility, .appleNotes].contains(request.kind) {
                    Button("Open \(request.kind.title) Settings…") { model.permissions.openSettings(request.kind) }
                    Button("Check now") { model.checkAccessibilityGrant(request.id) }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button(model.permissions.state(request.kind).canRequest ? "Allow access…" : "Open System Settings…") { Task { await model.connectIntegration(request.id) } }
                        .buttonStyle(.borderedProminent).disabled(model.permissions.requesting != nil)
                }
            }
        }.padding(28).frame(width: 440)
        .interactiveDismissDisabled()
    }
}
