# Validation record

## Real-time speech · November 15–16, 2026

This entry supersedes older voice/backend and file-approval descriptions below; earlier entries remain historical evidence. Deployment stays macOS 14, built with Xcode 27/Swift 6.4 on Apple Silicon/macOS 27.

Audited existing streaming SFSpeechRecognizer and Atticus at pinned commit `cee9340d5076d275ac90d321675f5ab0d89d3518`. Added modern on-device progressive SpeechAnalyzer/SpeechTranscriber when installed/supported, confirmed/provisional range handling, explicit asset preparation, same-shortcut press-to-toggle, safe pause-time reasoning preparation and end-to-end phase instrumentation. The existing glass panel, native routes, agent authorization and real integrations remain in use. Preparation never executes tools; explicit submission plus confirmed transcription is required for native and model-generated actions alike.

- Final `swift test`: **175 discovered, 164 passed, 11 opt-in skipped, zero failures**. Preparation tests use actual AgentRuntime with probe providers/tools to verify no early execution, trusted approval, cached first-turn reuse, rejection after final-word/context/provider/age changes, acoustic pause invalidation, native fast routing, toggle events, setting migration/round trip and timing calculations. No OS permissions are granted by these tests.
- `SOTTO_MODERN_SPEECH_TEST=1 swift test --filter LiveModernSpeechTests`: passed against the real installed Apple analyzer. Synthetic speech delivered provisional words while input was still open, then confirmed final words after closing input. Observed **1,403.8 ms analysis-start-to-first-partial**, **26.9 ms input-end-to-final**. Injected PCM avoids the microphone; no cloud or tools. This is not a physical speech benchmark.
- The optional OpenAI Realtime adapter also passed its explicit synthetic-speech API round trip using the existing Keychain credential (about 3.0 seconds total in that earlier run). It uses separate audio consent, not a ChatGPT subscription. No personal audio or command was sent in that test. Offline protocol tests cover cancellation, limits, item matching and incomplete/error responses.
- `Scripts/build.sh`: signed Debug build succeeded. Deep/strict signature verification passed. Inspected native General/Voice, preserved the user's chosen shortcut and Apple Speech backend, and explicitly prepared the signed app's system language assets. The actual status became **Live on-device transcription is ready**. Transcription-only capture and Escape returned to an idle microphone state; no tool ran during this UI check.
- Actual app timing logs include a **6,226.6 ms cold startup**, **218.8 ms subsequent startup**, and **83.8 ms input-end-to-final**. These were not a controlled voice trial; microphone/model startup still needs optimization. No full voice-to-agent first-action/completion measurement, CPU/memory benchmark, physical shortcut acceptance, minimum-OS/Intel or accessibility certification is claimed.
- The final small change guards language-preparation UI against canceled/stale status results. Build and offline suite were rerun afterward. The computer-use service later timed out while rebinding the app; no optional cloud selection or consent change was made during that attempted inspection.

See [pipeline/research/manual checklist](REALTIME-VOICE.md) and [optional cloud speech](REALTIME-TRANSCRIPTION.md). Physical speech, corrections during pauses, all shortcut gestures, route changes and real tool completion remain the next acceptance pass. There is no wake word, silence submission, automatic follow-up microphone reopening or external speech application dependency.

## GIF opening correction · November 15, 2026

The user clarified that “open a GIF” only revealed its location. GIF was missing from FilePolicy’s extension allowlist. Added GIF (case-insensitive), extracted the supported extensions into a shared source used by both enforcement and the model-visible tool description, and clarified that reveal is not completion of an open request. No speech-recognition substitutions were made: the reported issue was action selection/file support, not misheard PDF/PNG.

143 offline Swift tests passed, nine opt-in tests skipped (152 discovered); Debug build and deep/strict signature verification passed. The file-policy regression accepts actual temporary .gif and .GIF paths while retaining script/installer rejection. A new check verifies advertised support stays aligned with the allowed formats. No personal GIF was opened during this pass; native default-app handling uses the existing NSWorkspace open adapter. Restarted the normal app to load the fix and discard the old in-memory capability claim.

## Display-safe capsule and requested file actions · November 15, 2026

