# Sotto

**Just say it. It’s done.**

A native, voice-first macOS agent. Swift 6, SwiftUI and AppKit; no web UI, no Sotto account, no Sotto backend. Apache 2.0 licensed.

## Run

Requires macOS 14+, Xcode 26+ with Swift 6 (macOS 26 SDK or later), and network access to resolve the pinned GRDB dependency. This checkout was built with Xcode 27 / Swift 6.4 on Apple Silicon. Intel compilation and macOS 14 runtime behavior need separate validation.

Open `Sotto.xcodeproj`, select the Sotto scheme, and Run. Or:

```sh
./Scripts/build.sh
open build/Build/Products/Debug/Sotto.app
```

The app runs in the menu bar without a Dock icon. Setup opens on first launch and offers real commands: **Open my Downloads folder**, **Find my latest PDF** and **What’s on my calendar today?**. These work without an AI account or external runtime. Calendar asks for access when needed and continues the original request after authorization. Microphone permission is requested when listening starts; legacy Apple recognition also requires Speech Recognition permission. Keyboard access is optional.

**Intelligence** defaults to Automatic for new installations: native commands first, then Apple’s on-device Foundation Model when available, then a discovered tool-capable local Ollama model. No paid connection is selected automatically. Availability depends on macOS, hardware, Apple Intelligence settings and assets. More flexible requests require an available reasoning engine. When none is ready, Sotto offers a guided connection sheet and keeps the request in memory for up to five minutes so it can continue after verification.

**Intelligence → Enable intelligence… → Enable local intelligence** starts an installed Ollama engine, verifies available models and selects a compatible installed model without terminal commands. Sotto reuses existing servers, manages only its own child process, and stops that child after five idle minutes or when Sotto quits. Runtime installation and model downloads remain separate; no large downloads happen automatically. The same sheet also offers an explicitly authorized OpenAI API connection.

**Intelligence → Advanced** preserves manual providers, model selection, keys, connection diagnostics and Ollama endpoints. Turn off Automatic to use that selected provider. OpenAI requires an API key in Keychain and explicit permission in **Privacy**; API billing is separate from a ChatGPT subscription. Existing saved provider selections are preserved. Sotto does not implement ChatGPT subscription sign-in.

Default shortcut: **Control–Option–Space**. Hold to talk and release to send. Double-tap the same shortcut to keep listening after release, then click **Send**; Escape discards the recording. General also offers **Press to toggle**, using the same shortcut to begin and submit. **Activation shortcut** is one native recorder shared by General and Setup: click it and press a combination, or press/release modifier keys for a modifier-only shortcut such as Fn. Escape cancels editing; Tab leaves the field. Existing chosen keys are preserved; older toggle preferences retain their migrated hold/double-tap behavior until explicitly changed. Fn/Globe availability depends on keyboard and system settings. The passive listener does not suppress keystrokes; avoid shortcuts used by other apps. Menu bar **Activate Sotto** starts/stops listening without global keyboard access. Recordings reaching the 55-second limit are discarded rather than submitted automatically.

Apple Speech displays live words while you speak. On supported macOS 26+ configurations it uses on-device SpeechAnalyzer/SpeechTranscriber; Voice offers **Prepare on-device speech** for missing system language assets. Other configurations retain streaming SFSpeechRecognizer. The on-device requirement defaults on; the legacy service may need downloaded assets or a supported language. Disabling that requirement permits Apple's legacy remote processing. Initial permission dialogs can interrupt a hold gesture: finish setup, then invoke again. [Pipeline, research and timing evidence](docs/REALTIME-VOICE.md).

**Test transcription only** in Voice checks the chosen speech backend without calling the reasoning provider or executing tools. Its result offers **Run command** to explicitly send that transcript through the normal agent, or **Speak a command** to dictate a new request. Your activation shortcut, menu-bar activation, Voice's Start listening and Setup's Try a voice command use normal command mode.

Voice can prepare reasoning during stable pauses, without executing tools. Changed words or resumed speech discard the draft; explicit submission and confirmed transcription still precede every action. You can disable preparation in Voice. Optional **OpenAI Realtime** transcription requires separate audio consent and your API key; it does not change your reasoning model. See [cloud transcription setup](docs/REALTIME-TRANSCRIPTION.md).

## Implemented

