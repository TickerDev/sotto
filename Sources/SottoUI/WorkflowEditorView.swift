import SwiftUI
import AppKit
import UniformTypeIdentifiers
import SottoIntegrations
import SottoTools

struct WorkflowEditorSession: Identifiable {
    let id = UUID()
    let workflow: SavedWorkflow?
}
struct WorkflowEditorView: View {
    let original: SavedWorkflow?
    let saved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var steps: [WorkflowEditorStep]
    @State private var error: String?
    private let unsupported: Bool
    init(session: WorkflowEditorSession, saved: @escaping () -> Void) {
        original = session.workflow; self.saved = saved
        _name = State(initialValue: session.workflow?.name ?? "")
        do {
            if let original = session.workflow {
                _ = try WorkflowDefinition.validate(original.steps, registry: NativeTools.registry())
                guard case .array(let values) = original.steps else { throw WorkflowEditorError.unsupported }
                _steps = State(initialValue: try values.map(WorkflowEditorStep.init))
            } else { _steps = State(initialValue: []) }
            unsupported = false
        } catch {
            _steps = State(initialValue: []); _error = State(initialValue: error.localizedDescription)
            unsupported = true
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(original == nil ? "New workflow" : "Edit workflow").font(.title2.weight(.semibold))
            Text("Choose what happens, in order. Saving doesn’t run the actions.").font(.callout).foregroundStyle(.secondary)
            TextField("Workflow name", text: $name).textFieldStyle(.roundedBorder)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach($steps) { $step in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                let position = steps.firstIndex(where: { $0.id == step.id }) ?? 0
                                Text("Action \(position + 1)").font(.headline)
                                Spacer()
                                Button { move(step.id, by: -1) } label: { Image(systemName: "arrow.up") }
                                    .disabled(position == 0).accessibilityLabel("Move action \(position + 1) earlier")
                                Button { move(step.id, by: 1) } label: { Image(systemName: "arrow.down") }
                                    .disabled(position == steps.count - 1).accessibilityLabel("Move action \(position + 1) later")
                                Button("Remove") { steps.removeAll { $0.id == step.id } }
                                    .accessibilityLabel("Remove action \(position + 1)")
                            }
                            WorkflowStepEditor(step: $step)
                            Divider()
                        }
                    }
                    if steps.isEmpty && !unsupported {
                        Text("Add an action, or cancel and ask Sotto to create the routine by voice.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Button("Add action") { steps.append(WorkflowEditorStep()) }
                .disabled(steps.count >= 10 || unsupported)
            if let error { Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                Text("\(steps.count) of 10 actions").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save workflow") { save() }.keyboardShortcut(.defaultAction)
                    .disabled(unsupported || steps.isEmpty || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(24).frame(width: 580).frame(minHeight: 460, maxHeight: 720)
    }
    private func move(_ id: UUID, by offset: Int) {
        guard let from = steps.firstIndex(where: { $0.id == id }), steps.indices.contains(from + offset) else { return }
        steps.swapAt(from, from + offset)
    }
    private func save() {
        do {
            let candidate = SavedWorkflow(name: name, steps: .array(steps.map(\.json)), id: original?.id ?? UUID())
            _ = try WorkflowStore.shared.upsert(candidate, expectedRevision: original?.revision, registry: NativeTools.registry())
            saved(); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
private struct WorkflowStepEditor: View {
    @Binding var step: WorkflowEditorStep
    @State private var devices: [OutputChoice] = []
    @State private var deviceError: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Action", selection: $step.kind) {
                ForEach(WorkflowActionKind.allCases) { kind in Text(kind.title).tag(kind) }
            }
            switch step.kind {
            case .folder, .openFile, .revealFile:
                HStack {
                    Text(step.path.isEmpty ? "Choose a location" : step.path).font(.caption).textSelection(.enabled)
                    Spacer()
                    Button("Choose…") { chooseFile() }
                }
            case .application:
                HStack {
                    Text(appName).font(.callout)
                    Spacer()
                    Button("Choose application…") {
                        let panel = NSOpenPanel(); panel.allowedContentTypes = [.applicationBundle]
                        panel.directoryURL = URL(fileURLWithPath: "/Applications")
                        if panel.runModal() == .OK, let url = panel.url { step.bundleID = Bundle(url: url)?.bundleIdentifier ?? "" }
                    }
                }
            case .volume:
                Picker("Volume action", selection: $step.volumeAction) {
                    ForEach(["set", "up", "down", "off", "on", "status"], id: \.self) { action in
                        Text(volumeLabel(action)).tag(action)
                    }
                    if !["set", "up", "down", "off", "on", "status"].contains(step.volumeAction) {
                        Text(step.volumeAction.capitalized).tag(step.volumeAction)
                    }
                }.onChange(of: step.volumeAction) { _, _ in step.volumeValue = "" }
                if step.volumeAction == "set" {
                    Slider(value: $step.volume, in: 0...100, step: 1) { Text("Volume") }
                    Text("\(Int(step.volume))%").font(.caption).monospacedDigit()
                } else if ["up", "down"].contains(step.volumeAction) {
                    TextField("Optional adjustment in percent", text: $step.volumeValue)
                }
            case .audioOutput:
                Picker("Audio action", selection: $step.outputAction) {
                    Text("Select speakers").tag("select"); Text("List speakers").tag("list")
                }
                if step.outputAction == "select" {
                    Picker("Speakers", selection: $step.outputID) {
                        if !devices.contains(where: { $0.id == step.outputID }) {
                            Text(step.outputID == 0 ? "Choose speakers" : "Saved speakers are unavailable").tag(step.outputID)
                        }
                        ForEach(devices) { device in Text(device.name).tag(device.id) }
                    }
                    Button("Refresh speakers") { Task { await refreshDevices() } }
                    if let deviceError { Text(deviceError).font(.caption).foregroundStyle(.secondary) }
                }
            case .timer:
                TextField("Timer name (optional)", text: $step.timerName)
                HStack {
                    Text("Duration in seconds")
                    TextField("Seconds", value: $step.seconds, format: .number).frame(width: 100)
                }
                Text("For example, 1500 seconds is 25 minutes.").font(.caption).foregroundStyle(.secondary)
            case .settings:
                TextField("Settings page, such as Bluetooth or Sound", text: $step.pane)
            case .context:
                Text("Read the name of the application you’re using. No screenshot is taken.").font(.caption).foregroundStyle(.secondary)
            }
        }.task(id: step.kind) { if step.kind == .audioOutput { await refreshDevices() } }
    }
    private var appName: String {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: step.bundleID)?.deletingPathExtension().lastPathComponent ?? (step.bundleID.isEmpty ? "Choose an application" : "Saved application is unavailable")
    }
    private func volumeLabel(_ action: String) -> String {
        ["set": "Set volume", "up": "Louder", "down": "Quieter", "off": "Mute", "on": "Unmute", "status": "Check volume"][action] ?? action.capitalized
    }
    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = step.kind == .folder || step.kind == .revealFile
        panel.canChooseFiles = step.kind != .folder
        if panel.runModal() == .OK { step.path = panel.url?.path ?? "" }
    }
    private func refreshDevices() async {
        do {
            let result = try await NativeTools.registry().tool("audio.output").execute(arguments: .object(["action": .string("list"), "device_id": .number(0)]))
            guard case .array(let rows) = result.data else { return }
            devices = rows.compactMap { row in
                guard case .number(let id) = row.object?["device_id"], let name = row.object?["name"]?.string else { return nil }
                return OutputChoice(id: id, name: name)
            }
            deviceError = nil
        } catch { deviceError = error.localizedDescription }
    }
}
private struct OutputChoice: Identifiable { let id: Double; let name: String }