The user’s screenshot showed an approval capsule below the display edge and a redundant approval for opening Settings.app. Window sizing now follows explicit natural SwiftUI content measurements instead of automatic intrinsic resizing. The outer viewport is capped to the selected display’s visible frame with a 14-point window inset and additional shadow padding. The bottom stays fixed as content grows upward; oversized content scrolls. Display configuration changes recompute width/height constraints and reselect an available monitor when necessary. AppKit logical coordinates handle display scaling without manual pixel conversion.

Requested file opening/revealing now runs directly through the existing gate and native adapter. Application bundles, including System Settings.app, can open through the file adapter; supported document/media checks remain, and script/installer types remain blocked. Runtime instructions no longer ask for an extra file-opening confirmation. The generic consequential-action gate remains intact; OS permission prompts remain independent.

Validation: 134 offline Swift tests passed, eight opt-in tests skipped (142 discovered), zero failures. Four placement tests cover large/small displays, negative/multiple-monitor coordinates, screen/Dock-bound changes, invalid measurements and actual SwiftUI/NSPanel growth with a fixed bottom edge. A new file-policy test checks supported document/app paths and rejects command/script/installer files without opening anything. Updated authorization tests verify no redundant file/reveal approval and continued schema rejection; existing consequential-gate tests still pass. Signed Debug build and deep/strict verification passed.

Inspected a deliberately inert approval fixture in the actual application. The complete text and footer controls were visible inside the glass shell. This preview performs no action and is not a live approval request; the app was returned to normal command mode afterward. No microphone capture, personal file opening or model call was used for visual review. Physical external-monitor disconnection and real resolution/Dock changes remain manual checks; geometry tests are not claims of those hardware interactions.

## v0.4.0 local reasoning · November 15, 2026

Installed Homebrew Ollama 0.40.16 and Qwen3 1.7B (approximately 1.4 GB model download) with explicit user approval. Started one loopback-only server with OLLAMA_NO_CLOUD=1; no Homebrew service or login item was registered. The model's actual metadata advertises completion, tools and thinking. Its default thinking behavior is preserved. The weights are separate from Sotto's distribution and carry their own Apache-2.0 license.

Implemented native Ollama streaming, tool/result history, capability discovery, local provider settings and backend-specific consent/configuration. Loopback URL validation, cloud metadata checks before inference, redirect refusal, isolated credential-free transport and trusted tool authorization apply independently of model instructions. Changing destination cancels active work and clears the conversation; no automatic remote fallback exists.

Validation:

- 87 offline Swift tests passed, zero failures; four opt-in live tests skipped (91 discovered). New protocol and loopback HTTP tests cover invalid destinations, capability/cloud gating before transcript transmission, redirects, absent authorization headers, real NDJSON decoding, incomplete responses, tool-result roles, duplicate/malformed calls, preferences migration, cancellation and stale discovery.
- Both opt-in live Ollama tests passed against the real server/model. The model selected the actual Finder folder tool, opened Downloads, consumed its confirmed result and completed a second reasoning round (7.300 seconds for the test on this machine). Cancellation completed in 0.156 seconds. These are individual observed test durations, not performance guarantees or physical speech timings. The tests do not read an OpenAI key.
- The development-signed v0.4.0 application built successfully and passed strict code-signature verification. Launched one normal command-enabled app through LaunchServices.
- In native AI Providers, selecting Ollama and clicking Connect & refresh models discovered and selected qwen3:1.7b and displayed Connected. Setup shared the same selection, reported four areas ready and enabled Try a voice command. Privacy showed the local reasoning destination and independent Apple Speech disclosure. Restored OpenAI with gpt-4.1-mini; its saved Keychain credential remained present. The local model choice remains saved for later use.
- No user speech sample was supplied during this pass. The existing voice pipeline and the new real local model/tool path were checked separately; a physical voice-to-Ollama acceptance pass remains manual. Small-model argument quality is a limitation: malformed or incorrect choices produce actual tool errors, never mocked success. Minimum-OS/Intel, accessibility settings and official distribution gates remain outstanding.

See [local setup and contributor notes](LOCAL-MODELS.md). The server remains running for user testing but is not configured to restart at login.

November 15, 2026 · Apple Silicon · macOS 27.0.1 · Xcode 27.0 · Swift 6.4 · deployment target macOS 14.

## Automated results

