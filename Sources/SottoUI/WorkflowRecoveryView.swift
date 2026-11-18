import SwiftUI
import SottoIntegrations
import SottoTools

struct WorkflowRecoveryView: View {
    @Bindable var model: AppModel
    @State private var runs: [WorkflowRunRecord] = []
    @State private var error: String?
    @State private var forgetting: WorkflowRunRecord?
    var body: some View {
        GroupBox("Interrupted routines") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Continue remaining actions after reviewing the earlier results. Completed actions are never repeated.")
                    .font(.callout).foregroundStyle(.secondary)
                if runs.filter({ !$0.terminal }).isEmpty { Text("No interrupted routines.").foregroundStyle(.secondary) }
                ForEach(runs.filter { !$0.terminal }) { run in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(run.name).font(.headline)
                        Text(run.updatedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                        ForEach(run.steps.indices, id: \.self) { index in
                            let step = run.steps[index], summary = WorkflowActionSummary(step.definition)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(index + 1). \(summary.title) · \(stateLabel(step.state))").font(.callout)
                                Text(summary.detail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            }
                        }
                        if run.hasUncertainSteps {
                            Text("An action may already have taken effect. Check it before choosing to skip it. Skipping will not count it as verified.")
                                .font(.caption).foregroundStyle(.secondary)
                            Button("I checked — skip uncertain actions and continue…") {
                                model.resumeWorkflow(run.id, skipUncertain: true)
                            }.disabled(model.isBusy)
                        } else {
                            Button("Continue remaining actions…") { model.resumeWorkflow(run.id, skipUncertain: false) }.disabled(model.isBusy)
                        }
                        Button("Forget recovery record…", role: .destructive) { forgetting = run }.disabled(model.isBusy)
                        Divider()
                    }
                }
                if runs.contains(where: \.terminal) {
                    DisclosureGroup("Finished routines") {
                        ForEach(runs.filter(\.terminal)) { run in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(run.name)
                                    Text(run.state == .completed ? "Completed" : "Finished with unverified skipped actions").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Forget…") { forgetting = run }.disabled(model.isBusy)
                            }
                        }
                    }
                }
                Text("Recovery stays on this Mac. Completed records expire after a week or make room for newer runs; interrupted records remain until reviewed or forgotten.")
                    .font(.caption).foregroundStyle(.secondary)
                if let error { Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled) }
            }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { await reload() }
        .onChange(of: model.workflowVersion) { _, _ in Task { await reload() } }
        .alert("Forget recovery record?", isPresented: Binding(get: { forgetting != nil }, set: { if !$0 { forgetting = nil } }), presenting: forgetting) { run in
            Button("Cancel", role: .cancel) { forgetting = nil }
            Button("Forget record", role: .destructive) {
                Task {
                    do { try await Task.detached { try WorkflowJournal.shared.remove(run.id) }.value; forgetting = nil; await reload() }
                    catch { self.error = error.localizedDescription; forgetting = nil }
                }
            }
        } message: { run in
            Text("Forget recovery for “\(run.name)”? This removes its recovery evidence. Past actions remain as they are.")
        }
    }
    private func reload() async {
        do { runs = try await Task.detached(priority: .utility) { try WorkflowJournal.shared.records() }.value; error = nil }
        catch { self.error = error.localizedDescription }
    }
    private func stateLabel(_ state: WorkflowStepState) -> String {
        switch state {
        case .pending: "Not started"
        case .running, .uncertain: "Needs checking"
        case .succeeded: "Completed"
        case .skipped: "Skipped · unverified"
        }
    }
}
