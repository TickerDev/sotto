import SwiftUI
import AppKit
import Observation
import VoiceGlowKit
import SottoAgent
import SottoSecurity
import SottoTools
import OSLog

public struct CapsuleView: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let preview: Bool
    private let maximumSize: CGSize
    private let sizeChanged: (CGSize) -> Void
    @State private var contentHeight: CGFloat = 100
    public init(model: AppModel, preview: Bool = false, maximumSize: CGSize = CGSize(width: 456, height: 800), sizeChanged: @escaping (CGSize) -> Void = { _ in }) {
        self.model = model; self.preview = preview; self.maximumSize = maximumSize; self.sizeChanged = sizeChanged
    }
    private var shellWidth: CGFloat { max(1, min(400, maximumSize.width - 56)) }
    private var viewportHeight: CGFloat { max(1, min(contentHeight, maximumSize.height - 56)) }

    private var symbol: String {
        switch model.state {
        case .listening: "waveform"
        case .completed: "checkmark"
        case .failed: "exclamationmark"
        case .awaitingApproval: "hand.raised"
        case .awaitingInput: "questionmark.bubble"
        case .responded: "text.bubble"
        default: "sparkle"
        }
    }

    public var body: some View {
        ScrollView {
            content
                .fixedSize(horizontal: false, vertical: true)
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: CapsuleContentHeight.self, value: proxy.size.height)
                })
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: shellWidth, height: viewportHeight)
        .floatingGlass(radius: 26)
        .voiceGlow(
            type: .standard,
            levelProvider: {
                guard model.state == .listening else { return 0 }
                return min(1, Double(model.levels.last ?? 0) * 1.6)
            },
            active: model.state == .listening,
            cornerRadius: 26
        )
        .shadow(color: .black.opacity(0.16), radius: 18, x: 0, y: 8)
        .padding(28)
        .onPreferenceChange(CapsuleContentHeight.self) { height in
            guard height > 0, height.isFinite else { return }
            contentHeight = height
            sizeChanged(CGSize(width: shellWidth + 56, height: max(1, min(height, maximumSize.height - 56)) + 56))
        }
        .onChange(of: maximumSize) { _, _ in sizeChanged(CGSize(width: shellWidth + 56, height: viewportHeight + 56)) }
        .animation(reduceMotion || model.state == .listening ? nil : .spring(duration: 0.32, bounce: 0.08), value: model.state)
        .disabled(preview)
        .onExitCommand { if !preview { model.cancel() } }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 32, height: 32)
                    .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace, options: .nonRepeating))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.status).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                    Text(hint).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if [.thinking, .executing, .transcribing].contains(model.state) {
                    ProgressView().controlSize(.small).accessibilityLabel(model.status)
                }
                dismissButton
            }
            if let approval = model.approval {
                let presentation = ApprovalPresentation(approval)
                VStack(alignment: .leading, spacing: 12) {
                    Text(presentation.title).font(.system(size: 13, weight: .medium))
                    CapsuleBody {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(presentation.fields) { field in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(field.label).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                                    Text(field.value).font(.system(size: 12)).textSelection(.enabled)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack {
                        Button("Deny", role: .cancel) { model.resolveApproval(false) }
                        Spacer()
                        Button("Approve once") { model.resolveApproval(true) }.buttonStyle(.borderedProminent)
                    }
                }.transition(.opacity)
            } else if !model.fileMatches.isEmpty {
                FileMatchesView(matches: model.fileMatches) { match, reveal in model.openFileMatch(match, reveal: reveal) }
            } else if model.state == .listening && !model.transcript.isEmpty {
                CapsuleBody {
                    (Text(model.confirmedSpeech).foregroundColor(.primary) + Text(model.provisionalSpeech).foregroundColor(.secondary))
                        .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.padding(.leading, 4)
            } else if !bodyText.isEmpty {
                CapsuleBody {
                    Text(bodyText).font(.system(size: 12)).foregroundStyle(.secondary)
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.padding(.leading, 4).transition(.opacity)
            }
            if model.state == .listening {
                HStack(spacing: 12) {
                    if model.transcript.isEmpty {
                        Text("Speak now…")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    sendButton
                }
                .frame(minHeight: 32)
                .transition(.opacity)
            }
            if model.state == .failed, let recovery = model.recovery {
                Button(recovery.title) { model.recover() }.buttonStyle(.borderless).font(.system(size: 12))
            }
            if [.completed, .failed, .responded, .awaitingInput].contains(model.state) {
                HStack(spacing: 16) {
                    if model.canRunVoiceCheckCommand {
                        Button("Run command", systemImage: "arrow.up") { model.runVoiceCheckCommand() }
                            .buttonStyle(.borderedProminent).controlSize(.small)
                            .help("Send this transcript to your selected provider and execute your request")
                            .accessibilityIdentifier("run-voice-check-command")
                    }
                    Button(model.capturePurpose == .voiceCheck ? "Speak a command" : model.state == .awaitingInput ? "Reply" : "Speak again", systemImage: "mic") { model.beginListening() }
                        .buttonStyle(.borderless).font(.system(size: 12))
                }.padding(.leading, 4)
            }
        }
        .padding(20).frame(width: shellWidth)
    }

    private var bodyText: String {
        if model.state == .completed && !model.confirmedSummary.isEmpty {
            return model.reply.isEmpty || model.reply == model.confirmedSummary
                ? model.confirmedSummary : model.confirmedSummary + "\n\n" + model.reply
        }
        return model.reply.isEmpty ? model.transcript : model.reply
    }

    private var hint: String {
        if preview { "Interface preview · no task is running" }
        else if model.capturePurpose == .voiceCheck { model.state == .listening ? "\(model.voiceActivation.hint) · \(model.settings.speechBackend.name)" : "Transcription test · no command executed" }
        else if model.state == .listening { model.voiceActivation.hint }
        else if model.state == .awaitingApproval { "Review before continuing" }
        else if model.state == .awaitingInput { "Your request is still in progress" }
        else if model.state == .responded { model.reply.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("?") ? "Speak to reply" : "Speak to continue" }
        else { "Sotto" }
    }

    @ViewBuilder private var sendButton: some View {
        if #available(macOS 26.0, *) {
            Button(model.capturePurpose == .voiceCheck ? "Finish" : "Send", systemImage: "arrow.up") { model.endListening() }
                .buttonStyle(.glass).controlSize(.small)
                .help(model.capturePurpose == .voiceCheck ? "Finish transcription without running a command" : "Finish recording and send your request")
                .accessibilityLabel(model.capturePurpose == .voiceCheck ? "Finish voice check" : "Send recording")
        } else {
            Button(model.capturePurpose == .voiceCheck ? "Finish" : "Send", systemImage: "arrow.up") { model.endListening() }
                .buttonStyle(.bordered).controlSize(.small)
                .help(model.capturePurpose == .voiceCheck ? "Finish transcription without running a command" : "Finish recording and send your request")
                .accessibilityLabel(model.capturePurpose == .voiceCheck ? "Finish voice check" : "Send recording")
        }
    }

    @ViewBuilder private var dismissButton: some View {
        dismissControl
            .overlay {
                if let window = model.autoDismissWindow {
                    AutoDismissRing(window: window)
                        .padding(-1)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
    }

    @ViewBuilder private var dismissControl: some View {
        if #available(macOS 26.0, *) {
            Button { model.cancel() } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).frame(width: 24, height: 24)
            }
            .buttonStyle(.glass).buttonBorderShape(.circle)
            .help("Cancel (Esc)").accessibilityLabel("Cancel Sotto")
        } else {
            Button { model.cancel() } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).frame(width: 24, height: 24)
            }.buttonStyle(.borderless).help("Cancel (Esc)").accessibilityLabel("Cancel Sotto")
        }
    }
}

