# Changelog

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
