# Sotto roadmap

## New major expansion — active

The newest request establishes eight phases: reliability; everyday information; structured computer control; internet/browser; productivity utilities; isolated SDK/MCP; curated discovery/connection; routing/recovery. It supersedes the earlier search pause for future phase 4; no new search account, backend or paid service has been configured.

Current delivery: real Sotto-identity owned Calendar create/list/update, Reminders create/title-filtered list/complete, timer Notification Center scheduling/presence/removal and native read-only checks passed. Owned fixtures were cleaned up. Screen Recording is unavailable. The external AX fixture could not become foreground, and native control attached to an older running Sotto instance; no personal selection/window was manipulated or declared verified. Browser, playback, output-switch and Shortcut effects still need safe live fixtures.

Contacts search/get/create/update and just-in-time access are implemented. Account reads/saves remain unverified because Contacts permission is absent here. Sotto Notes list/search/read/create/update passed actual isolated persistence tests; this is not Apple Notes access. Apple Notes now has a separate public-Automation adapter with five tools and just-in-time access; real account operations remain unverified. Read-only Apple Mail accounts/search/read now use public Automation, scoped message references and bounded inbox/text results; live account acceptance remains pending. Mail writes/threading, messaging, contact aliases, broader UI actions/utilities, SDK/HelloSotto, MCP, marketplace and general task recovery remain unfinished.

Latest delivery: **372 tests, 24 skipped, zero failures**; macOS build and UI mechanical scan pass. Contacts writes use controlled adapters; local notes use real files; native observations used the actual Sotto identity. Evidence: acceptance/2026-11-17-native.json, acceptance/2026-11-17-windows.json and the November 18 Notes/Mail no-prompt permission reports.

Next: reviewable Mail drafts and deliberate conversation/thread handling; keep sending unavailable until exact recipient/body review and durable uncertain-send protection are implemented. Remaining live acceptance runs only with existing access and suitable owned fixtures.

See INTEGRATIONS.md, INTEGRATION-SDK.md and SECURITY.md. The older history below is retained as dated evidence, not certification of the entire expansion.

## Current delivery status — November 17, 2026

The original sections below retain core-development and acceptance history. The expanded tool inventory in [TOOLS.md](../TOOLS.md) is the current source for individual capabilities and evidence.

| Phase | Implemented now | Remaining |
|---|---|---|
| 1 · Everyday Mac | Files, apps, EventKit actions, persistent timer reconciliation/cancellation, Spotify and Core Audio adapters | Timer delivery, media/output changes and fresh/revoked permission acceptance across devices |
| 2 · Local context | AX windows/selection, approved capture/OCR, clipboard and automatic local document matching | Full-document/large-library coverage and physical accessibility acceptance |
| 3–4 · Web and media | Headless connected search, labeled Wikipedia fallback, in-pill pictures, publications, bounded fetch/download/PDF OCR | General-search expansion deferred at the user's request; arbitrary-publisher retrieval remains incomplete |
| 5 · Research | Bounded source collection, page/snippet provenance, citations, publisher diversity and explicit three-source comparisons | Independent-source evaluation and broader freshness/authority assessment |
| 6 · Productivity | Safe file management, Shortcuts, ordered native workflow editor, voice management, typed remembered names and durable reviewed recovery | Physical editor/recovery acceptance and verified external Shortcut effects |
| 7 · Intelligence | Automatic local English semantic/phrase matching, shared PDF/text/RTF/DOCX extraction, selection reasoning, capability browser and a permission-scoped foreground browser bridge | Physical browser/assistive-technology acceptance, extension/same-tab interaction, broader computer use and multilingual/large-library evaluation |

Workflow creation and editing now validate the entire ordered sequence before saving. Saving does not execute actions. Exact saved names such as “Start my study session” route locally to the runner; execution still requests review of the complete frozen sequence. Version checks prevent stale voice/editor changes overwriting newer saved routines. Per-step timeouts, cancellation, failure records, execution references and measured durations preserve partial evidence without automatic replay.

Remembered names now support installed apps and saved-workflow identities as well as files/folders, with reviewed changes and stale-edit protection. Workflow execution persists each dispatch marker and result locally. Explicit recovery approves only the remaining plan and never repeats completed actions. Unknown outcomes require user review and explicit skipping; skipped actions remain unverified. Nothing resumes automatically at startup.