private struct AutoDismissRing: View {
    let window: AutoDismissWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        if reduceMotion {
            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                ring(progress: window.progress())
            }
        } else {
            TimelineView(.animation) { _ in
                ring(progress: window.progress())
            }
        }
    }

    private func ring(progress: Double) -> some View {
        ZStack {
            Circle()
                .stroke(.primary.opacity(contrast == .increased ? 0.22 : 0.07), lineWidth: 1.5)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(.primary.opacity(contrast == .increased ? 0.65 : 0.32), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

public final class VoicePanel: NSPanel {
    private var model: AppModel!
    private var hosting: NSHostingView<CapsuleView>!
    private var preview = false
    private var targetDisplay: NSNumber?
    private var screenObserver: CapsuleScreenObserver?
    private var measuredSize = CGSize(width: 456, height: 156)
    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { false }

    @MainActor public init(model: AppModel, preview: Bool = false) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 456, height: 150), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        self.model = model
        self.preview = preview
        isFloatingPanel = true
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false // The glass shell, rather than the transparent window bounds, casts the shadow.
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        hosting = NSHostingView(rootView: CapsuleView(model: model, preview: preview))
        // AppKit must not resize the window from its top edge when intrinsic
        // SwiftUI content grows. The measured root is the sole sizing authority.
        hosting.sizingOptions = []
        contentView = hosting
        updateScreenLayout()
        hosting.layoutSubtreeIfNeeded()
        screenObserver = CapsuleScreenObserver(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.updateScreenLayout() }
        })
    }

    private var placementScreen: NSScreen? {
        NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber) == targetDisplay } ?? NSScreen.main ?? NSScreen.screens.first
    }
    private func updateScreenLayout() {
        guard let screen = placementScreen else { return }
        targetDisplay = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        let area = CapsulePlacement.usableArea(screen.visibleFrame)
        hosting.rootView = CapsuleView(model: model, preview: preview, maximumSize: area.size) { [weak self] size in
            self?.measuredSize = size
            self?.placeMeasuredContent()
        }
        placeMeasuredContent()
    }
    private func placeMeasuredContent() {
        guard let visible = placementScreen?.visibleFrame else { return }
        let rect = CapsulePlacement.frame(for: measuredSize, visibleFrame: visible)
        if rect != frame { setFrame(rect, display: true) }
    }

    @MainActor public func show() {
        let started = ContinuousClock.now
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        targetDisplay = screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        updateScreenLayout()
        alphaValue = 1
        orderFrontRegardless()
        Logger(subsystem: "org.sotto.mac", category: "latency").notice("Panel positioning and ordering: \(String(describing: started.duration(to: .now)), privacy: .public)")
        // Display the already prepared panel first. Content measurement must not
        // delay the input event callback or the first visible response.
        DispatchQueue.main.async { [weak self] in self?.hosting.layoutSubtreeIfNeeded() }
    }
}

