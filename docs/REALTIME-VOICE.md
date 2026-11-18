# Real-time voice

Sotto displays speech while the microphone is open. The existing glass capsule, waveform, tool registry, permission checks and native integrations remain in place. Recognition and reasoning are independent choices.

## Audit and research

Before this change, Sotto already streamed `SFSpeechRecognizer` results from an `AVAudioEngine` tap. It was not a batch-only recognizer. The gaps were modern on-device recognition, explicit confirmed versus revisable text, safe preparation during pauses and timing across the whole request.

Reviewed [Atticus](https://github.com/SaarthurR/atticus-mac/tree/cee9340d5076d275ac90d321675f5ab0d89d3518) at commit `cee9340d5076d275ac90d321675f5ab0d89d3518`, particularly [Atticus.swift](https://github.com/SaarthurR/atticus-mac/blob/cee9340d5076d275ac90d321675f5ab0d89d3518/Atticus.swift), [GUIDE.md](https://github.com/SaarthurR/atticus-mac/blob/cee9340d5076d275ac90d321675f5ab0d89d3518/docs/GUIDE.md) and the worker's execution gate in [atticus.py](https://github.com/SaarthurR/atticus-mac/blob/cee9340d5076d275ac90d321675f5ab0d89d3518/atticus.py).

| Area | Atticus implementation studied | Sotto implementation |
| --- | --- | --- |
| Capture | `Mic` uses AVCaptureSession and serialized startup/stop | Retain AVAudioEngine and selected-device recovery |
| Recognition | SpeechAnalyzer, negotiated format, progressive SpeechTranscriber | Availability-gated modern adapter with the existing legacy fallback |
| Results | `speechPiece` stitches finalized text and replaces volatile text | Time-range segments replace overlapping provisional results; confirmed text remains stable |
| Finish | Drain capture, finalize analyzer, await result reader | Release microphone, drain bounded input, finalize, then accept confirmed text |
| Silence | About 0.7 seconds for speculative work; click mode can submit after silence | 650 ms of quiet and unchanged text may prepare reasoning; silence never submits |
| Early reasoning | Worker starts ahead; commit file gates actions | Typed, in-memory first-turn draft; no tool execution in preparation |
| Fast commands | Some builtins run during speech | Deterministic native routing runs only after explicit submission and final transcription |
| Interruption | Cancel workers, timers and speech segments | Session tokens, task cancellation, actor-owned cleanup and stale-result rejection |
| Hands-free | Toggle, double-tap, optional wake word and automatic conversation listening | Same-shortcut toggle or double-tap/manual Send; follow-up context retained, no wake word or automatic microphone reopening |

This is a native Swift implementation; Atticus's UI, worker-process architecture and commit-file mechanism were not copied.

## Apple speech pipeline

The deployment target stays macOS 14. On macOS 26+, when hardware, locale and installed assets support it, `AppleSpeechProvider` selects `SpeechAnalyzer` and `SpeechTranscriber` with progressive results. Other configurations retain streaming `SFSpeechRecognizer`. Voice settings offers **Prepare on-device speech** when system language assets are missing. Ordinary activation does not download assets. Cancel stops an asset preparation request.

The modern path requires microphone permission. Apple's legacy Speech Recognition authorization is needed only for `SFSpeechRecognizer`, not the on-device analyzer modules. See [Apple's permission documentation](https://developer.apple.com/documentation/speech/asking-permission-to-use-speech-recognition).

`RealtimeMicrophone` owns AVAudioEngine, the selected input, actual RMS levels and bounded PCM delivery. Capture occurs only after activation. A converter produces mono 24 kHz PCM16; the modern adapter converts that stream to the analyzer's negotiated format, using a new buffer for each input. The macOS 27-only input-converter convenience API is deliberately avoided. No PCM is saved to disk.

`StreamingTranscript` keeps confirmed and provisional ranges separately. A revised hypothesis replaces earlier provisional words rather than duplicating them. The capsule renders confirmed words normally and provisional words with secondary emphasis. A framework-final segment during recording is still not authorization to execute the request.

On Send/release, capture stops before finalization is awaited. The adapter closes and drains analyzer input, calls `finalizeAndFinishThroughEndOfInput`, awaits the result reader and returns confirmed text. Provisional-only text is never promoted into an executable request on timeout or failure. Startup has an eight-second analyzer deadline and capture has a five-second no-audio deadline; modern finalization has a four-second deadline. The existing 55-second recording limit discards rather than submits. Escape, shutdown, sleep and failed input recovery invalidate the session and release capture. Late callbacks cannot revive it.

Relevant sources: `SottoAudio/AppleStreamingSpeech.swift`, `AppleSpeech.swift`, `StreamingTranscript.swift`, `RealtimeMicrophone.swift`, `AppleSpeechResources.swift` and `SottoUI/AppModel.swift`.

Framework references: [SpeechAnalyzer](https://developer.apple.com/documentation/speech/speechanalyzer), [SpeechTranscriber](https://developer.apple.com/documentation/speech/speechtranscriber), [finalization](https://developer.apple.com/documentation/speech/speechanalyzer/finalizeandfinishthroughendofinput()), [WWDC session](https://developer.apple.com/videos/play/wwdc2025/277/).

## One shortcut, explicit submission

- **Hold to talk** is the default. Hold, speak, release to submit. A short tap uses the existing double-tap detection window.
- **Double-tap** latches that recording; release your keys, then click Send when finished.
- **Press to toggle**, in General, uses the same saved shortcut: press to begin, press again to submit. Releases do nothing.
- Menu-bar activation and the capsule's Send button remain available without keyboard access. Escape cancels.

There is no silence-triggered submission, always-listening microphone, wake word or automatic follow-up recording. Follow-up questions preserve context; the user explicitly activates recording to reply.

## Safe preparation and execution

Voice's **Prepare commands during pauses** allows inference after both the transcript and audio have been quiet for 650 ms. Preparation uses the already available, consented reasoning engine. It does not launch/install engines, download models, ask for new credentials or silently switch providers. When remote reasoning is selected and allowed, provisional text may be sent to that provider during the pause; Voice settings discloses this. Turn the setting off to wait for final transcription before inference.

Preparation is limited to two attempts per recording, each with an eight-second cancellation budget. Resumed speech, changed words, cancellation, relevant settings changes and new requests invalidate it. The prepared first turn is reusable only when the finalized words match after whitespace/terminal-punctuation normalization, conversation context and provider/model/destination/local-day identity match, and the draft is less than 15 seconds old. Otherwise normal reasoning starts from the final request.

`AgentRuntime.prepareTurn` can generate a tool proposal but cannot authorize or execute one. After explicit submission and confirmed transcription, `AgentRuntime.run` validates the proposal and uses the same trusted authorization, permission, schema, native integration and actual-result path as other requests. Even deterministic reversible commands wait for final transcription. Existing native routing avoids inference for supported requests such as opening Downloads or controlling Spotify. Complex requests use the existing reasoning loop.

`SpeechRecognitionProvider` remains the backend boundary: start with live updates, finish with a confirmed transcript, cancel and declare legacy speech-authorization requirements. Future Whisper/cloud implementations can use it without changing tool execution policy. The optional [OpenAI Realtime adapter](REALTIME-TRANSCRIPTION.md) uses this same boundary.

## Bounded modern backend startup

After microphone permission is granted, modern Apple backend initialization has an eight-second deadline covering worker locale resolution, format negotiation, analyzer preparation/start and first-buffer capture. Timeout returns a retryable error without waiting for a framework suspension that ignores task cancellation. Cancellation likewise returns promptly. The first result wins exactly once; failure invalidates the recording token synchronously and schedules backend cleanup. A late framework return still checks session ownership before installing state. macOS permission dialogs are outside this deadline.

This bounds the caller's wait, not the duration of an Apple API or blocked hardware driver. Cleanup can continue after the error, and the earlier Apple backend capability/asset-selection query remains separate. No partial transcript is submitted by this failure path.

## Measurement

`VoiceLatencyTrace` uses monotonic uptime. Physical shortcut activation uses the event timestamp; button activation uses the invocation time. Voice → Advanced shows the most recent measured phases. Unified logs under `org.sotto.mac`, category `voice-timing`, contain durations only, never transcripts or keys.

| Metric | Boundary |
| --- | --- |
| `activationToMicrophoneReadyMs` | Activation to successful speech/capture startup, including permission and analyzer preparation |
| `activationToFirstPartialMs` | Activation to first nonempty provisional result |
| `microphoneToFirstPartialMs` | Successful startup to first provisional result |
| `inputEndToFinalMs` | Explicit Send/release handling to confirmed transcription; this is not acoustic last-word detection |
| `activationToFirstActionMs` | Activation to first runtime tool-execution state |
| `activationToVerifiedCompletionMs` | Activation to successful request completion with actual tool-result evidence |
| `inputEndToFirstActionMs` | Send/release to first runtime action, excluding speaking time |
| `inputEndToVerifiedCompletionMs` | Send/release to verified successful completion |
| `finalTranscriptToFirstActionMs` | Final recognition to first runtime action |

Repeated physical sessions can be exported without transcript/audio content:

```sh
python3 Scripts/voice_benchmark.py --last 15m > build/voice-benchmark.json
python3 Scripts/voice_benchmark.py --input build/voice-log.ndjson
```

The report contains at most 100 recent activation IDs, activation-relative phase durations, measured Send/final/action intervals and terminal outcomes. It reads only Sotto's `voice-timing` log category and excludes test processes. No recording is started by this command. Only sessions whose activation marker appears in the selected window are included; truncated sessions remain incomplete. Logs predating this instrumentation produce no samples. A transcription-only result has no verified action; canceled, failed, replaced, questioning, intelligence-setup and changed-input sessions retain distinct outcomes. Route recovery ends the original sample so its discarded partial text cannot masquerade as a successful benchmark. Recovery behavior continues normally.

For physical acceptance, record the OS/hardware, speech backend/language, shortcut mode and microphone/output route alongside the report. Run the first attempt after app launch separately from five subsequent repetitions, then test correction, Escape during startup/finalization and another successful attempt. App relaunch alone does not establish an uncached system speech model. Do not pool transcription-only checks with voice-to-action checks. Save actual observations of capsule behavior and external tool results; timings alone do not certify them.

Send/release time is recorded immediately, including when startup is still pending. The remaining startup wait is part of Send-to-final timing.

Missing phases remain absent. A spoken answer or canceled recording is not reported as verified task completion. The panel is ordered before asynchronous speech startup; microphone/model initialization still takes time.

Audio startup overlaps audio-format negotiation and analyzer preparation after explicit activation; bounded captured PCM waits for the analyzer. Canceled or replaced locale/format/analyzer lookups cannot install state into a newer recording. A pending first-buffer capture is canceled before startup task teardown waits for it; finalization retains its own result reader. Native requests never wait for speculative inference. Apple tool selection uses capability descriptions and a short planning field; the selected argument schema is provided afterward, with no unused conversational reply generated before an action. See the November 16 response-latency entry in VALIDATION.md for measured results and rejected experiments.

Validation on this Apple Silicon Mac with macOS 27/Xcode 27:

- Offline suite: 164 passed, 11 opt-in tests skipped, zero failures (175 discovered). Includes revisable/final range handling, zero preparation side effects, trusted approval, changed final request/context/provider/expiry, pause invalidation, native routing, toggle events, persistence and timing arithmetic.
- Real on-device analyzer with synthetic speech: provisional text arrived while input was still open; final text was confirmed after closing input. First provisional result took **1,404 ms from analysis startup**; input end to final took **27 ms** in this one run. This used production recognition with injected PCM, no microphone, cloud or actions.
- Signed-app native controls and local capture were inspected; the transcription-only entry and Escape returned to an idle microphone state. Logs also contain a **6,227 ms cold startup**, a **219 ms subsequent startup** and an **84 ms input-end-to-final interval**. These are individual observations, not a controlled human-speech benchmark or latency guarantee. Cold-start improvement remains outstanding.
- Build and strict code-signature verification passed. No claims of matching Atticus/Wispr latency, Intel/minimum-OS runtime acceptance or full physical voice-to-tool acceptance are made by these tests.

Run the on-device integration test explicitly:

```sh
SOTTO_MODERN_SPEECH_TEST=1 swift test --filter LiveModernSpeechTests
# If the test identity needs system language assets:
SOTTO_MODERN_SPEECH_TEST=1 SOTTO_PREPARE_SPEECH_ASSETS=1 swift test --filter LiveModernSpeechTests
```

## Manual acceptance still required

1. Hold the shortcut and speak several words. Verify evolving text appears before release; release and verify one real native action, then inspect timing phases.
2. Correct yourself mid-sentence. Verify the final correction controls execution, with no action during a pause. Repeat with remote preparation disabled.
3. Double-tap and release both keys; verify listening continues until Send. Select press-to-toggle and verify the second press submits. Restore your preferred behavior.
4. Escape during startup, capture, finalization and prepared reasoning. Verify the microphone indicator clears, no action follows and the next activation works.
5. Try silence, a long recording, a missing asset/unsupported locale, denied permissions, unavailable reasoning, a disconnected microphone and a route change. Failures must not submit partial words.
6. Check actual Spotify/Finder/Reminders results, OS consent and consequential-action blocking. Test minimum macOS/Intel, VoiceOver, Reduce Motion and external display layouts separately.