`SOTTO_LIVE_TESTS=1 swift test`: **15 tests passed, 0 failures**. Fourteen deterministic tests cover JSON round trips; schema rejection of unknown/missing/wrongly typed arguments; unknown tools; malformed calls; provider HTTP failure and conservative capabilities; real runtime events/result forwarding; invalid arguments preventing execution; failed tools never emitting successful results; approval before side effects; denial; cancellation during pending approval; disconnected-provider propagation; SQLite persistence/deletion; allowed/rejected state transitions and cancellation.

One opt-in integration test used a real OpenAI API key from Sotto's Keychain entry and the real native folder tool. The model interpreted “Open my Downloads folder,” emitted a structured call, the adapter opened the folder using NSWorkspace, returned an actual result, and the provider consumed the result. **Passed.** This validates the provider → agent → native integration vertical slice without mocked success. It does not include microphone input.

Run `swift test` for offline deterministic tests (the live test skips). Run `SOTTO_LIVE_TESTS=1 swift test --filter LiveTests` to opt into API usage and opening Downloads. Never put an API key in source or test logs.

## Native app observations

- Xcode app bundle build succeeded with ad-hoc signing. No paid developer identity was required for the local build. The toolchain notes that hardened runtime is disabled for ad-hoc signing.
- Launched the app bundle and inspected native Settings through the accessibility tree and screenshot. General and Voice sections rendered, the sidebar navigated, microphone/language controls were exposed, and the global shortcut reported Ready.
- Subsequent computer-use checks timed out, so no microphone input, speech transcription, or capsule animation is claimed as visually verified.
- A one-second process sample after launch found the main thread waiting in the AppKit event loop, with an 18 MiB physical footprint at that instant. This is a single debug-build observation, not a performance benchmark or idle CPU guarantee.
- Spotify's locally installed scripting dictionary was inspected to confirm the implemented playback commands/state fields. No Spotify playback change was performed during verification.
- The user-supplied API key was stored in Sotto's Keychain service. The app still requires explicit remote-processing consent in Privacy before voice requests are sent.

## Acceptance checklist

| Test | Status |
| --- | --- |
| A: hold, say Pause Spotify, release, playback stops | User reports the checklist working; individual Spotify playback states have not been independently observed |
| B: voice Open Downloads | Live reasoning → Finder opening passed; user reports the voice checklist working |
| C: create tomorrow 5 PM reminder | User screenshots show successful voice → EventKit creation; user confirmed the automatic-creation update works |
| D: Esc discards audio | User reports checklist working; explicit cancellation/discard regression capture remains a release check |
| E: approval blocks side effects | Gate tests passed; user screenshots showed the earlier reminder approval UI. File-open approval is now the relevant consequential-action release test |
| F: provider disconnected | Passed in offline tests; user supplied the live offline-error screenshot and confirmed expected failure handling |

## Manual release check

1. Open the built Sotto app. Set the API key, connection check, and explicit Privacy consent. Grant microphone/speech permission when invoking Voice. Test on-device speech availability; do not automatically downgrade to remote speech.
2. Invoke Control–Option–Space from another app; observe that the capsule does not take focus. Speak then release. Confirm actual waveform levels and final transcript. Try toggle-to-talk, alternate shortcuts, Escape during capture, Escape during recognition and Escape during a model response.
3. Start Spotify with a track. Ask Pause Spotify and approve the native Automation prompt yourself. Verify the player stops. Repeat next/previous/current/play; test missing/not-running Spotify handling.
4. Ask to create a specifically named test reminder tomorrow at 5 PM. Grant native Reminders access if needed. Verify it creates directly without an extra Sotto approval, and check title/date/alarm in Reminders. Test approval blocking separately with open_file: deny opening a known document and verify it does not open. Remove test data yourself afterward.
5. Search for a known indexed document, check ambiguity, deny/approve its opening. Verify files outside macOS authorization fail honestly.
6. Disconnect the provider; invoke a request and verify the capsule reports authentication failure. Test network loss midstream and step limits. Reconnect explicitly.
7. Check history retention, disabled writes, deletion, launch-at-login status, notification denial, sound toggle, device removal, appearance, Reduce Motion, keyboard navigation and VoiceOver. Actual VoiceOver listening is not yet verified.
8. Test with a stable Developer ID signing identity on both minimum supported macOS and current macOS, Intel and Apple Silicon. Notarization, automatic updates, and release packaging remain outstanding.

## Known limits

