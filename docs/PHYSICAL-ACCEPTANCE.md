# Physical acceptance session · November 16, 2026

This record covers the actual running signed Debug app. Automated tests, synthetic audio and universal compilation are recorded separately in VALIDATION.md. Pending rows are not passed tests.

## Observed starting configuration

- macOS 27.2.1 (26B131), arm64.
- One normal command-enabled Sotto process; no shortcut diagnostic override.
- Native General UI: Option + Command modifier shortcut, Hold to talk, global shortcut Ready, Pause off.
- Native Voice UI: MacBook Air Microphone, Apple Speech, English (United States), live on-device transcription ready, require on-device recognition on.
- Native Permissions UI: Microphone, Speech Recognition and Input Monitoring Allowed. Calendar and Accessibility also Allowed; Reminders Not requested. No grants were changed.
- Core Audio inventory: built-in microphone is default input; MacBook Air Speakers are default/system output, both 48 kHz. Virtual BlackHole/Teams/aggregate devices are present. No Bluetooth audio device appeared in this inventory; Bluetooth-output acceptance is pending.

## First observed sample

The pre-test log export contained one activation, session E55CEBFC-C1B6-4AFD-A814-FB7208D8464E, at 15:18:52 local time. Microphone-ready elapsed time was 357.850709 ms; input ended at 602.519626 ms. The outcome was failed, with no recorded partial/final transcript, first action or verified completion. The agent log reports ToolError without its contents. The exact user speech and visible error were not observed, so no specific failure cause is established. This is not a successful latency benchmark.

The baseline export is local at build/voice-acceptance-before.json (ignored by Git). Native inspection did not start a recording, change preferences, request access, upload content or execute a command.

## First physical batch results

The user confirmed “opened correctly and Escape canceled.” The same running app (process 97370) recorded six new sessions between 15:56:23 and 15:57:02 local time. Four requests used the native provider and reached verifiedCompletion. A later activation ended cancelled, with no input-end, final-transcript or action phases. This supports hold/release and Escape preventing the canceled request; the user's report establishes the visible Downloads result.

One earlier request used Apple reasoning, executed a runtime action and ended with a clarification question. Its transcript and question were not inspected, so it is retained separately rather than called a clean success, a routing bug or a speech failure. The earlier failed baseline is also kept separate. No claim is made that every attempt in the window was successful.

| Session | Outcome | Microphone ready, ms from activation | Send to final, ms | Send to verified completion, ms |
| --- | --- | ---: | ---: | ---: |
| 4D2F442E-CDF8-4CC7-A5E4-3BE0975A4A91 | Question; Apple reasoning | 293.0 | 130.0 | — |
| 52FF0988-479D-48A8-A3BB-0E707E83D6CF | Verified; native | 216.4 | 105.1 | 292.3 |
| AEF910E2-C258-4D9E-9AEE-C6AD4667BF70 | Verified; native | 295.0 | 55.8 | 279.0 |
| D8E92E33-1EFC-44C5-BA02-766D2B464234 | Verified; native | 225.7 | 62.5 | 295.9 |
| 947B49FD-A540-4ED2-B724-EE11F2ED572D | Verified; native | 233.4 | 94.9 | 237.8 |
| 097E3896-5F81-45C6-9687-0E71F5DB48E2 | Cancelled; no submission/action | 206.9 | — | — |

The content-free batch export is build/voice-acceptance-batch-1.json (ignored by Git). These are observations of this batch, not an uncached cold-start benchmark or a cross-device performance guarantee. Native audio-route logs report the selected 48 kHz input and outputDisabled=true during capture. Bluetooth, alternate shortcut modes, cancellation during startup/finalization and successful reactivation after Escape remain separate checks.

## Double-tap hands-free result

The user confirmed that Sotto kept listening after both keys were released, waited for Send and then opened Downloads. Session 4E7561CB-AD4F-4ABE-B84B-699B2E460549 began at 16:21:37.550 local time in the same process (97370); the keyboard adapter logged Hands-free recording latched at 16:21:37.701. Input ended at activation + 9676.815083 ms. Native submission and first action followed input end; verifiedCompletion followed at activation + 10013.443042 ms. No submission/action phase is present before input ended. The user's report establishes the actual Send click and visible folder result; the logs establish the latch and action ordering.

Observed microphone-ready time was 293.631208 ms, input-end-to-final 59.405667 ms, input-end-to-first-action 136.502000 ms and input-end-to-verified-completion 336.627959 ms. This is one physical hands-free sample, not a cold-start or repeated-mode benchmark. The content-free export is build/voice-acceptance-double-tap.json (ignored by Git).

This successful activation also demonstrates that a later recording and native command worked after the previous Escape cancellation in the same process. Microphone-indicator clearing at the time of that cancellation was not separately observed. Toggle, corrections and cancellation during startup/finalization remain pending.

## Press-to-toggle result