The first browser bridge now identifies the foreground accessible HTTPS page, reads bounded static-text excerpts, finds text locally and opens actual returned links through the default browser. Approval freezes the source identity/address; a changed window/tab or expired reference refuses execution. Form controls and embedded frames are omitted, and subsequent tools require approval to prevent instructions embedded in a page from disclosing local/page data. Native source/link controls are included in the pill. This is implemented code with controlled safety coverage; actual Safari/Chrome/Edge/Brave page acceptance remains pending.

Latest validation: **340 tests, 24 skipped, zero failures**, with a successful macOS application build. No live web searches were enabled. Timer checks use real temporary persistence, the native absolute calendar-trigger API and controlled notification adapters for relaunch, permission delay/denial, expiry, scheduling/removal failures and cancellation races. Actual foreground banners, notification-center delivery, sleep/Focus and terminated-app delivery remain device acceptance work.

Timer maintenance now runs on launch, wake and app activation without permission prompts. It repairs missing future requests at their original deadlines, retains cancellation markers until notification removal is verified and never restarts elapsed timers. Active listings show real remaining time and distinguish recent elapsed/cancellation-pending records. Storage errors no longer silently reset timers.

Local document coverage now includes DOCX main-body text, bounded native RTF text and UTF-8/BOM-marked UTF-16 TXT/Markdown. Automatic indexing reuses the same extractors without new setup. Word layout, headers/footers/comments/images and linked resources are outside the read contract; RTF fields/images/embedded content are refused. After reading document content, further tool calls require approval so document instructions cannot silently disclose data or trigger actions. General web-search expansion remains on hold.

Next implementation priorities:

1. Improve local document handling and native capability reliability.
2. Expand supported document retrieval/research reliability and investigate an explicitly authorized browser extension for deeper same-tab interaction, independently of general-search expansion.
3. Complete the physical browser, assistive-technology, minimum-OS and distribution gates below. User-operated manual acceptance remains pending without repeated prompts.

General web-search expansion is on hold at the user's request. Existing search, image and publication adapters remain available. Do not provision hosting, introduce a project-operated search dependency or add search providers while this work is deferred. Sotto remains an open-source native app; any future search architecture needs a separate decision consistent with that distribution model.

## Working MVP

Native menu bar app, Liquid Glass/material interface, persisted Settings, push-to-talk and click/toggle modes, Send control, real microphone waveform, Apple Speech, direct OpenAI reasoning, bounded tool loop, trusted authorization, Spotify, Finder/Spotlight, applications, Reminders, Keychain, and GRDB history are implemented. Live Finder execution and model clarification were verified directly. The user has tested the voice flow, supplied reminder-creation/offline-failure screenshots, and reports the checklist working. Keep the individual evidence and limits in VALIDATION.md; this is not release certification.

The latest interaction pass adds typed follow-up questions, context-preserving replies, readable approvals, non-truncated results, and accurate distinctions between questions, information and confirmed actions. Reminder creation follows the user's preference: a clear request is sufficient authorization. Native OS consent still applies.

## v0.2: setup and reliability — implemented

- Optional, replayable native setup with real provider verification, explicit privacy choices, a voice-only transcription check, activation selection and a real first-command entry point.
- Permission status, explicit requests and targeted recovery links; contextual capsule recovery actions for voice/provider/privacy failures.
- Stable Core Audio UIDs, visible missing-device state, event-driven inventory/default-input monitoring and recording discard on route changes, engine reconfiguration or sleep.
- Asynchronous bounded Spotify helper, cancellation/timeout/output limits, play/pause state readback and a read-only connection checker in Settings.
- Backward-compatible settings migration and optional stable local development signing without committing personal identity data.

Physical unplug/reconnect during capture, fresh/revoked native permission flows and accessibility/minimum-OS validation remain release checks. Bluetooth-output acceptance is deferred in the current session because the user has no Bluetooth headphones available. Voice phase instrumentation is implemented; controlled physical-device performance benchmarks remain pending.

## v0.4: local reasoning — implemented

