# Changelog

## Unreleased · read-only Apple Mail

- Add mail.accounts/search/read through the public Automation interface and accounts already configured in Apple Mail.
- Preserve the original request through native permission setup; bind reads to expiring references carrying actual account/native/RFC message IDs and metadata.
- Disclose inbox-only search limits, skipped results, text excerpts and unexpected read-status changes. Sending, drafting, archive and mark-read remain unavailable.
- Exercise actual date/Unicode AppleScript helpers and installed-dictionary compilation; cover identity/refusal/partial cases with controlled adapters. Real inbox acceptance remains pending.


## Unreleased · Apple Notes integration

- Add five separate appleNotes.* tools using public Automation, while preserving existing Sotto Notes and identifiers.
- Preserve the original request through native per-app permission setup; review actual destinations and complete final text before changes.
- Bind updates to current native content, refuse complex/locked/shared notes, escape text, and verify actual visible-text read-back with honest partial results.
- Pass private note data through an unlinked owner-only stdin descriptor; execute real transport timeout/cancellation tests and compile the reviewed script against the installed public dictionary. Real account operations remain unverified.


## Unreleased · local OCR for requested scanned PDFs

- Recognize textless PDF pages locally with Apple Vision, retaining embedded text where available and preserving page order.
- Bound OCR to five pages per read and 2,000 pixels per image edge, alongside the existing 20 MB/50-page/16,000-character limits. Disclose skipped/unreadable pages, recognition uncertainty and partial results.
- Cancel in-flight recognition and reject canceled output; preserve the existing user-path/search scope and tool authorization. Images/recognized bodies are not saved to activity history.
- Add generated image-only PDF recognition and limit/error/cancellation regressions. Manual acceptance remains paused.

## Unreleased · polite folder questions

- Handle “Could you open documents, please?” directly, including known-folder articles and polite wording inside self-corrections.
- Share anchored folder parsing; preserve clarification for unspecified documents, negations, conditions and unsupported additional work.
- Reproduce the screenshot's exact transcription in a runtime regression and keep imperative acceptance separate from the pending polite physical retry.

## Unreleased · honor corrected folder destinations

- Route explicit standard-folder self-corrections to only the final destination, including “Open Downloads—actually open Documents.” Match the complete bounded request; preserve additive commands and reject ambiguous/negated/unsupported revisions from the native route.
- Tell reasoning providers to exclude withdrawn intent from remaining work rather than executing it after the corrected action.
- Add runtime/parser regressions and a real on-device fixture regression. Record the reported physical failure separately; physical retest remains required after relaunch.

## Unreleased · bounded modern speech startup

- Return a retryable error after eight seconds of modern backend initialization even if an awaited Apple API ignores cancellation. Start the deadline after microphone consent.
- Invalidate the session immediately on timeout/cancellation and schedule cleanup without holding the caller behind framework teardown; ignore late results and protect newer recordings.
- Add five regressions for uncooperative startup, cancellation, already-canceled calls, success and original framework errors. Exercise successful real synthetic recognition through the deadline wrapper.

## Unreleased · repeatable physical voice measurements

- Add session-scoped, content-free phase/outcome log records and a bounded JSON report for repeated physical voice checks. Exclude test processes, partial-window sessions and late callbacks from completed results.
- Include the remaining startup wait in Send-to-final timings when the shortcut is released early.
- Keep transcription checks, cancellations, failures, input recovery and verified actions distinct; document a repeatable physical protocol and add report checks to CI.

## Unreleased · speech startup cancellation and overlap

- Start microphone capture alongside audio-format negotiation as well as analyzer preparation, after explicit activation and native permission.
- Reject canceled/replaced sessions after asynchronous locale, format, analyzer and capture startup; keep old result readers and finalization scoped to their own recording.
- Stop pending first-buffer capture when its startup task is canceled. Include locale resolution in the existing startup deadline and clean up unsupported locales.
- Add offline regressions for canceling a suspended locale lookup and replacing it with a new recording.

## Unreleased · real Calendar acceptance and production build coverage

- Verify actual native Calendar creation, read-back, duplicate reuse, production agenda lookup and cleanup against the current authorized account, with visible native results and no leftover test event.
- Add an explicit Debug-only account acceptance entry point; it never prompts for access, invokes intelligence or exposes event removal to the agent.
- Cross-compile the production Release app for Apple Silicon/Intel, verify deployment/resources and exclude Debug test flags.
- Add release-policy and unsigned universal Release checks to CI. Official signing/notarization and hardware acceptance remain separate gates.

## Unreleased · accessible results and document actions

- Add a visible Summarize action to supported PDF/TXT/Markdown file results, keeping exact cached-path checks and preserving the request if intelligence setup is needed. Unsupported formats retain Open/Show in Finder only.
- Measure actual result-list content instead of allocating empty row space. Preserve the bounded, upward-growing glass capsule.
- Pause short-result dismissal while hovered or keyboard-focused; suppress it for VoiceOver/Switch Control, including when assistive reading starts during the countdown. Existing privacy/context expiry remains unchanged.
- Announce stable outcomes and required decisions through native accessibility notifications without speaking every waveform/partial-text change. Add status heading semantics and file-location values.
- Honor Reduce Motion/Reduce Transparency by replacing animated listening glow with a simple actual-input level meter, and hide the countdown ring under Reduce Motion.
- Add explicit menu-bar Review response for keyboard access without changing ordinary nonactivating voice behavior. Add an inert Debug file-result fixture for visual/accessibility review.