/// Immutable notification token; NotificationCenter removal is thread-safe.
private final class CapsuleScreenObserver: @unchecked Sendable {
    let token: NSObjectProtocol
    init(_ token: NSObjectProtocol) { self.token = token }
    deinit { NotificationCenter.default.removeObserver(token) }
}

enum CapsulePlacement {
    static func usableArea(_ visible: CGRect) -> CGRect {
        let margin = min(14, max(0, min(visible.width, visible.height) / 4))
        return visible.insetBy(dx: margin, dy: margin)
    }
    static func frame(for desired: CGSize, visibleFrame: CGRect) -> CGRect {
        let area = usableArea(visibleFrame)
        let width = min(max(1, desired.width.isFinite ? desired.width : 456), area.width)
        let height = min(max(1, desired.height.isFinite ? desired.height : 156), area.height)
        return CGRect(x: area.midX - width / 2, y: area.minY, width: width, height: height)
    }
}

private struct CapsuleContentHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Grow naturally for short feedback; make the full text scrollable when it is long.
private struct CapsuleBody<Content: View>: View {
    let content: Content
    @State private var height: CGFloat = 18
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        ScrollView {
            content.background {
                GeometryReader { proxy in
                    Color.clear.preference(key: CapsuleBodyHeight.self, value: proxy.size.height)
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: min(max(18, height), 180))
        .onPreferenceChange(CapsuleBodyHeight.self) { height = $0 }
    }
}
private struct CapsuleBodyHeight: PreferenceKey {
    static let defaultValue: CGFloat = 18
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