- Local Ollama adapter with native streaming chat/tool results, installed-model capability discovery and a shared native provider selector in Setup and Settings.
- Loopback-only destinations, no redirects/proxy credentials, cloud-tag rejection before sending transcript data, and the existing trusted tool authorization gate.
- Separate persisted model choices and context clearing when changing destinations. OpenAI credentials and consent are not required for local requests.
- Protocol/HTTP fixture tests plus a real Qwen3 1.7B agent loop that opened Downloads, consumed its confirmed result, and completed. See LOCAL-MODELS.md for runtime setup, boundaries and validation.

## Zero-configuration direction — implemented

Native commands run before model selection, without accounts, keys or external runtimes. New installations use Automatic for flexible requests: available on-device intelligence, then a local model. Guided connections preserve the waiting request; remote use remains explicit. Adaptive microphones and managed startup of an installed local engine reduce setup work. [ZERO-CONFIGURATION.md](ZERO-CONFIGURATION.md) records implementation and validation limits.

Calendar agenda reading follows this direction: “What’s on my calendar today/tomorrow?” needs only just-in-time macOS access. It reads a bounded date range and never changes events. Native dates handle daylight-saving transitions. The actual connection sheet and cancellation were inspected. A user-operated voice request for tomorrow's agenda now matches Calendar on this Mac, backed by native verified completion; fresh/revoked consent and other account configurations remain acceptance checks.

## Real-time voice — implemented, hardware acceptance ongoing

- Modern on-device SpeechAnalyzer/SpeechTranscriber on supported macOS 26+ configurations, explicit language preparation and streaming legacy fallback on the macOS 14 deployment floor.
- Confirmed/provisional capsule text, same-shortcut hold/double-tap and optional press-to-toggle, bounded finalization and cancellation.
- Inference-only preparation during stable pauses, invalidated by resumed/changed speech; all tools wait for explicit submission and confirmed transcription. Existing native routing and agent integrations retained.
- Optional OpenAI Realtime speech with separate raw-audio consent and Keychain credentials, independent of reasoning.
- 164 offline checks and a real synthetic on-device analyzer test pass. Native controls/start/cancel inspected. Cold-start latency, physical speech-to-action timings, minimum OS and Intel acceptance remain work. See [research and validation](REALTIME-VOICE.md).

## Core responsiveness and everyday-task history

Manual acceptance is paused at the user’s request. Continue implementation independently; remaining acceptance items stay pending without repeated test prompts.

- Speech startup now overlaps microphone capture with audio-format negotiation and analyzer preparation. Session checks prevent canceled/replaced startup and finalization from changing the next recording; cancellation stops a capture still waiting for its first buffer. Offline race regressions and synthetic analyzer validation are recorded in VALIDATION.md. A content-free, bounded multi-session report now distinguishes cancellation/recovery and transcription-only outcomes; Send timing includes release during startup. Modern backend initialization now returns a retryable error after eight seconds even if an Apple API ignores cancellation; permission dialogs remain outside that deadline. User-operated repeated hold/release Downloads commands and Escape-prevents-action now pass on this Mac, backed by four native verified completions and one canceled sample. One earlier clarification remains recorded separately. Physical double-tap hands-free now also passes: the user confirms waiting for Send and opening Downloads afterward, backed by the gesture latch and verified native result. Successful reactivation after Escape is established. Physical press-to-toggle also passes with user-confirmed second-press submission and restoration to Hold to talk, backed by native verified completion. A physical spoken-correction test failed (Downloads opened after correction to Documents); a bounded native correction route and reasoning regressions pass, and the user confirms the imperative retry works. A follow-up transcription screenshot exposed trailing “please” in polite folder questions; the shared courteous folder grammar passes exact regressions, and the physical retry now passes with user-confirmed direct Documents opening plus native verified completion. Early-recording cancellation now also passes with user-confirmed microphone stop and a verified next command; logs place Escape just after readiness, so strictly pending-startup and finalization interruption remain separate. Controlled cold-start and broader hardware benchmarks remain next, without continuous microphone capture. See [physical acceptance](PHYSICAL-ACCEPTANCE.md).

