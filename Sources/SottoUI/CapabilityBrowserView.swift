import SwiftUI
import AppKit
import EventKit
import UserNotifications
import SottoTools
import SottoIntegrations

struct CapabilityBrowserView: View {
    @Bindable var model: AppModel
    private let groups: [(String, [String], String)] = [
        ("Files and Documents", ["files.", "aliases."], "“Find my résumé.” · “Find the PDF I downloaded yesterday.”"),
        ("Apps and Windows", ["apps.", "windows."], "“Open Safari.” · “Arrange my windows.”"),
        ("Apple Notes", ["appleNotes."], "“Find my Apple research note.” · “Create an Apple Note with this idea.”"),
        ("Sotto Notes", ["notes."], "“Create a Sotto note with this idea.” · “Find my Sotto research note.”"),
        ("Contacts", ["contacts."], "“What’s Alex’s phone number?” · “Add this person to my contacts.”"),
        ("Calendar and Reminders", ["calendar.", "reminders."], "“What’s on my calendar?” · “Remind me to water the plants tomorrow.”"),
        ("Timers", ["timers."], "“Set a ten-minute timer.” · “Show my active timers.”"),
        ("Music and Audio", ["media.", "audio."], "“Pause Spotify.” · “Set the volume to 30 percent.”"),
        ("Screen and Selection", ["screen.", "selection.", "clipboard."], "“What application am I using?” · “Explain the selected text.”"),
        ("Web and Research", ["web.", "browser."], "“Summarize this webpage.” · “Find images of Yosemite.” · “Find research publications about phishing.”"),
        ("Automation and Workflows", ["shortcuts.", "workflows."], "“Run my study workflow.”"),
        ("System Utilities", ["system."], "“Open Bluetooth settings.”")
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Ask naturally. Sotto chooses a tool and requests access when needed.")
                .foregroundStyle(.secondary)
            ForEach(groups.indices, id: \.self) { index in
                let group = groups[index]
                GroupBox(group.0) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(group.2).font(.callout)
                        ForEach(NativeTools.registry().descriptors.filter { tool in group.1.contains(where: tool.id.hasPrefix) }, id: \.id) { tool in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(tool.name).font(.system(size: 13, weight: .medium))
                                    Spacer()
                                    Text(availability(tool)).font(.caption).foregroundStyle(.secondary)
                                }
                                Text(tool.description).font(.caption).foregroundStyle(.secondary)
                                if tool.id == "files.index" {
                                    Button("Document search options…") { model.settingsSection = "Documents" }.font(.caption)
                                }
                                if tool.id == "web.search" {
                                    Button("Web search options…") { model.settingsSection = "Web" }.font(.caption)
                                }
                                if let kind = missingPermission(tool) {
                                    Button(kind == .appleNotes ? "Connect Apple Notes…" : "Open \(kind.title) permissions…") {
                                        if kind == .appleNotes { Task { await model.permissions.request(kind) } }
                                        else { model.permissions.openSettings(kind) }
                                    }.font(.caption)
                                }
                            }
                        }
                    }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Text("Search runs inside Sotto. General web results use a connected search service; without it, the fallback is clearly labeled Wikipedia search. Wikipedia, Wikimedia images and Crossref publications work without that connection. Browser reading uses the foreground page in Safari, Chrome, Edge or Brave after approval; pages that expose no accessible text are unsupported. Sotto does not inspect cookies or background tabs, fill forms or run page scripts. Fetching and downloading support selected public publishers.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Refresh permissions") { model.refreshEnvironment() }
        }
    }
    private func missingPermission(_ tool: ToolDescriptor) -> PermissionKind? {
        if tool.id.hasPrefix("appleNotes."), model.permissions.state(.appleNotes) != .allowed { return .appleNotes }
        for (capability, kind) in [(Capability.contacts, PermissionKind.contacts), (Capability.calendar, PermissionKind.calendar), (.reminders, .reminders), (.accessibility, .accessibility)] {
            if tool.capabilities.contains(capability), model.permissions.state(kind) != .allowed { return kind }
        }
        return nil
    }
    private func availability(_ tool: ToolDescriptor) -> String {
        if tool.id.hasPrefix("appleNotes."), NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Notes") == nil { return "Apple Notes required" }
        if tool.id.hasPrefix("browser."), !["com.apple.Safari", "com.google.Chrome", "com.microsoft.edgemac", "com.brave.Browser"].contains(where: { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }) { return "Supported browser required" }
        if missingPermission(tool) != nil { return "Permission needed" }
        if tool.id == "files.index" { return LocalDocumentIndex.automaticEnabled ? "Automatic" : "Automatic search off" }
        if ["screen.capture", "screen.readText"].contains(tool.id) && !CGPreflightScreenCaptureAccess() { return "Screen Recording needed" }
        if tool.id.hasPrefix("media."), NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") == nil { return "Spotify required" }
        if tool.risk == .consequential { return "Approval required" }
        if tool.id.hasPrefix("web.") { return "Network required" }
        if tool.id == "timers.start" { return "Notification access checked on use" }
        return "Available · checked on use"
    }
}