As of v0.2, fixed Spotify Apple Events run in a bounded helper outside the UI thread. Cancellation can terminate the helper but cannot retract already delivered events. Native actions already submitted cannot be rolled back by cancellation. Spotlight searches indexed home-directory filenames only, with newest-first ordering, an eight-second timeout and a 20-result cap. As of v0.2, microphone UIDs survive device renumbering; upgrading old numeric selections requires one explicit reselection. Physical disconnect/reconnect during capture remains a manual release test. Native OS permissions and model capability support are conservative, not universal. Other provider types, screen/AX context capture and future integrations remain unavailable and are labeled as such in Settings.

## Liquid Glass refinement · November 15, 2026

- App bundle rebuild succeeded with Xcode 27 and the macOS 27 SDK. Deployment stays macOS 14; the source now needs Xcode 26+ to compile the availability-gated Liquid Glass APIs.
- Re-ran offline tests: 14 passed, 0 failures; the single opt-in live provider test skipped. No API request was made for this visual refinement.
- Inspected actual Settings in system/dark and light appearances, then restored System. Confirmed aligned preference controls, monochrome native sidebar, material groups and corrected chrome background.
- Inspected the actual idle nonactivating voice panel: native glass shell, edge rendering, soft offset shadow, and native glass close control. The Debug-only `--show-capsule` launch flag shows idle UI without recording or provider work. Listening/transcribing/execution animations were not live audio tested in this pass.
- Directly launching the bundle's executable from the coding terminal produced TCC usage-description crashes attributed to the parent app. Launching the complete `.app` through LaunchServices resolved the verification launch issue. Always use Xcode Run or `open`, not the raw executable, for permission-sensitive tests.
- macOS 14–15 fallback rendering, actual Reduce Transparency/Increase Contrast/Reduce Motion settings, and VoiceOver remain manual runtime checks; code explicitly accommodates them.

## Listen-button crash fix · November 15, 2026

The 13:01 and 13:04 crash reports identified `_dispatch_assert_queue_fail` in the Speech authorization callback, not a missing usage description or headset problem. The legacy callback inherited MainActor isolation but was invoked on a background queue. SpeechAuthorization now creates explicitly Sendable callbacks outside MainActor and resumes a checked continuation. The EventKit fetch callback was also made explicitly Sendable to avoid the same legacy callback inference.

Rebuilt the app bundle successfully. Offline suite: 16 passed, 0 failures; one live API test skipped (17 discovered). Two new tests deliver authorization, denial and restriction from background queues into MainActor callers without requesting actual OS permissions.

Launched through LaunchServices. During verification the user activated listening; the native accessibility tree showed Listening, the microphone-level element, and a live recognized word. The app stayed open through speech authorization and live recognition. This verifies the crash fix and initial live transcription; final transcription submission and action execution remain separate acceptance checks. User shortcut/device preferences were preserved, and the active recording was not interrupted by verification.

## Click-to-talk send control · November 15, 2026

Added a visible Send action to the listening capsule, using the same stop/finalize path as shortcut release. The app snapshots whether recording began from a button, held shortcut, or toggle shortcut; button recordings now say “Click Send when finished,” and unrelated shortcut release cannot end them. Settings changes its Start listening action to Send recording during capture. Hold-to-talk and toggle shortcuts retain their respective completion behavior; the capsule Send action works in all modes, including while microphone startup is pending.

App rebuild passed and the 16 offline tests passed (one live API test skipped). Relaunched the app while preserving the user's toggle-to-talk and shortcut settings. The user was interacting with the app during UI verification, so no test recording was submitted or interrupted; a full manual Send → action check remains to be performed by the user.

## Reminder authorization preference · November 15, 2026

The user's screenshots showed the real reminder flow progressing through clarification, approval, and successful EventKit creation for “Review my notes,” November 16 at 5 PM America/Chicago. The user then explicitly requested removal of the second approval for a reminder they asked Sotto to create.

Updated only create_reminder to the trusted reversible-action classification. Schema validation, EventKit authorization, cancellation checks, actual save/readback verification and activity reporting remain active. The compiled application determines authorization; no model-supplied approval flag is trusted. File opening remains consequential and still requires approval. Provider instructions now use the local timezone by default and avoid reconfirming unambiguous reminder details.