- Real Calendar account acceptance passed for native creation, exact read-back, duplicate-request reuse, agenda discovery in the same time slot and owned-test cleanup. Physical voice-to-agenda also passes with a user-confirmed Calendar comparison. Fresh/revoked consent, spoken event creation, and specific empty/all-day real-account cases remain acceptance checks.
- Calendar creation is implemented for personal timed events with explicit date/duration, writable default calendar checks, verified EventKit saves and bounded duplicate protection. A narrow today/tomorrow route works without reasoning. Actual account creation/read/retry/cleanup passed on this Mac with existing consent; invitations, recurrence, edits and deletion remain unavailable to the agent.
- Requested PDF/TXT/Markdown/RTF/DOCX text extraction is implemented, with bounded reads, actual-search/user-path enforcement and honest partial/no-text results. Real PDF extraction tests pass. Textless PDF pages now have bounded local Apple Vision OCR, with partial-read/recognition disclosures and generated-image PDF verification. End-to-end summaries with personally chosen documents remain an acceptance step; Pages/legacy Office formats and chunked full-document summaries remain work. See [DOCUMENTS.md](DOCUMENTS.md).
- Keep models, endpoints and tool diagnostics in Advanced. Bundled model lifecycle still needs pinned licensed artifacts, verified downloads, disk/memory checks and real reliability measurements before one-click installation.

## Later: provider expansion

- Add compatible endpoints only with explicit destination configuration and credential isolation.
- Implement Codex app-server only after the documented auth, versioning and restricted-tool bridge requirements in PROVIDERS.md are met. It must not bypass Sotto's native authorization policy.

## Later: context and integrations

Foreground application context, selected text, windows, explicit screen capture/OCR, Shortcuts and the narrowly authorized foreground browser bridge are implemented; their individual physical acceptance limits are tracked in TOOLS.md. Mail writes and complete threading, browser extension/session automation, unrestricted Notes editing, permitted Discord context and MCP remain future integrations.

## Requested system settings — implemented

Native routes and actual adapters support direct display/audio/network/Dock settings and scoped Accessibility interaction with System Settings controls. Sotto can also change its own supported preferences. Clear requests execute through trusted validation without a redundant Sotto approval; native macOS consent still applies. User feedback confirms the compound Low Power Mode/audio command works. Broader app automation remains limited to the registered window/selection/screen and reviewed Settings adapters; arbitrary app control is not available.

## Path to a finished first release

Result-accessibility hardening is implemented: explicit menu-bar Review response, VoiceOver/Switch Control countdown suppression, pointer/keyboard retention, stable native announcements, reduced-motion/transparency listening feedback and directly selectable file summaries. Native accessibility-tree and inert visual checks passed; actual assistive-technology use remains acceptance work below.

Universal production Release compilation now passes for arm64/x86_64 at the macOS 14 deployment floor. CI includes Release-policy tests and an unsigned universal Release compile. Neither the local unsigned build nor the CI recipe is a notarized/public release; official credentials and runtime acceptance are still required.

1. Complete physical acceptance of the existing core (current session: [PHYSICAL-ACCEPTANCE.md](PHYSICAL-ACCEPTANCE.md)): shortcut modes, Bluetooth output plus built-in input, cancellation, native tools, Calendar access/save/read-back and document summaries. Record actual outcomes rather than marking implementation as certification.
2. Test VoiceOver/display accessibility, minimum supported OS/Intel and multi-display behavior on the target hardware.
3. Supply the official release identity/notarization profile, publishable repository URL and update policy; run the two-version permission-preservation test and distribute signed/notarized artifacts.
4. Keep later integrations above separate from first-release completion. Accounts/OAuth, MCP hosting and automatic updating need their own real implementations and acceptance; the current app must not advertise them as ready.

## Release gates

Release tooling now requires explicit Developer ID credentials and checks old/new designated requirements before notarization and packaging. See RELEASING.md. The 15 release policy tests pass; actual signing/notarization and a two-version consent-preservation test still require the official certificate, notarization profile and release artifacts. Separate development/beta identifiers must be finalized before public distribution. No automatic updater is implemented. The current keychain has no Developer ID Application signing identity; development signing is not a distributable notarized release.

Use a stable signing identity; verify fresh-install and revoked-permission flows; test current and minimum supported macOS on Apple Silicon and Intel; verify VoiceOver, keyboard navigation, Reduce Motion, Reduce Transparency and Increase Contrast; verify consequential tools wait for approval and no canceled/partial recording is submitted; document signing/notarization and distribution. Requested supported file opening runs directly. Configure the actual public GitHub repository and release/update policy before showing links or claiming distribution support.
