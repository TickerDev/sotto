# Zero-configuration implementation audit

## Live speech without another application

Apple Speech now prefers modern, on-device progressive SpeechAnalyzer/SpeechTranscriber when this Mac/language supports it and system assets are installed. Voice offers explicit language preparation; older/unsupported configurations retain streaming Apple recognition. The macOS 14 deployment floor and existing native commands remain intact. No speech application, account or external runtime is required for this path. Modern recognition requires microphone access, without the legacy Speech Recognition permission.

One saved shortcut supports default hold/release and double-tap/manual Send; General can select press-to-toggle for that same binding. The capsule shows evolving words. Pauses may prepare an inference turn but never submit or run tools; release/Send/toggle-stop and confirmed text remain the action boundary. The existing native route still opens Downloads, searches filenames and controls Spotify without model inference.

Optional OpenAI Realtime is a separate speech choice with explicit audio consent and a user Keychain API key. It is never selected as an automatic fallback. Reasoning preparation can send provisional text only to the selected, already consented reasoning destination; it can be disabled in Voice. See [real-time voice](REALTIME-VOICE.md) for implementation, Atticus research, measurements and manual checks.

Validation: 164 offline tests pass, 11 opt-in skipped; signed build/strict signature verification pass. A real Apple analyzer test confirmed live partials before closing synthetic input and finalized words afterward. Native controls, language preparation and local start/cancel were inspected. Cold microphone/model startup is still variable; physical full voice-to-tool timings and minimum-OS/Intel acceptance remain outstanding.

## Actionable file search

“Find my résumé” now takes a native filename-search route, without a model or account. Structured matches carry path and modification date. Résumé/CV/curriculum-vitae variants are searched together, supported document formats ranked, code/cache noise suppressed and iCloud/CloudStorage documents retained. Results use native file rows with title, location, date, Open and Show in Finder actions. Clicking a row submits its exact cached path through the native runtime and normal file checks; invented paths are rejected. No file contents are read for search or uploaded in this native route.

Spotlight examines up to 500 newest matching candidates and returns up to 20 ranked matches. The query’s results are snapshotted before stopping it. When no useful indexed matches exist, an actor performs a bounded filename-only search of Documents, Desktop, Downloads, iCloud Drive and CloudStorage folders, capped at 5,000 entries and six levels. It skips symlinks, packages’ descendants, hidden items and developer dependency/build folders. OS access denial is not bypassed; a system folder-access prompt may still require the user’s grant. No whole-disk scan or Full Disk Access is requested. Empty results describe the searched accessible locations, rather than claiming no file exists anywhere.

The capsule renders actual native results, not model-authored paths or an unnecessary folder clarification. Matches stay visible, support scrolling and reuse the display-safe capsule layout. If a model asks a follow-up after returning real matches, the native choices remain available. Starting another request or cancelling clears the choices. Generic ambiguous requests remain model-driven; contextual date/content search is not implemented.

Validation: 142 offline tests passed, nine opt-in tests skipped (151 discovered). New tests cover accented/CV names, code noise, iCloud preservation, numbered names, recency, structured-result round trips, direct find routing, exact cached-file selection and one execution, fallback nesting/noise exclusion and cancellation. A separate live native search returned two real indexed résumé documents without reading their contents or opening them. Signed Debug build passed. The signed app’s narrower Spotlight result set motivated the directory fallback; the full folder-permission/result-selection UI acceptance remains manual. Native Setup entry inspected; no personal résumé was opened and no file data was sent to an AI provider during this pass.

## Calendar agenda

### Permission-request correction

The user reported Allow access immediately claiming cancellation. The macOS TCC log identified the actual cause: Hardened Runtime blocked Calendar prompting because `com.apple.security.personal-information.calendars` was missing. Added that entitlement to the application and reviewed release policy; the app retains Hardened Runtime and still requires user-granted OS consent. Verified the entitlement in the built signed bundle, not just the source plist.

Permission requests now distinguish granted access, refusal, a System Settings recovery, an unavailable request and another request in progress. A framework failure or a blocked request that leaves authorization undetermined is no longer called user cancellation. Access already granted while the sheet is open is accepted after refresh. Cancelled or expired continuations remain single-use and cannot resume late.

Validation: 129 offline Swift tests passed, eight opt-in tests skipped; 15 release-policy tests passed. New checks enforce Calendar entitlement/usage-description packaging and distinguish blocked requests from cancellation. Signed Debug build and deep/strict signature verification passed. Restarted the rebuilt application; no OS grant or privacy reset was performed. Actual grant-and-agenda completion remains for the user to verify.