Validation: app bundle build succeeded; 18 offline tests passed, one live API test skipped (19 total). New regression checks prove the actual registered reminder tool passes the gate without a second approval, invalid reminder arguments still fail validation, and the actual file-opening tool still requires approval and honors denial. No additional live reminder was created during this policy test. Automatic creation with live speech remains a follow-up acceptance check for the updated build.


## MVP interaction hardening · November 15, 2026

- Clarifications now have a typed ask_user control tool and explicit awaitingInput state. The runtime stops at the question with no success event, preserves a completed call/result pair, and resumes with the user's reply in the same context. Informational responses use a separate responded state, without a completion checkmark.
- Remaining consequential approvals use readable action names and labeled original values instead of serialized JSON. This changes presentation only; immutable arguments and the trusted gate are unchanged. Requested reminders still run directly.
- Confirmations use the short Done title and show full tool evidence in the body. Longer text can scroll instead of being truncated. Long results remain visible until dismissal or inactivity expiry; short confirmations dismiss automatically. The panel observes intrinsic content-size changes to fit measured text.
- Follow-up context survives active reply recording and expires after inactivity, with the capsule dismissed when its context expires.
- 22 offline tests passed, 0 failures (two opt-in live tests skipped, 24 discovered). The new tests prove a question performs no native action, a reply retains the original request and executes once, blank questions fail, question/response states differ from completion, and readable approval fields preserve the exact arguments.
- A separate live OpenAI test passed: the model selected ask_user, the runtime paused without native actions, and a follow-up cancellation completed without another question. The earlier live Downloads test remains valid; it was not rerun for this change.
- Visually inspected approval, question, and long-completion capsule states using Debug-only interface fixtures. They are labeled as previews, disable their controls and global recording shortcut, and execute no native action, microphone capture or inference. The app was returned to normal mode after review.
- User reports the core test checklist working and provided offline-failure and reminder-creation evidence. Stable Developer ID signing, minimum-OS/Intel execution, accessibility display settings, VoiceOver, and dedicated file-approval/cancellation checks remain release gates.


## v0.2 setup and reliability · November 15, 2026

Implementation:

- Added optional native Setup, replayable from the menu bar/sidebar. It verifies the saved provider/model, records explicit privacy choices, requests microphone/speech access only on user action, offers a transcription-only check, treats global keyboard permission as optional, and provides a real first-command action. Completion/skip flags persist.
- PermissionCenter exposes actual native voice/Reminders status, conservatively labels keyboard access, and treats Automation as system-managed rather than assuming it is granted. Denied/restricted permissions open targeted settings instead of repeatedly prompting. Capsule recovery actions identify the relevant permission or settings section.
- Added stable microphone UIDs and backwards-compatible settings decoding. Legacy pinned numeric IDs require a one-time choice to avoid trusting a possibly reassigned device ID. Other preferences remain intact. Missing inputs do not silently fall back. Hardware/default-input listeners, engine reconfiguration and sleep invalidate active capture and discard audio; callbacks are removed on shutdown.
- Moved Spotify from synchronous NSAppleScript on MainActor to an internal fixed-script osascript transport on a serial queue. The model can select only the playback-action enum. The helper has a 30-second outer timeout, 20-second Apple Event timeout, a 64 KiB bound per output stream, cancellable process lifetime and force-termination fallback. Play/pause state is verified. No unrestricted shell/script tool exists.
- Added a read-only Spotify connection check that does not use OpenAI or change playback, with cancellation and honest failure feedback.
- Build script now uses one existing local Apple Development identity when unambiguous, derives the team from public certificate metadata, and falls back to ad-hoc when unavailable. No account details or private keys are committed. v0.2 development-signed bundle built with hardened runtime and passed deep/strict signature verification.

Validation:

- 38 checks passed, zero failures; two opt-in live API tests skipped (40 total). New tests cover UID renumbering/duplicate names/missing inputs, legacy/default migration and preference round trips, setup gating and optional keyboard access, permission prompt eligibility, actual helper output/errors/timeouts/cancellation/output limits and verified Spotify results. A real Core Audio inventory/listener lifecycle test passed on this Mac. No helper processes were left running after the tests.
- Inspected the actual Setup and Permissions screens. Verified the saved OpenAI connection through the native Setup button; it reported the selected model connected. The microphone/first-command controls correctly stayed disabled while required access/input selection was missing.
- The native Spotify connection button read the real current playback state/track through the new helper while leaving playback unchanged. This check did not call the reasoning provider.
- Did not grant/revoke OS permissions, change the selected physical microphone, simulate sleep, or unplug hardware during verification. The new voice-check/route-discard flows still need a physical end-to-end pass after the user selects their microphone and grants any permissions requested for the new signing identity. These are explicit manual checks, not claimed passes.
- Existing keys, privacy choices, shortcuts, language, appearance and history were retained. The old pinned microphone appeared as “Choose microphone again,” as designed. Developer-signing identity stability across subsequent user-authorized permission grants remains a manual check; signing is not notarized release distribution.

