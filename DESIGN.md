# Sotto native interface

## Direction

A quiet macOS utility using public Apple materials, restrained hierarchy, and system controls. Liquid Glass is functional surface rendering, not an ornamental blur layer. Preserve the voice-first menu bar lifecycle and existing capabilities. No web UI, proprietary Apple assets, saturated gradients, opaque dashboard panels, or fake waveform motion.

## Material hierarchy

- Floating capsule: SwiftUI `glassEffect(.regular)` on macOS 26+, with a continuous 26-point shell, a soft downward shadow, and native glass close control. macOS 14–15 uses behind-window NSVisualEffectView HUD vibrancy with faint edge highlights.
- Settings window: behind-window native under-window material, integrated transparent chrome, and a native sidebar using sidebar vibrancy.
- Settings groups: quieter ultra-thin system material, 14-point corners, and half-point low-opacity edges. Content remains below the visual emphasis of navigation and floating controls.
- Never stack multiple glass effects on the same shell. Let the compositor handle blur, wallpaper influence, and light/dark adaptation.

## Layout and type

Use SF system text and SF Symbols. Settings sidebar is 200–240 points wide (210 ideal); detail content has a 640-point maximum measure and 28-point margins. Group gaps are 26 points, heading gaps 10, panel insets 18, and row gaps 16. Native controls sit in a trailing column. Settings titles are 23-point semibold, section labels 12-point semibold, and capsule status 13-point semibold. Secondary text uses semantic secondary foreground.

Keep the native sidebar selection, keyboard behavior, focus indicators, menu pickers, switches, and accessibility labels. Sidebar icons are monochrome. No custom control should replace a native behavior merely to reproduce a screenshot.

## Capsule and motion

The capsule fits its content rather than occupying a fixed tall window. State changes use a short, low-bounce spring. Actual microphone samples drive its monochrome waveform. The window appears without activating the user's application context. Approval arguments scroll rather than being silently clipped. Quiet states have no looping decorative animation.

Listening appears without an entrance fade or spring. The prepared panel is ordered immediately and measured afterward; subsequent task-state changes retain restrained motion. Reduce Motion disables authored springs, symbol replacement and waveform interpolation. Reduce Transparency substitutes opaque semantic surfaces. Increase Contrast strengthens shell and group edges. Test these settings on real supported systems before claiming accessibility certification.

## Build compatibility

Deployment remains macOS 14+. Compiling the Liquid Glass branches requires Xcode 26+ / macOS 26 SDK or later. Availability checks preserve native material fallbacks at runtime.

## Review

November 15, 2026: built with Xcode 27; inspected native Settings in dark/system and light appearances and the real idle capsule in its nonactivating panel. No audio capture or model inference was used for the visual review. Permission-dependent interaction tests remain tracked separately in docs/VALIDATION.md.

## Questions and feedback

Questions use an explicit question icon, the A quick question title, and a Reply action. They remain part of the active request. Ordinary informational responses use a text bubble; a checkmark is reserved for a confirmed native tool result. Requested reminders do not show an additional Sotto approval.

Consequential approvals show a human-readable action and labeled values. Never replace or mutate the immutable authorization arguments for presentation. Show the full file location, with selectable text and bounded scrolling for long details.

Completion headers stay short (Done); actual tool summaries and explanatory text live in the scrollable body. Short confirmations dismiss quietly; longer results remain readable until dismissed or expired. The NSPanel uses explicit SwiftUI content measurements, with AppKit automatic intrinsic window resizing disabled. It grows upward from a fixed bottom inset inside the selected display’s visible frame. Oversized content scrolls within that frame, and screen-configuration changes recalculate the available bounds. Debug interface fixtures must be labeled, inert, and kept separate from actual tool verification.

## Guided setup and recovery

Setup is an optional native checklist, not a blocking tour. Its progress reflects a verified provider, explicit processing choice, usable voice input and optional keyboard access. Existing users can revisit it from the menu bar. A microphone test uses real Apple Speech without model calls or tool execution; Test microphone only and Finish identify that privacy boundary.

The microphone-only test never uploads or executes its transcript automatically. A successful result offers an explicit Run command action using the same transcript through the trusted agent path. Speak a command starts normal capture rather than silently repeating the local test. Setup's test and command actions use distinct labels; trying a command may use a saved key without a new catalog verification, while finishing setup still requires verification.

Permissions use labeled native states and contextual actions. Do not present denied/restricted or system-managed access as granted. Do not ask for screen/Accessibility capabilities that are not implemented. Microphone selection is a preference. A missing preferred microphone remains visible while Sotto uses a working fallback. The capsule names the active input; a switch during recording clears the interrupted transcript and asks the user to repeat. Keep a working recording stable when a preferred input reconnects, and re-evaluate preference on the next activation.

Requested documents, file reveals and application launches do not show a second Sotto approval. Keep schema validation and file-type checks in trusted code. macOS permission prompts remain independent.

## Accessible result actions

File results use native Open, visibly named Summarize (supported text formats only), and Show in Finder actions. Preserve specific VoiceOver labels and location values. Measure natural list height, cap overflow and keep the footer adjacent to the rows.

Short confirmation countdowns pause while the pointer or keyboard focus is in the capsule. VoiceOver/Switch Control suppresses that short countdown; privacy/context expiry remains separate. Ordinary presentation never takes focus; menu-bar Review response may focus the panel because the user explicitly chose it. Announce stable outcomes and decisions, not every partial word or audio level.

Reduce Motion and Reduce Transparency omit the animated listening glow entirely and use a native actual-input level meter. Reduce Motion omits the animated dismissal ring. Do not change OS accessibility settings automatically to demonstrate these modes. Native AX-tree and inert visual review are evidence of controls/layout, not certification of spoken VoiceOver or physical accessibility use.