Ask “What’s on my calendar today?” or “What’s on my calendar tomorrow?” The bounded native route computes local day boundaries (including daylight saving), invokes the actual registry/runtime, and formats the result without any reasoning provider. Setup includes a matching first-command button. Other dates can use the selected intelligence through the same typed read tool. No Calendar writes, invitations, edits or deletion are exposed.

First use presents a native Connect Calendar sheet and preserves the original request only in the suspended task. Cancel, shutdown and the existing five-minute timeout discard it. macOS requires full access to read Calendar; the sheet explains that Sotto only reads the requested range. Write-only access is insufficient; denied access opens System Settings and cancels the current attempt. The production adapter independently verifies authorization before and after fetching. This follows [Apple’s EventKit access model](https://developer.apple.com/documentation/technotes/tn3153-adopting-api-changes-for-eventkit-in-ios-macos-and-watchos).

An actor owns EventKit objects off the main thread and returns immutable title/start/end/all-day snapshots. No notes, attendees, conferencing links or locations are collected. Queries are bounded to 31 days; cancelled events are excluded, results sorted and capped at 30 with an explicit truncation notice. Activity history records count/range rather than event titles. Native agenda requests clear follow-up context and never send event data to a model. Flexible model-driven requests return these minimal snapshots to the chosen provider under the existing processing choice. Agenda results remain readable rather than dismissing as short action confirmations.

Validation: 136 tests discovered, 128 passed, eight opt-in tests skipped, zero failures. Seven new tests cover DST boundaries, conservative grammar, invalid ranges before reads, sorted/overlapping/all-day results, empty/capped agendas, full versus write-only authorization, pending-access resumption and cancellation. No real Calendar access is granted by tests. Signed Debug build and deep/strict signature verification passed. The real Setup button opened the native connection sheet; Cancel dismissed it without requesting OS access or reading events. The screenshot showed no clipped content. Personal-calendar retrieval, physical speech and minimum-OS/Intel acceptance remain manual.

Manual acceptance: use Setup’s calendar question (or speak it), allow access yourself, compare titles/times with Calendar, then ask about tomorrow. Also cancel before granting and confirm that no agenda is returned. During inspection Input Monitoring reported unavailable to this copy; the menu-bar and Setup entry points remain usable. No permissions were changed or reset during this pass.

## Original barriers

- AppModel.submit required processing consent before any execution, including Finder commands. Every request required an external provider.
- Setup presented endpoints, provider selection and model identifiers and required provider verification to finish.
- NativeTools already implemented Finder, Spotlight, NSWorkspace, Spotify Apple Events and EventKit. No external runtime is needed for these tools themselves.
- Provider configuration and internal tool identifiers appeared in primary settings.
- Apple Speech, AVFoundation capture, SQLite activity history and Keychain were already implemented; these are retained.
- Reminders and Spotify require macOS consent; OpenAI requires a user API key and remote-data consent. No Gmail OAuth, MCP host or marketplace execution environment existed.

## Implemented increments

1. Read-only structured discovery of OS, memory, architecture, Foundation Model readiness, speech availability and supported installed applications, with permission-specific states. Discovery never requests permissions or advertises unsupported screen/Accessibility/MCP connections.
2. Conservative native command routing through the existing runtime, schema validation, authorization gate and activity history. Folder opening and indexed PDF search work without intelligence infrastructure. Ambiguous and compound commands are deliberately left to reasoning. PDF matching uses filename suffix and reports the newest indexed match, not a claim to search every disk.
3. Availability-gated Foundation Models guided action generation. Proposals use the registered schemas and pass through the same policy gate. The adapter handles errors and cancellation without silently changing to a paid service. Context limits fail explicitly. It does not claim arbitrary tool-call reliability.
4. New installs default to Automatic; existing provider preferences migrate without changing their selection. Automatic prefers native actions, then Apple intelligence, then discovered local tool-capable Ollama models. OpenAI remains an explicit choice with separate remote consent; the guided connection flow can enable it after verification. No model or runtime is downloaded. An installed local engine can now be started on demand by the managed-runtime flow described below.
5. Provider-free first-run actions, simple Intelligence states, Advanced provider/tool diagnostics, and preserved microphone-only test under Voice.
6. Native Reminders connection sheet suspends the original runtime task in memory. Official EventKit authorization must be verified before resumption. Decline terminates without retries; cancellation, shutdown and a five-minute timeout discard the pending intent. No transcript is persisted for setup. Previously denied access opens macOS settings and cancels this attempt; it never assumes permission was granted.
7. Turning off remote consent cancels active work and clears conversation context. Changing Automatic or a provider also clears context.

## Embedded inference investigation

[MLX Swift](https://github.com/ml-explore/mlx-swift) and [MLX Swift LM](https://github.com/ml-explore/mlx-swift-lm) support in-process Swift inference and model-specific tool parsing. [llama.cpp](https://github.com/ggml-org/llama.cpp) provides a C/C++ alternative with Metal and Accelerate support. These are candidates, not dependencies added by this increment. MLX is the preferred Apple Silicon prototype; llama.cpp merits a separate Intel/CPU compatibility evaluation.

Do not select a model solely from RAM or its claimed tool flag. Before shipping a download, pin a licensed artifact revision, exact compressed and installed byte counts, checksums and supported prompt/tool formats; benchmark actual memory use and action reliability across target Macs. Use consented URLSession downloads with progress and resumable transfer, disk-space checks, atomic verified installation and removal. None of those model lifecycle functions are implemented yet, so no one-click download is advertised.

## Remaining product scope

This increment is not the full acceptance of the product brief. Official account OAuth (including Gmail), generalized service connection management, an integration catalog, package signing/install/update/removal, isolated third-party execution, developer SDK and MCP compatibility remain to be implemented. PDFKit/Vision content understanding, Calendar writes, Accessibility and screen-aware execution are also absent. Calendar agenda reading is implemented below. Do not display them as ready.

The on-device adapter compiles against the public framework, but live model reasoning, voice onboarding and actual permission sheets still need interactive validation on an eligible Mac. Automated tests use probe tools without opening personal files or granting permissions. Intel and older macOS runtime coverage remain required. A build is not evidence of live model quality or visual acceptance.

## Validation for this increment

- `SOTTO_NATIVE_TEST=1 swift test`: 97 tests, zero failures, four pre-existing credential/server-dependent tests skipped.
- Live native Downloads test opened Finder using the actual registry and agent runtime, without any AI provider.
- Authorization probe verified zero executions while access was pending and exactly one execution after resumption, retaining the original user request.
- Xcode Debug application build succeeded with `CODE_SIGNING_ALLOWED=NO`.
- No live Foundation Model, microphone, permission-sheet, visual-layout or third-party account acceptance is claimed by these results.

## Guided intelligence setup increment

Missing intelligence now opens a native connection sheet and preserves the original request and necessary follow-up context only in memory. A monotonic five-minute deadline, single-use identifier, cancellation and shutdown prevent replay. Starting a new voice session or request discards the waiting intent. Setup does not persist the waiting text in preferences, history or diagnostics.

The sheet offers ready on-device/local intelligence without a model picker or endpoint field. It also supports an explicit OpenAI API connection: separate billing and data-transfer disclosures, a secure key field (or saved Keychain credential), affirmative remote-use consent, and catalog verification before generation. It makes no ChatGPT subscription authorization claim. The approved pending context is restored only after that explicit connection action; ordinary provider changes still clear active context. No API request is generated during verification.

Failed key saves never fall back to a previously saved key. Cancelled verification results cannot enable cloud consent or resume a request. Existing verified connections survive an intentional backend selection when no verification is in flight. Test injection avoids real Keychain reads, preference writes, database creation and global keyboard registration.

Validation: 103 package tests, zero failures, five opt-in live tests skipped. Tests cover intent expiry/single use, absence of generation before consent, failed credential saves, late results after cancellation, and exactly-once resumption after changing providers. Native visual inspection was attempted but the computer-use service returned `timeoutReached`; no visual acceptance is claimed.

Final guided-setup verification: `swift test` passed with 103 tests, zero failures and five opt-in tests skipped. Xcode Debug application build succeeded with signing disabled. The only Xcode warning was skipped App Intents metadata extraction because this target has no AppIntents dependency. No live account, paid generation or microphone interaction was used during this increment.

## Downloads + Spotify failure fix

The screenshot exposed a raw decoding failure in Automatic mode. Inspection found model-generated JSON nested inside the on-device action's string arguments, parsed with JSONDecoder. That unsafe serialization boundary is removed. Runtime schemas now constrain tool selection and generate typed parameter objects; validation still precedes execution. Malformed provider arguments receive content-free, actionable errors and an Intelligence recovery action.

The exact request “open downloads folder and resume music on Spotify” now takes a bounded native route. Each complete clause must match an allowed native operation. The native sequence shares the agent's validation, authorization and real tools; it stops on a failure rather than continuing with the remaining actions. Mixed unknown/unsafe clauses do not enter this route.

Real on-device single-action generation was exercised successfully without executing desktop actions. Exploratory direct-model compound planning remained unreliable (repetition/step limit); this is not claimed fixed or certified. Its observed repetition motivated a guard preventing identical successfully completed actions from executing again in the on-device path. The product handles this reported command natively rather than relying on that planner. Automated regression tests use probe tools for Downloads and Spotify, with no real playback changes. The exploratory multi-step model experiment is documented here rather than represented as a passing acceptance test.

Final validation for the reported-command fix: 111 tests, zero failures, six opt-in tests skipped; Xcode Debug application build succeeded. The running app must be quit and reopened to load the rebuilt binary. No live Spotify playback or personal-folder opening was performed during this fix.

## Microphone startup crash fix

macOS crash reports from November 15, 2026 pinpointed an uncaught `com.apple.coreaudio.avfaudio` exception at `AppleSpeechWorker.installTap`. Unified logs showed 48 kHz hardware with a stale 16 kHz client/output format during startup. This was an audio-route failure, independent of intelligence response decoding.

Tap installation now reads the hardware input format immediately at the native boundary. A small Objective-C bridge contains AVFoundation exceptions during tap installation, engine preparation/start and cleanup, returning a recoverable microphone error to the existing session lifecycle. Swift do/catch alone cannot contain those framework exceptions. Cancellation, input-change detection and recording discard behavior remain in place.

Regression fixtures use message-compatible native test objects: a 48 kHz hardware input and 16 kHz stale output, plus real injected Objective-C exceptions. They do not instantiate an audio engine or capture microphone data. Tests confirm exception containment and successful subsequent installation after a failure.

Validation: 114 tests, zero failures, six opt-in live tests skipped. `Scripts/build.sh` succeeded and `codesign --verify --deep --strict` passed. Reopening through the computer-use service timed out, but process inspection confirmed the rebuilt Sotto executable was running afterward. Live microphone/route-transition behavior was not exercised automatically; it still requires a deliberate voice activation.

## Adaptive microphone selection

Microphone selection now expresses a preference rather than a pin. At activation Sotto chooses the preferred available UID, then the system input, then another available input. Discovery filters out non-live and zero-channel devices. A missing or legacy preference no longer blocks listening. The saved preference is not rewritten when a fallback is used.

During a user-initiated recording, input loss or an audio-format failure triggers a fresh capture on another candidate. The interrupted transcript is cleared and the capsule names the active microphone with “Please repeat.” The app excludes failed candidates during that capture, permits at most two recoveries, and preserves the original 55-second deadline. If only one device exists, a clean restart can recover a format transition. A preferred device returning does not interrupt a working recording; it is selected on the next activation. No device reconnection or stale callback starts capture after cancellation. Permission failures never trigger source hopping. Transcription already being finalized is cancelled if its source disappears; it is not submitted as a partial command.

Voice settings now show “Preferred microphone,” “Automatic — Recommended,” actual active/next input, and the fallback behavior. README and design guidance supersede their previous hard-pin policy.

Validation: 121 package tests, zero failures, six opt-in tests skipped; signed Debug app build and strict signature verification passed. The focused adaptive tests cover preferred/system/remaining selection, failed startup, disconnect while recording, stale transcript suppression, bounded retries, preference restoration on the next activation, cancellation and permission denial. Speech and device inventories are injected probes; no microphone capture or live Bluetooth disconnect was performed. Restart the running app to load this build.

## Managed local runtime

Sotto now owns server startup rather than instructing users to run terminal commands. Enable local intelligence detects a fixed-location Ollama app/Homebrew executable, launches `serve` directly if the standard local server is unavailable, waits for bounded readiness, discovers installed models, selects a tool-capable model and resumes the waiting request. Normal local requests also ensure readiness and restart the managed engine if it was stopped. This does not invoke a shell, alter login items or manage Homebrew services.

The child uses a minimal environment with IPv4 loopback binding, cloud features disabled and a one-minute model keep-alive. Provider credentials and inherited proxy configuration are absent. Concurrent startup is coalesced for the same endpoint; a different endpoint cannot borrow that readiness result. Existing servers are probed and reused without ownership. Only a child launched by Sotto is stopped, after five idle minutes or shutdown; active request leases postpone idle shutdown. Changing the endpoint stops Sotto’s old child. Advanced custom endpoints must already be healthy; Sotto does not spawn a service at a custom address.

Runtime installation and model downloads remain separate: the sheet links to the official Ollama macOS download when the executable is missing, and honestly reports when no compatible model exists. No large model is downloaded or executable installed automatically by this increment.

Validation: `SOTTO_RUNTIME_TEST=1 swift test` passed 129 tests, zero failures, six opt-in inference/action tests skipped. A real installed Ollama child started on an isolated loopback port, served the model catalog and terminated through the production process wrapper. An existing server was reused and remained alive after controller shutdown; process inspection confirmed it was the only Ollama process left afterward. Unit tests also cover unavailable/missing binaries, startup timeout, cancellation, external ownership, local-only environment and idle leases. Signed Debug app build succeeded. No inference, model download or desktop action occurred in these runtime checks.