## v0.2.1 key-verification reliability · November 15, 2026

The user reported that Verify quit the app and removed its menu-bar icon. No new macOS crash report was available during diagnosis; the observed process was alive, its main thread was idle, its Settings window was on screen, and its earlier model-catalog request had returned HTTP 200. The original termination mechanism was not independently established, so the old speech-permission crash reports were not treated as evidence for this report.

Removed two hazards in this path. Keychain reads/writes now use a serialized background worker, with a metadata-only, noninteractive startup check instead of reading the secret on MainActor. Verification state now belongs to a dedicated MainActor controller independent of view lifetime. It supports cancellation and operation IDs, suppresses stale Keychain/network/inspection results, handles credential removal and authentication failure, and keeps errors in Settings. Security operations already inside an OS authorization dialog cannot be forcibly interrupted, but they no longer block the UI and canceled results cannot start inference or overwrite newer state.

The app now explicitly declines termination after its last window closes and disables automatic background termination for its menu-bar lifetime. Added local lifecycle and verification-phase logs containing no credentials, transcripts or raw provider responses. Verification buttons retain stable labels and expose a dedicated accessible status element.

Validation: development-signed v0.2.1 built and passed signature verification. 44 offline checks passed, zero failures; two opt-in API tests skipped (46 total). New tests cover success/authentication failure without termination, background Keychain work, cancellation during blocked credential access, old network results after a newer verification, disconnect during verification, and late startup metadata after failure. These tests use fixture credentials and do not modify the user's Keychain.

After rebuilding, used the actual saved key in native Setup. Two verification attempts completed with Connected for the selected model, the UI remained accessible, and Sotto stayed in the same running process. Closed Settings and confirmed that the app remained alive and could show Settings again with its connected state preserved. The exact original user-reported exit still needs user confirmation after this update; no claim is made that an unavailable crash stack identified its cause. The saved API key was preserved throughout.

## v0.2.2 Settings window audit · November 15, 2026

The user subsequently clarified that the window minimized/disappeared rather than the process crashing. Removed background-wide window dragging and hit testing from decorative AppKit material/chrome views. Chrome configuration now runs once per attachment, and opening Settings explicitly restores a minimized window. Added minimize/restore diagnostics. These address window interaction hazards; the exact original trigger was not independently established.

Build and signature verification passed. 46 offline tests passed; two opt-in live API tests skipped (48 discovered). All nine native Settings sections were inspected; completed live interactions include repeated provider verification, microphone and permission refresh, reversible toggles, native picker menus, appearance changes, a real Spotify read, native permission-settings navigation and intentional minimize/restore. The API key and existing history were preserved. Intermittent automation/capture errors prevented reliable scroll verification; destructive actions and new OS grants were excluded. See [the detailed coverage matrix](SETTINGS-TEST-MATRIX.md) for the distinction between exercised controls, inspected controls and outstanding manual checks.

## v0.2.3 Input Monitoring mismatch · November 15, 2026

Confirmed in native System Settings that Sotto's Input Monitoring switch was on. Restarting the existing app did not restore access. Public event-tap metadata showed a disabled listener with only `flagsChanged` (mask 4096), with `keyDown` and `keyUp` stripped. A non-nil tap had incorrectly been treated as shortcut readiness. The updated app checks the effective mask, current process, global listen-only scope, validity and enabled state; partial taps are discarded. Permission status also distinguishes first-time access, current-copy unavailability and granted access without a working listener.

Both `CGPreflightListenEventAccess` and `IOHIDCheckAccess` deny access in the development-signed v0.2.3 process. A separate existing Reminders grant produced a signing-requirement mismatch in macOS logs, consistent with permissions retained from an earlier development identity. This does not prove which identity the Input Monitoring entry uses. Sotto cannot infer authorization from a visible switch or silently rewrite macOS privacy records. The recovery interface explains restarting and, if necessary, removing/re-adding the current copy through System Settings.

