# Sotto roadmap

## Working MVP

Native menu bar app, Liquid Glass/material interface, persisted Settings, push-to-talk and click/toggle modes, Send control, real microphone waveform, Apple Speech, direct OpenAI reasoning, bounded tool loop, trusted authorization, Spotify, Finder/Spotlight, applications, Reminders, Keychain, and GRDB history are implemented. Live Finder execution and model clarification were verified directly. The user has tested the voice flow, supplied reminder-creation/offline-failure screenshots, and reports the checklist working. Keep the individual evidence and limits in VALIDATION.md; this is not release certification.

The latest interaction pass adds typed follow-up questions, context-preserving replies, readable approvals, non-truncated results, and accurate distinctions between questions, information and confirmed actions. Reminder creation follows the user's preference: a clear request is sufficient authorization. Native OS consent still applies.

## v0.2: setup and reliability — implemented

- Optional, replayable native setup with real provider verification, explicit privacy choices, a voice-only transcription check, activation selection and a real first-command entry point.
- Permission status, explicit requests and targeted recovery links; contextual capsule recovery actions for voice/provider/privacy failures.
- Stable Core Audio UIDs, visible missing-device state, event-driven inventory/default-input monitoring and recording discard on route changes, engine reconfiguration or sleep.
- Asynchronous bounded Spotify helper, cancellation/timeout/output limits, play/pause state readback and a read-only connection checker in Settings.
- Backward-compatible settings migration and optional stable local development signing without committing personal identity data.

Physical unplug/reconnect during capture, fresh/revoked native permission flows and accessibility/minimum-OS validation remain release checks. Voice phase instrumentation is implemented; controlled physical-device performance benchmarks remain pending.

## v0.4: local reasoning — implemented

- Local Ollama adapter with native streaming chat/tool results, installed-model capability discovery and a shared native provider selector in Setup and Settings.
- Loopback-only destinations, no redirects/proxy credentials, cloud-tag rejection before sending transcript data, and the existing trusted tool authorization gate.
- Separate persisted model choices and context clearing when changing destinations. OpenAI credentials and consent are not required for local requests.
- Protocol/HTTP fixture tests plus a real Qwen3 1.7B agent loop that opened Downloads, consumed its confirmed result, and completed. See LOCAL-MODELS.md for runtime setup, boundaries and validation.

## Zero-configuration direction — implemented

Native commands run before model selection, without accounts, keys or external runtimes. New installations use Automatic for flexible requests: available on-device intelligence, then a local model. Guided connections preserve the waiting request; remote use remains explicit. Adaptive microphones and managed startup of an installed local engine reduce setup work. [ZERO-CONFIGURATION.md](ZERO-CONFIGURATION.md) records implementation and validation limits.

Calendar agenda reading follows this direction: “What’s on my calendar today/tomorrow?” needs only just-in-time macOS access. It reads a bounded date range and never changes events. Native dates handle daylight-saving transitions. The actual connection sheet and cancellation were inspected; authorized calendar retrieval remains a manual acceptance test.

## Real-time voice — implemented, hardware acceptance ongoing

- Modern on-device SpeechAnalyzer/SpeechTranscriber on supported macOS 26+ configurations, explicit language preparation and streaming legacy fallback on the macOS 14 deployment floor.
- Confirmed/provisional capsule text, same-shortcut hold/double-tap and optional press-to-toggle, bounded finalization and cancellation.
- Inference-only preparation during stable pauses, invalidated by resumed/changed speech; all tools wait for explicit submission and confirmed transcription. Existing native routing and agent integrations retained.
- Optional OpenAI Realtime speech with separate raw-audio consent and Keychain credentials, independent of reasoning.
- 164 offline checks and a real synthetic on-device analyzer test pass. Native controls/start/cancel inspected. Cold-start latency, physical speech-to-action timings, minimum OS and Intel acceptance remain work. See [research and validation](REALTIME-VOICE.md).

## Next: responsiveness and everyday tasks

- Reduce cold speech startup and benchmark repeated physical hold/toggle/double-tap sessions, corrections, interruption, first action and verified completion without continuous microphone capture.

- Verify the Calendar voice → permission → agenda flow with user-granted access, including empty/all-day agendas.
- Add Calendar creation only with clear date/duration handling, trusted authorization and actual save verification; invitations and edits remain unavailable.
- Develop purpose-scoped document understanding and native integrations with the same ask-when-needed flow.
- Keep models, endpoints and tool diagnostics in Advanced. Bundled model lifecycle still needs pinned licensed artifacts, verified downloads, disk/memory checks and real reliability measurements before one-click installation.

## Later: provider expansion

- Add compatible endpoints only with explicit destination configuration and credential isolation.
- Implement Codex app-server only after the documented auth, versioning and restricted-tool bridge requirements in PROVIDERS.md are met. It must not bypass Sotto's native authorization policy.

## Later: context and integrations

Foreground application context is a foundation. Selected text, window context and screen capture require explicit purpose-scoped access and privacy disclosures before model upload. Mail, Calendar writes, Safari, Notes, Shortcuts, permitted Discord accessibility context and MCP need working adapters and truthful availability labels before enabling UI.

## Release gates

Release tooling now requires explicit Developer ID credentials and checks old/new designated requirements before notarization and packaging. See RELEASING.md. The 14 release policy tests pass; actual signing/notarization and a two-version consent-preservation test still require the official certificate, notarization profile and release artifacts. Separate development/beta identifiers must be finalized before public distribution. No automatic updater is implemented.

Use a stable signing identity; verify fresh-install and revoked-permission flows; test current and minimum supported macOS on Apple Silicon and Intel; verify VoiceOver, keyboard navigation, Reduce Motion, Reduce Transparency and Increase Contrast; verify consequential tools wait for approval and no canceled/partial recording is submitted; document signing/notarization and distribution. Requested supported file opening runs directly. Configure the actual public GitHub repository and release/update policy before showing links or claiming distribution support.