The user confirmed that the second Option + Command press submitted the request, Downloads opened and Hold to talk was restored afterward. Session B777A6C7-804A-448F-B184-9065EA69E822 began at 21:06:27.113 local time in the same app process (97370). Input ended at activation + 4607.372959 ms; final transcription, native submission, first action and verifiedCompletion all followed. The user report establishes the second-press trigger and restored preference; generic phase logs alone do not identify a physical press or the stored shortcut mode. Listener-ready messages bracket this test at 21:06:18 and 21:06:52.

Observed microphone-ready time was 330.683792 ms, input-end-to-final 93.368708 ms, input-end-to-first-action 142.238417 ms and input-end-to-verified-completion 353.424792 ms. This is one physical toggle test, not repeated-toggle or cold-start certification. The content-free export is build/voice-acceptance-toggle.json (ignored by Git). Spoken corrections and cancellation during startup/finalization remain pending.

## Spoken correction failure and fix awaiting physical retest

The user reported failure, then clarified the actual spoken request: “Open downloads--actually open documents.” Downloads opened instead of the corrected Documents destination. Native Activity showed one Downloads open at 21:08; session 9620C5D9-5365-49A2-A13A-3269F41FE188 used Apple reasoning and reached runtime verifiedCompletion. Action started only after input end, so the observed failure concerns the final destination. A verified tool result confirms that an action occurred; it does not certify that the action matched the corrected user intent. The recognized transcript was not inspected/retained, so no transcription root cause is claimed. The failure is saved locally in build/voice-correction-failed.json.

Implemented a full-request native grammar for two or three explicit standard-folder corrections, selecting only the last destination. Exact reported wording, reversed direction, punctuation and multiple corrections pass. Negated, quoted, unsupported or additional work stays outside that grammar; conjunctions continue to execute both requested actions. General runtime and on-device planning guidance now treat explicitly withdrawn intent as withdrawn, including after another action completes. All actions retain the existing schema, authorization and tool-result path.

Validation: 234 Swift tests discovered, 215 passed, 19 opt-in skipped, zero failures. Four new offline regressions include execution of the reported correction through the real runtime with a probe folder tool and no desktop effect. A separate real Apple-intelligence test passed using fixture tools, executing only Documents and not returning to Downloads after completion. Signed Debug build and strict signature verification passed. The updated app was relaunched normally; actual General UI confirms Option + Command, Hold to talk, Ready and Pause off. No permissions or preferences were changed by the fix/verification tools. Physical speech-to-Documents retest remains pending.

## Polite question diagnosis and installed fix

After the correction fix, the user reported that imperative requests pass but polite questions fail. The initial reported example “Can you please open Documents?” already passed an exact runtime regression before any further production change. The user then ran the transcription-only check and supplied its actual final text: “Could you open documents, please?” This establishes the concrete parser gap: trailing comma/please prevented a known folder match. The earlier screenshot's request for a document path is consistent with the fallback interpreting a generic document. The question mark itself was already stripped correctly. The user's transcription-only check executed no command.

Folder matching now shares one anchored grammar for known Downloads/Documents/Desktop requests: polite prefixes, my/the, optional folder and trailing please (with optional comma). Explicit corrections use the same grammar for each folder clause. Unknown/singular documents, indirect how-to questions, negations, conditions and unsupported additional work still do not become native folder commands. No global deletion of “please” from arbitrary file names or requests was added.

The exact screenshot phrase executes only Documents through the real runtime with a probe tool, without reasoning or a path question. Polite corrections likewise execute only the final destination. Seven correction/politeness checks pass; the full suite reports 237 discovered, 218 passed, 19 opt-in skipped, zero failures. Signed Debug build and strict signature verification passed. Relaunched the updated normal app and inspected General: Option + Command, Hold to talk, Ready, Pause off. Physical retry of the polite question remains pending; the imperative correction success is user-reported separately.

## Polite folder request physical retry passed

The user confirmed “Documents opened directly” without another file-path question. The updated normal app (process 66961) recorded session 2934660B-9E98-4948-9B3A-5605247005B4 at 21:25:12.950 local time. After input end, confirmed transcription was submitted through the native provider, followed by firstAction and verifiedCompletion. No reasoning-provider submission was recorded for this session. The user's observation establishes the Documents destination and lack of clarification; content-free logs establish the direct route and tool-result ordering.

Observed microphone-ready time was 328.745292 ms, input-end-to-final 112.159583 ms, input-end-to-first-action 162.551250 ms and input-end-to-verified-completion 305.124041 ms. The single-session export is build/voice-polite-acceptance.json (ignored by Git). This closes the exact polite-folder regression on this Mac. The initial failure and transcription-only evidence remain above; arbitrary polite requests and polite multi-correction combinations are not certified by one successful retry.

## Early-recording cancellation and immediate recovery

The user reported clean cancellation, microphone shutdown and a successful following Documents request. The attempted startup-cancellation session B268BE5A-79E3-4B59-873A-FEDBBD9AD1EA began at 21:26:38.206 local time. MicrophoneReady was recorded at 21:26:38.476 (270.568375 ms); cancellation followed at 21:26:38.478. There is no inputEnded, finalTranscript, firstAction or verifiedCompletion for this session. It is therefore early-recording cancellation, not proven cancellation during pending startup. The user observation establishes capsule/microphone behavior.