- Menu bar lifecycle, native settings and optional guided setup, light/dark/system appearance, Reduce Motion support, labeled controls, keyboard navigation, and nonactivating voice panel.
- Explicit listening/transcription/agent/approval/completion/error states; real microphone RMS waveform, modern on-device progressive transcripts with legacy fallback, safe pause preparation, Escape cancellation, 55-second capture limit, final-transcript timeout and measured voice phases.
- Explicit follow-up questions with preserved context, readable consequential-action approvals, and complete scrollable feedback.
- Streamed OpenAI Responses API provider, Keychain storage, catalog connection check, conservative supported-model list, tool calls/results, cancellation, bounded eight-round agent loop, short-lived follow-up context.
- Local Ollama provider with installed-model/capability discovery, streamed tool calls and results, loopback-only configuration and cloud-tag rejection. Local reasoning requires no OpenAI key. See [local model setup](docs/LOCAL-MODELS.md).
- Trusted schema validation and risk gate. Requested reminder creation uses an in-context access sheet on first use and resumes the suspended command only after EventKit access is verified. Declining, cancelling, or waiting five minutes cancels the pending access request. Requested document opening, file revealing and application launches run directly. Consequential tools retain exact-argument authorization. No general shell or generated AppleScript execution is exposed to the agent. The Spotify adapter launches only `/usr/bin/osascript` with reviewed scripts selected by a fixed action enum.
- Spotify play, pause, next, previous, current track via its installed scripting dictionary. Spotify must already be running with a playable track. A fixed native helper runs off the UI thread, supports cancellation, enforces a timeout/output bound, and verifies play/pause state. macOS Automation consent is requested on first use. Integrations includes a read-only connection check.
- Finder folder opening, document opening/reveal, Spotlight filename search with ranked, clickable results and a bounded document-folder fallback, installed-app opening by bundle ID, running-app listing.
- EventKit create/list reminders, with permission handling and post-save identifier verification.
- Read Calendar agendas through EventKit. Today/tomorrow questions run without a model; other date ranges can use intelligence. Access is requested on demand. No event creation, editing, invitations or deletion is implemented. See [Calendar validation](docs/ZERO-CONFIGURATION.md#calendar-agenda).
- GRDB/SQLite actual tool result/error history, retention and deletion, optional completion sounds and notifications, launch-at-login registration.

**Live OpenAI and Ollama → tool execution have been tested for Downloads. Full voice acceptance is not certified.** See [validation status](docs/VALIDATION.md) for what was actually checked and what needs credentials, permission consent, microphone speech, or user data.

## Privacy and safety

Raw audio is not stored. Only explicit activation starts the microphone. Modern Apple transcription stays on device. Apple's legacy speech service may process audio remotely only when the on-device requirement is disabled. Selecting OpenAI Realtime and enabling its separate audio consent streams microphone audio directly to OpenAI while listening; cancellation cannot recall audio already sent. When OpenAI reasoning is selected and allowed, transcripts, conversational context, schemas and tool results go directly to OpenAI; results may include local filenames or reminder titles. With pause preparation enabled, this can include provisional transcript text before release. `store:false` is requested for reasoning; OpenAI policies still apply. Ollama receives reasoning requests at its configured loopback address, without OpenAI credentials. Advertised cloud-backed models are blocked; also disable cloud features in the external Ollama server for local-only operation. Changing provider, model or local address clears in-memory conversation. No screenshot or selected text is captured. No credentials are extracted from other apps.

History lives at `~/Library/Application Support/Sotto/activity.sqlite`. It contains tool summaries/errors, which can include sensitive titles or paths. It is not application-level encrypted; use FileVault for disk protection. API keys are stored in the user's Keychain. Conversation context expires after five minutes of inactivity; active reply recording preserves the current request. Activity retention is enforced at launch/history refresh and after tool records; deletion also clears in-memory conversation.

Cancellation stops recording and discards the transcript, aborts pending provider work, denies pending approvals, and terminates the Spotify helper. Native side effects already submitted cannot be rolled back; terminating the helper cannot retract an Apple Event already delivered. Actual late results are still recorded when history is enabled. Treat all retrieved content as untrusted; the model never decides its own approval policy.

This is a non-sandboxed developer app using public macOS APIs. Distribution requires a stable signing identity, Developer ID signing/notarization, and testing consent flows with that identity. The build script automatically uses one unambiguous local Apple Development identity when available, without storing personal certificate/team data in source. Otherwise it falls back to ad-hoc signing, which can require permissions to be reauthorized after rebuilds. Changing from ad-hoc to development signing may require an initial reauthorization. No automatic updater or public GitHub remote is configured.

## Audio and permission recovery

Microphone preferences use stable Core Audio UIDs. Sotto uses your preferred microphone when available, then the system input, then another available input. Failed sources are excluded during bounded recovery. A source or format failure during listening restarts capture, clears the interrupted transcript and displays the new input with “Please repeat.” A reconnecting preferred microphone is used on the next activation without interrupting a working recording. Recovery never extends the original 55-second recording limit. Cancel, permission denial and sleep stop recording.

**Upgrading from the first build:** an unavailable or legacy microphone selection automatically falls back to a working input. Existing shortcut, model, privacy, history and appearance preferences are preserved. A system-default selection remains system default.

Permissions shows native access state and specific System Settings links. Denied/restricted access is not repeatedly prompted. Setup asks only when you click an Allow action; optional Reminders/Automation permissions remain tied to their integrations. Failed voice startup offers a recovery button for the relevant permission or Voice settings. No Accessibility or screen-capture permission is requested.

The Setup voice check records only on explicit activation, uses the selected speech backend and never calls the reasoning provider or runs an agent tool. Sending its transcript requires the explicit Run command action. Apple on-device recognition stays required unless you explicitly allow Apple processing; OpenAI audio upload requires its own consent.

## Local signing

With one valid Apple Development identity in Keychain, `Scripts/build.sh` selects it and obtains its team from the public certificate. Personal identity data and private keys are never copied into the repository. Xcode users can select their team in Signing & Capabilities.

```sh
# Explicit identity/team when several are installed:
SOTTO_SIGNING_IDENTITY="your identity" SOTTO_DEVELOPMENT_TEAM="your team" ./Scripts/build.sh
# Ad-hoc development fallback, including CI:
SOTTO_SIGNING_IDENTITY=- ./Scripts/build.sh
```

Development signing is not Developer ID distribution or notarization.

Official release builds use a separate fail-closed [release workflow](docs/RELEASING.md): explicit Developer ID signing, previous-release identity compatibility checks, notarization and stapling. `Scripts/release.py` never falls back to development/ad-hoc signing. A real two-version permission-preservation test is required before publishing; the release certificate, notarization profile and automatic updater are not configured here.

## Not available yet

Remote/custom compatible endpoints, Codex app-server, other hosted vendors, MCP, email, Discord, Calendar writes, Notes, Shortcuts, screen capture, selected-text reading, AX automation, spoken responses in the UI, and automatic updates. Settings labels these unavailable. The speech-synthesis protocol and foreground-app context type are foundations only. No claims of completing these integrations are made.

OpenAI uses a fixed vetted model set because `/models` does not provide a tool-capability contract. Other OpenAI catalog models are not automatically enabled. Ollama uses native capability discovery. Spotify commands can run only through its fixed local adapter. Document opening is restricted to supported document/media formats; macOS application bundles can also be opened directly. Scripts, installers and other executable file types remain unavailable through the file tool; folders open in Finder. File search ranks up to 500 indexed home-directory candidates and displays up to 20 matches. If Spotlight provides none, a filename-only fallback inspects up to 5,000 entries, six levels deep, in usual document folders and cloud-drive folders. macOS file permissions still apply. Résumé searches include CV/accented names and suppress developer/cache noise. There is no full-content search or date filter yet.

## Contribute

See [architecture and extension interfaces](docs/ARCHITECTURE.md), [provider research](docs/PROVIDERS.md), and [acceptance checklist](docs/VALIDATION.md).

```sh
swift test
# Only needed after changing project.yml:
xcodegen generate
```

`project.yml` is the reproducible XcodeGen source; the generated Xcode project is included. `Package.resolved` pins the dependency. No provider credential is needed for automated tests.

## Native material design

The capsule uses native Liquid Glass on macOS 26+, and native HUD vibrancy on macOS 14–15. Settings uses layered native materials and a translucent sidebar. Accessibility display preferences take priority over translucency and animation. The design conventions are recorded in [DESIGN.md](DESIGN.md).

For visual review of the Debug build without microphone capture or inference:

```sh
open build/Build/Products/Debug/Sotto.app --args --settings --show-capsule
```

Launch the `.app` with `open` or Xcode Run. Invoking its raw executable from a terminal can give permission requests the wrong responsible-app identity.


Additional Debug-only interface fixtures (no recording, inference, or native actions; controls are disabled):

```sh
open build/Build/Products/Debug/Sotto.app --args --review-capsule approval
# Alternatives: question, completion
```

Quit any running copy before launching a fixture, and quit the fixture before launching normally. Keep only one Sotto process running. These are labeled visual-review states, not integration tests. See [the roadmap](docs/ROADMAP.md) for the remaining work.