## Unreleased · Calendar creation and document reading

- Add verified personal Calendar events in the default writable calendar, requiring explicit start/end and existing native Calendar access. Clear requests run directly; invitations, recurrence, edits and deletion stay unavailable.
- Add a fast native today/tomorrow event grammar with an explicit AM/PM time and duration. Preserve title case; ambiguous or nonexistent daylight-saving times fall back to reasoning/clarification.
- Guard repeated and uncertain saves against duplicate retries for 15 minutes within the app session. Return real identifier/title/time read-back evidence.
- Extract requested PDF/TXT/Markdown text locally with 20 MB/50-page/16,000-character bounds and explicit truncation. Scans, locked PDFs and unsupported formats report real limitations.
- Enforce document paths from actual current-request search results or the user's literal path in trusted runtime code; model-invented paths cannot read content. Apple reasoning receives a disclosed 2,500-character excerpt to fit its context.
- Update Calendar permission copy and capability discovery, preserving the existing native connection flow and glass UI.

## Unreleased · response latency

- Shorten Apple on-device planning and generate conversational text only when a reply is needed, rather than before tool parameters.
- Supply capability descriptions for tool selection and the selected tool's typed argument schema afterward. Preserve compound-task instructions, recall, validation and trusted authorization.
- Deterministic native requests bypass pending speculative inference. Start microphone capture alongside analyzer preparation, with the same bounded stream and explicit-activation/cancellation rules.
- Add Send-to-first-action, Send-to-verified-completion and final-transcript-to-first-action diagnostics, plus content-free Apple selection/argument timing logs.
- Real on-device action/conversation/recall checks and synthetic streaming recognition pass. See VALIDATION.md for measurements and limits; model-driven commands still take time.

## Unreleased · real-time voice

- Prefer progressive on-device SpeechAnalyzer/SpeechTranscriber on supported macOS 26+ configurations, with explicit system language preparation and existing streaming fallback for the macOS 14 deployment floor.
- Display confirmed and revisable speech separately in the existing glass capsule; drain/finalize input before submitting and discard incomplete speech on failure or timeout.
- Add same-shortcut press-to-toggle without changing default hold/release or double-tap/manual Send. Preserve legacy preference migration.
- Prepare inference during stable pauses without authorizing/executing tools. Invalidate drafts on resumed/changed speech, context/provider changes, expiry and cancellation; deterministic native commands wait for final text and avoid inference.
- Instrument startup, first partial, finalization, first action and verified completion. Add cancellation and stale-status guards; retain bounded microphone recovery and cleanup.
- Offer optional OpenAI Realtime transcription with a Keychain key and separate audio consent, independent of reasoning. Apple Speech remains the default.
- 164 offline tests and the real synthetic on-device streaming test pass; signed app build and strict signature verification pass. Cold-start improvement and controlled physical voice-to-action benchmarks remain outstanding. See REALTIME-VOICE.md.

## Unreleased · open GIF files

- Add GIF to supported native file formats, including uppercase extensions.
- Generate advertised file-format support from the same list used by FilePolicy, so providers do not invent different limitations.
- Clarify that opening a supported file uses action open; revealing its location does not complete an open request. Prior assistant claims do not override current tool capabilities.

## Unreleased · actionable file search

- Search for named files natively and show ranked Open/Show in Finder choices instead of an unnecessary clarification.
- Match résumé/CV variants, retain cloud documents and filter technical noise; preserve explicit latest-PDF recency.
- Add bounded filename-only folder fallback when indexed results are empty, preserving OS file access and cancellation.
- Keep result paths in memory and submit only exact cached selections through the native tool/runtime. 142 offline checks and a live local search passed; permission-dependent signed-app acceptance remains manual.

## Unreleased · capsule containment and direct actions

- Keep the voice capsule bottom-anchored inside the display’s usable frame; grow upward, constrain width/height and scroll overflow.
- Remove automatic intrinsic window resizing, measure natural content explicitly, and recalculate placement when display configuration changes.
- Run requested document opening, file revealing and application launching without redundant Sotto approval; preserve schema validation and blocked script/installer types.
- 134 offline tests pass, including actual native-host growth and file-policy checks; inspect the complete capsule/footer in a non-executing visual fixture.

## Unreleased · native Calendar agenda

- Correct missing Calendar Hardened Runtime entitlement that prevented macOS from showing the authorization prompt. Include it in the reviewed release policy and packaging regression checks.
- Distinguish permission refusal, blocked requests and System Settings recovery from user cancellation; accept access granted while a connection sheet is open.