The following session 3D7E207E-F728-4432-BB0A-8720BFA66368 began at 21:26:43.647 and reached verifiedCompletion via the native provider after input end. The user confirms the Documents result. This establishes recovery in the same process (66961). The local two-session export is build/voice-early-cancel-acceptance.json (ignored by Git).

Read-only system audio inventory after the batch shows built-in speakers as output and Aggregate Device as the system default input; the capture log still verifies device 107, the selected built-in input used in the earlier app checks. No Bluetooth audio device is currently connected. No route or preference was changed by verification tools. Strict pre-readiness cancellation, finalization interruption and Bluetooth/physical device changes remain pending.

## Physical tests

| Test | Status | Required observation |
| --- | --- | --- |
| Hold shortcut through “Open my Downloads folder,” then release; repeated | Passed on this Mac: user + runtime evidence | User confirms Downloads opened correctly; four native requests recorded verified completion |
| Escape during another activation | Requested behavior passed: user + runtime evidence | User confirms cancellation prevented the action; canceled log sample has no inputEnded/finalTranscript/firstAction/verifiedCompletion. A subsequent double-tap activation and verified command now establish reactivation after Escape; a later early-recording cancellation test now includes user-confirmed microphone shutdown |
| Double-tap hands-free, then Send | Passed on this Mac: user + runtime evidence | User confirms listening survived key release and action waited for Send; hands-free latch and subsequent native verified completion logged |
| Explicit press-to-toggle mode | Passed on this Mac: user + runtime evidence | User confirms second press submitted, Downloads opened and Hold to talk was restored; native verified completion logged after input end |
| Spoken correction during a pause and related polite folder request | Imperative correction passed per user; polite folder question passed with runtime evidence | User confirms corrected imperative behavior and direct Documents opening for “Could you open documents, please?”; native verified completion recorded after submission. Polite correction combinations remain fixture-tested only |
| Early-recording cancellation and recovery | Passed on this Mac: user + runtime evidence | User confirms clean cancellation/microphone stop and working next Documents command; canceled sample has no submission/action and following sample is verified |
| Cancellation before microphone readiness | Pending precise physical observation | The attempted startup test canceled just after readiness, so it does not establish the before-ready case |
| Finalization cancellation | Pending | Cancel while final transcription is pending; no late action; next recording works |
| Bluetooth output with built-in input | Deferred: user has no Bluetooth headphones available | Remains a release acceptance check on suitable hardware; neither passed nor failed |
| Physical input disconnect/reconnect | Pending hardware availability | Recording discarded/recovered as documented; incomplete words never submitted |
| Spoken Calendar agenda | Passed on this Mac: user + runtime evidence | User confirms tomorrow's agenda matched Calendar; native submission and verified completion logged. Agenda contents were not shared/read by verification tools |
| Spoken Calendar creation and permission edges | Pending | Actual event/save/read-back evidence; fresh/revoked consent checked separately |
| User-selected document summary | Pending user document choice | Facts verified against the selected document using the selected intelligence destination |

The initial user test asks for three hold/release Downloads commands and one Escape cancellation. Physical gestures must be performed by the user; synthesized key events are not counted as physical shortcut acceptance.

Export after the user completes a batch:

```sh
python3 Scripts/voice_benchmark.py --last 20m > build/voice-acceptance-after.json
```

Compare activation IDs with the baseline. Keep failures and canceled/recovered samples separate from verified completion. Record user-confirmed visual behavior alongside durations. The report does not certify acoustic latency, first-frame rendering, minimum macOS, Intel runtime or assistive-technology use.

## Hardware availability update

The user confirms no Bluetooth headphones are available for this session. The Bluetooth-output/built-in-input test is deferred for hardware availability, with no pass/fail claim or route change. Continue with read-only voice-to-Calendar agenda acceptance; do not substitute virtual devices or built-in speakers as Bluetooth evidence.

## Voice-to-Calendar agenda passed

The user confirms that the spoken tomorrow-agenda result matched the Calendar app. Session A241923D-AB94-4ECA-85A9-7B95BC50D648 began at 21:29:00.418 local time in the updated normal app (66961). Confirmed transcription, native submission, first action and verifiedCompletion followed input end. The user comparison establishes agenda correctness; the content-free logs establish the real voice/native execution path. No event titles, times, account contents or transcript bodies were inspected by verification tools.

Observed microphone-ready time was 256.116792 ms and input-end-to-verified-completion 188.430166 ms. The single-session export is build/voice-calendar-agenda-acceptance.json (ignored by Git). This closes one authorized physical voice-to-agenda check on this Mac. The user did not specify empty/all-day content, so those cases are not separately marked passed. Spoken creation, fresh/revoked consent, other calendar configurations and broader hardware remain pending.

## Manual acceptance paused

The user requested that testing stop on November 16. Remaining user-operated rows, including spoken event creation, remain pending; no result is inferred from that stop. Roadmap implementation resumed on November 17 with generated-fixture automated checks only and no further manual-test prompts.