50 offline tests passed, two opt-in API tests skipped (52 discovered). New tests cover granted-but-unavailable, denial versus unknown, independent permission/registration status, a stripped event mask, disabled taps and another process's tap. Build and strict signature verification passed. The actual recovery interface was inspected, and its native Restart Sotto action successfully replaced the process and reopened Settings while preserving preferences. The enabled OS entry still needs refreshing with user approval; no permission was changed during diagnosis.

API references: [Apple's event-tap documentation](https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate(tap:place:options:eventsofinterest:callback:userinfo:)) describes unavailable event-mask bits being cleared; [Apple DTS](https://developer.apple.com/forums/thread/724608) describes listen-only keyboard taps and Input Monitoring. IOKit's public SDK header documents granted/denied/unknown access checks. No private API, privacy-database edit or permission reset command is used.

The user subsequently removed and re-added Sotto in Input Monitoring and reports that it now works. This is user-confirmed recovery, not an independently replayed global shortcut test. No further permission changes were made by the agent.

## Release identity safeguards · November 15, 2026

Added an explicit Developer ID archive/export/notarization workflow and a read-only release gate. 14 Python policy/control-flow tests pass. A real invocation of the gate rejected the existing development-signed app at the Developer ID requirement check. The release command fails immediately without explicit release team, signing identity and notarization profile. Xcode's resolved Release settings confirm manual Developer ID signing, Hardened Runtime, a timestamp and disabled debug entitlement injection.

There are no installed Developer ID Application identities, so no actual distribution build, notarization upload or old-to-new production upgrade was performed. The running development app was not rebuilt, re-signed, relaunched or modified during this release tooling work. [RELEASING.md](RELEASING.md) records remaining prerequisites and acceptance tests; static identity checks alone do not certify privacy-grant preservation.

## v0.3.0 unified shortcut · November 15, 2026

Replaced preset modifier/key pickers and the toggle switch with a native shortcut recorder shared by Setup and General. Existing bindings migrate to the new representation; old toggle preferences no longer override hold/release. A pure gesture state machine starts capture on first press, defers only a short tap's release for double-tap recognition, and latches a timely second press into manual-submit listening. Normal holds submit on release. Send/Esc, failure and shutdown reset pending work. Modifier-only shortcuts use flagsChanged; combining a held modifier-only shortcut with another key discards that activation. Shortcut editing stops the global listener and restores it on completion/cancel/focus loss. The recording limit now discards audio, preserving manual submission semantics.

Build and strict signature verification passed. 60 offline Swift tests passed; two opt-in live API tests skipped (62 discovered). Ten new checks cover timing, cancellation, legacy migration, custom and Fn-only binding persistence, invalid bare keys/Escape, modifier release order, key-repeat suppression, Fn double-tap and rejection while the runtime is busy. Event-adapter tests construct CGEvent objects without posting them or capturing microphone audio.

Inspected the actual General control and native layout; the app reported Ready and Input Monitoring Allowed after rebuilding with the same development identity. During inspection the user changed their binding to Fn. Live recording/double-tap/Send acceptance was then handed to the user at their request, so no claim is made that those physical flows were independently verified by the agent. The temporary Debug-only --shortcut-voice-check launch routes real shortcut recordings to local transcription without inference/tools; it was removed by relaunching in normal --settings mode before handoff. No model request or native action was executed by this verification pass.

## v0.3.1 shortcut latency and double-tap fix · November 15, 2026

The user reported that double-tapping failed and capsule appearance was slow. Inspection found synchronous AVAudioEngine/recognizer setup and teardown on MainActor, callback-time tap measurement, a fixed 250 ms tap cutoff, and an initial panel fade/measurement path. Audio lifecycle work now belongs to a separate actor; immediate per-session cancellation tokens suppress stale audio/results, including during blocked hardware startup. Known authorization states use their existing status instead of repeatedly invoking request APIs. Capture uses the event-driven microphone inventory rather than scanning Core Audio on every press. No idle microphone capture or audio prewarming was introduced.

Shortcut timing uses CGEvent's physical timestamp and macOS's configured double-click interval (at least 250 ms). Modifier-key echoes do not count as an unrelated key canceling a modifier-only binding. A short grace allows already queued input to drain when callbacks arrive late. The prepared capsule is positioned/ordered at full opacity before deferred measurement, and entering Listening has no implicit animation. The UI no longer waits for synchronous audio hardware work to return.

65 offline Swift tests passed; two opt-in API tests skipped (67 discovered). New regressions cover callback delays longer than the tap window, a natural 400 ms first tap, modifier echoes, execution of the real audio worker startup method off the main thread using a canceled session (no hardware access), and immediately visible session-scoped cancellation. Build and strict signature verification passed.

Launched the development-signed app and inspected the real idle capsule. During the user's own keyboard tests, process 65654 logged three activation-to-panel-order durations of 2.79725 ms, 2.384917 ms and 1.007875 ms. Initial idle panel positioning/ordering took 3.209167 ms. A later physical second shortcut press logged “Hands-free recording latched.” The current native Settings control showed the user's Option-only shortcut and Ready. These are observed local window-ordering and gesture-state timings, not first-frame measurements, microphone readiness benchmarks, or a complete speech-to-tool acceptance test. Physical Fn-specific behavior and user-perceived latency remain for the user to confirm; their bindings and permission grants were preserved.

## v0.3.2 false configuration interruption · November 15, 2026

The screenshot's exact error came from an unconditional AVAudioEngineConfigurationChange observer. The updated handler runs on the audio actor, reads the actual input device/stream signature, and distinguishes unchanged running input, bounded same-input restart, startup-only format settling and genuine input changes. Recognition is not cleared on a same-format restart. Format rebuilds are forbidden once a buffer has been accepted, including a buffer racing with the recovery decision. Startup now completes only when a real buffer arrives; a five-second no-audio timeout prevents indefinite Starting microphone state. Old canceled startup continuations cannot reset a newer session after actor reentrancy.

73 offline Swift tests passed; two opt-in API tests skipped (75 discovered). Eight new policy/token tests cover benign notifications, output-related stops with unchanged input, startup format settling, mid-recording format changes, device switches, missing/invalid input, bounded repair loops and canceled buffers. Build and strict signature verification passed.

The diagnostic launch initially overlapped another running copy; both were stopped and a single new process was used for the check. Through native Setup, started a transcription-only check with the existing MacBook Air Microphone selection and on-device speech preference preserved. Process 73942 logged `running=true, inputUnchanged=true, hasAudio=false, action=ignore`, then real first-buffer readiness at 0.293476208 seconds. The check completed without the configuration-change error and reported No speech detected; no spoken sample was supplied, so this is startup/notification validation rather than a successful final-transcription or agent-tool test. No OpenAI request, tool execution, permission change or microphone selection change was made. Restarted one normal command-enabled copy before handoff.

Apple documents that [engine configuration notifications can concern input or output hardware](https://developer.apple.com/documentation/foundation/nsnotification/name-swift.struct/avaudioengineconfigurationchange), and that engine teardown must not occur on the internal notification queue. Physical disconnect/reconnect and headset profile transitions remain separate manual release tests.

## v0.3.3 microphone test versus agent command · November 15, 2026

The user's screenshot showed a successful local voice check for “Open my downloads folder,” with Check again repeating the local test. The process was launched with --settings, not the diagnostic shortcut override. Normal shortcut capture was already command-enabled; the separate microphone-test entry point and its sticky footer were confusing.

Setup now says Test microphone only and explains how to run an AI command. Successful test results offer Run command, which snapshots the actual recognized transcript, leaves test mode synchronously to prevent duplicate submission, and calls the existing submit path with its remote-consent, Keychain and trusted tool authorization checks. No microphone test uploads itself automatically. The terminal footer's Speak a command action starts normal capture. Setup allows trying a real request with a saved key, consent and usable voice input without demanding a fresh provider catalog verification each launch; finishing setup still requires verification.

73 offline tests passed; two opt-in API tests skipped (75 discovered). Build and strict signature verification passed. Native Setup showed the renamed test, processing disclosure, saved-key state, Allowed microphone/Speech/Input Monitoring and an enabled Try a voice command button. No API request or native action was triggered in this UI pass; the new result-to-command button's live network/tool completion still needs acceptance testing. One normal command-enabled app was launched through LaunchServices, preserving microphone, shortcut, history and credentials.