- Read today/tomorrow’s agenda without an account, model or runtime. Calculate date boundaries with the local calendar, including daylight saving.
- Ask for Calendar access only when needed, preserve the pending request, and discard it on cancellation/timeout. Explain macOS full access while exposing no event-writing tools.
- Return bounded, sorted title/time/all-day results with honest empty/truncated states; keep agendas readable and store only counts/ranges in activity history.
- Add seven focused checks; 128 offline tests pass, eight opt-in tests skipped. Native connection/cancel UI inspected; personal-calendar and voice acceptance remain manual.

## Unreleased · distribution safeguards

- Add explicit Developer ID archive/export, notarization and stapled-package workflow with no development/ad-hoc fallback.
- Gate updates on bidirectional designated-requirement compatibility, stable bundle/team identity, reviewed entitlements and increasing build numbers.
- Add 14 release policy tests and document the required two-version permission-preservation test. Actual distribution signing/notarization still requires release credentials.

## 0.4.0

- Add local Ollama reasoning with native streamed tool calls, result history and model-capability discovery.
- Share native provider configuration between Settings and Setup; persist local/OpenAI choices separately and clear in-memory context when changing providers/models.
- Enforce loopback-only destinations, cloud-model rejection, no redirects or OpenAI credential forwarding, bounded stream decoding and cancellation before tool execution.
- 87 offline tests pass; real Qwen3 1.7B inference opened Downloads through the native agent/tool loop and passed request cancellation.

## 0.3.3

- Make the microphone-only test distinct from normal command capture in Setup.
- Add Run command to successful voice-check results, using the real recognized transcript and existing consent/tool authorization path.
- Replace the sticky Check again action with Speak a command, which returns to normal agent capture.
- Allow trying a command with an existing saved key without requiring a fresh model-catalog verification every launch.

## 0.3.2

- Validate the actual input device/format instead of discarding every engine configuration notification.
- Ignore unchanged running input, bound same-input restarts, and allow startup-only format settling before audio is accepted.
- Mark microphone readiness on the first audio buffer; preserve cancellation and real mid-recording input-change protection.
- 73 offline Swift tests pass. The selected built-in microphone delivered real audio after a benign startup notification was ignored.

## 0.3.1

- Move audio engine and recognizer startup/teardown off MainActor; cancellation immediately invalidates per-session audio/results.
- Measure double-taps from physical event timestamps, use the system double-click interval, and ignore modifier-key echoes.
- Order the prepared capsule at full opacity before deferred layout; remove listening entrance animation and repeated microphone inventory scans.
- Add separate local latency diagnostics. 65 offline Swift tests pass; physical Fn acceptance remains with the user.

## 0.3.0

- One native shortcut recorder shared by General and Setup; supports custom combinations and modifier-only activation, including Fn where delivered by macOS.
- Hold to listen/release to send by default; double-tap keeps the same recording active until manual Send or Esc.
- Preserve legacy chosen keys, retire toggle-to-talk, suspend global activation during shortcut editing, and discard recordings at the safety limit.
- 60 offline Swift tests pass; native control inspected. Physical gesture acceptance is handed to the user.

## 0.2.3

- Validate the keyboard event mask and enabled state instead of treating any event-tap port as a working shortcut.
- Distinguish unavailable access for the current app copy from first-time authorization and shortcut registration failure.
- Add native restart and Finder recovery actions for an enabled System Settings entry that does not authorize the running copy.
- 50 passing offline checks, including stripped keyboard events and mismatched permission/registration states.

## 0.2.2

- Restrict Settings window dragging to native chrome and make decorative material views ignore clicks.
- Configure window chrome once per attachment; restore Settings explicitly when reopened after minimization.
- Add minimize/restore lifecycle diagnostics and window interaction regressions.
- 46 passing offline checks; live Settings audit and exclusions recorded in SETTINGS-TEST-MATRIX.md.

## 0.2.1

- Move Keychain work off the UI thread; inspect saved-key metadata without prompting at startup.
- Isolate provider verification state with cancellation and stale-result protection.
- Keep the menu-bar utility alive after its last window closes and prevent automatic background termination.
- Add credential-free lifecycle diagnostics and accessible verification status.
- 44 passing offline checks; repeated verification with the saved key succeeded in the native app.

## 0.2.0

- Optional guided setup, provider verification, explicit processing choices and transcription-only voice check.
- Permission status, native request/recovery actions and contextual capsule recovery buttons.
- Stable microphone identity, reconnect-aware selection and event-driven capture interruption handling.
- Nonblocking Spotify helper with bounded output, timeout, cancellation, playback-state verification and a read-only connection checker.
- Compatible preference migration and automatic local development signing when one suitable identity exists.
- 38 passing checks on the development Mac, plus native provider/Spotify connection checks. Physical reconnect, permission-reset, accessibility and cross-platform release checks remain documented in VALIDATION.md.

## 0.1.0

- Native menu bar agent, glass/material UI, click/toggle/hold voice input, Apple Speech, direct OpenAI reasoning, typed tools, native integrations, trusted approvals, Keychain and local activity history.
- Follow-up questions, readable approvals, complete result text, and the user's automatic-reminder preference.
