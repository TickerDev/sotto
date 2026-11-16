import AppKit
import SwiftUI

/// Public system materials only. The compositor owns blur, vibrancy and wallpaper sampling.
struct NativeMaterial: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    var blending: NSVisualEffectView.BlendingMode = .withinWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = PassiveMaterialView()
        view.material = material
        view.blendingMode = blending
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
    }
}

private struct FloatingGlass: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme
    let radius: CGFloat

    @ViewBuilder func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if reduceTransparency {
            content.background(Color(nsColor: .windowBackgroundColor), in: shape)
                .overlay(shape.strokeBorder(.primary.opacity(contrast == .increased ? 0.45 : 0.12), lineWidth: 0.5))
        } else if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
                .overlay { if contrast == .increased { shape.strokeBorder(.primary.opacity(0.45), lineWidth: 1) } }
        } else {
            content.background {
                NativeMaterial(material: .hudWindow, blending: .behindWindow).clipShape(shape)
            }
            .overlay(shape.strokeBorder(.primary.opacity(contrast == .increased ? 0.45 : 0.10), lineWidth: 0.5))
            .overlay(shape.inset(by: 0.5).strokeBorder(.white.opacity(colorScheme == .dark ? 0.13 : 0.4), lineWidth: 0.5))
        }
    }
}

extension View {
    func floatingGlass(radius: CGFloat = 26) -> some View { modifier(FloatingGlass(radius: radius)) }
}

/// Settings content stays quieter than the floating controls and navigation glass.
private struct SettingsSurface: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(reduceTransparency ? AnyShapeStyle(Color(nsColor: .controlBackgroundColor)) : AnyShapeStyle(.ultraThinMaterial))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.primary.opacity(contrast == .increased ? 0.4 : 0.055), lineWidth: 0.5))
    }
}

struct SettingsGroup<Content: View>: View {
    private let title: String?
    private let content: Content

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title { Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).padding(.leading, 4) }
            VStack(alignment: .leading, spacing: 16) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background { SettingsSurface() }
        }
    }
}

/// Decorative AppKit backdrops must never become a mouse-event target.
final class PassiveMaterialView: NSVisualEffectView {
    override var mouseDownCanMoveWindow: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Apply once per window, never as a side effect of a preference or network result.
public enum SettingsWindowPolicy {
    @MainActor public static func apply(to window: NSWindow) {
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        if !window.styleMask.contains(.fullSizeContentView) { window.styleMask.insert(.fullSizeContentView) }
        window.backgroundColor = .clear
        window.isOpaque = false
        window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = false
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
    }
}

/// Covers the native Settings scene as well as the AppKit-owned Settings window.
struct SettingsWindowChrome: NSViewRepresentable {
    final class Attachment: NSView {
        private weak var configuredWindow: NSWindow?
        override var mouseDownCanMoveWindow: Bool { false }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, configuredWindow !== window else { return }
            configuredWindow = window
            SettingsWindowPolicy.apply(to: window)
        }
    }
    func makeNSView(context: Context) -> Attachment { Attachment() }
    func updateNSView(_ view: Attachment, context: Context) {}
}

/// Preserve native controls while giving preferences a consistent trailing control column.
struct SettingsToggle: View {
    let title: String
    @Binding var value: Bool
    init(_ title: String, isOn value: Binding<Bool>) { self.title = title; _value = value }
    var body: some View {
        HStack(spacing: 20) {
            Text(title)
            Spacer(minLength: 12)
            Toggle(title, isOn: $value).labelsHidden().fixedSize().accessibilityLabel(title)
        }
    }
}

struct SettingsPicker<Selection: Hashable, Content: View>: View {
    let title: String
    @Binding var selection: Selection
    let content: Content
    init(_ title: String, selection: Binding<Selection>, @ViewBuilder content: () -> Content) {
        self.title = title; _selection = selection; self.content = content()
    }
    var body: some View {
        HStack(spacing: 20) {
            Text(title)
            Spacer(minLength: 12)
            Picker(title, selection: $selection) { content }
                .labelsHidden().frame(width: 210).accessibilityLabel(title)
        }
    }
}

struct SettingsValueStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 20) {
            configuration.label
            Spacer(minLength: 12)
            configuration.content.foregroundStyle(.secondary).multilineTextAlignment(.trailing)
        }
    }
}
