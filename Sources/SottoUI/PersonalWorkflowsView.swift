import SwiftUI
import SottoIntegrations
import SottoTools

struct PersonalWorkflowsView: View {
    @Bindable var model: AppModel
    @State private var workflows: [SavedWorkflow] = []
    @State private var aliases = AliasStore.all()
    @State private var editor: WorkflowEditorSession?
    @State private var removing: SavedWorkflow?
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            GroupBox("Your workflows") {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Ask Sotto to remember a routine, then run it by name. You review the actions before saving or running.")
                        .font(.callout).foregroundStyle(.secondary)
                    Text("“Save a study session: open Notes, set the volume to 30 percent, and start a 25-minute timer.”")
                        .font(.callout).textSelection(.enabled)
                    if workflows.isEmpty { Text("No saved workflows yet.").foregroundStyle(.secondary) }
                    ForEach(workflows) { workflow in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(workflow.name).font(.headline)
                                Spacer()
                                Button("Run…") { model.runSavedWorkflow(workflow.name) }.disabled(model.isBusy)
                                    .accessibilityLabel("Run \(workflow.name)")
                                Button("Edit…") { editor = WorkflowEditorSession(workflow: workflow) }
                                    .accessibilityLabel("Edit \(workflow.name)")
                                Button("Remove", role: .destructive) { removing = workflow }
                                    .accessibilityLabel("Remove \(workflow.name)")
                            }
                            if case .array(let steps) = workflow.steps {
                                ForEach(steps.indices, id: \.self) { index in
                                    let summary = WorkflowActionSummary(steps[index])
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("\(index + 1). " + summary.title).font(.callout)
                                        Text(summary.detail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                                    }
                                }
                            }
                            Divider()
                        }
                    }
                    Button("New workflow…") { editor = WorkflowEditorSession(workflow: nil) }
                }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
            }
            WorkflowRecoveryView(model: model)
            GroupBox("Remembered names") {
                VStack(alignment: .leading, spacing: 10) {
                    if aliases.isEmpty { Text("Remember a file, folder, app or workflow by voice. For example: “Remember Notes as my writing app.”").foregroundStyle(.secondary) }
                    ForEach(aliases) { alias in
                        HStack {
                            VStack(alignment: .leading) { Text(alias.name); Text(aliasDescription(alias)).font(.caption).textSelection(.enabled) }
                            Spacer()
                            Button("Forget") {
                                do { try RememberedAliasStore.shared.remove(alias); aliases = AliasStore.all() }
                                catch { self.error = error.localizedDescription }
                            }
                        }
                    }
                }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
            }
            if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
        }
        .task { reload() }
        .onChange(of: model.workflowVersion) { _, _ in reload() }
        .sheet(item: $editor) { session in WorkflowEditorView(session: session, saved: reload) }
        .alert("Remove saved workflow?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), presenting: removing) { workflow in
            Button("Cancel", role: .cancel) { removing = nil }
            Button("Remove", role: .destructive) { remove(workflow) }
        } message: { workflow in
            Text("Remove “\(workflow.name)” from your saved workflows? Past actions will stay as they are.")
        }
    }
    private func aliasDescription(_ alias: RememberedAlias) -> String {
        switch alias.kind {
        case .application: return "Application: " + (alias.path.split(separator: ".").last.map(String.init) ?? alias.path)
        case .workflow: return "Workflow: " + (workflows.first(where: { $0.id.uuidString == alias.path })?.name ?? "No longer available")
        case .file, .folder: return alias.path
        }
    }
    private func reload() {
        do { workflows = try WorkflowStore.shared.all(); aliases = try RememberedAliasStore.shared.all(); error = nil }
        catch { self.error = error.localizedDescription }
    }
    private func remove(_ workflow: SavedWorkflow) {
        do {
            try WorkflowStore.shared.remove(id: workflow.id, name: workflow.name, expectedRevision: workflow.revision)
            removing = nil; reload()
        } catch { self.error = error.localizedDescription; removing = nil }
    }
}
