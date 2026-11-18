# Validation record

## Local OCR for requested scanned PDFs · November 17, 2026

Continued implementation with manual acceptance paused at the user's request. Added Apple Vision OCR fallback for PDF pages without non-whitespace embedded text. The existing user-supplied-path/current-search scope, schema/authorization and local extraction policy remain intact. OCR works only within an explicitly requested PDF read; it does not collect screens, scan background files, upload images or read additional formats.

The reader prefers embedded text and preserves page order. Existing 20 MB, 50-page and 16,000-character limits remain; OCR adds a five-textless-page attempt budget and a raster with at most a 2,000-pixel longest edge (four million pixels). Rendering honors PDF media-box rotation and bounds finite dimensions before allocation. Later embedded-text pages can still be read after the OCR budget is exhausted. Failed/skipped pages mark results partial; one-based attempted/recognized/skipped/unreadable page arrays provide explicit provenance. Summaries disclose OCR uncertainty, partial/excerpt text and omitted pages. Raster/body content stays out of activity summaries. Extracted text goes only to the selected reasoning provider under existing consent.

Recognition uses the actual Apple Vision accurate request with language detection/correction. Cancellation requests Vision cancellation and checks before returning any OCR or earlier partial text. These are data/work bounds, not a wall-clock guarantee; native PDF parsing and recognition can take time. Pages already containing embedded text are not OCRed, so image-only regions there can be omitted. OCR may misread words, numbers, reading order and layout; no arbitrary scan/handwriting/table accuracy guarantee is made.

Seven new automated checks pass. An actual raster-only PDF has no embedded PDFKit text, then the production Vision path extracts its Friday deadline and 200-dollar budget. Other generated fixtures verify embedded-text preference, mixed-page order and the five-page cap, failed-page partial metadata, cancellation discarding earlier content, shared character bounds and rotated raster dimensions. Existing blank/oversized/invalid/path-scope checks still pass. Fixtures are generated locally and removed afterward; no personal document, microphone, account or live reasoning provider is used. Real in-flight Vision cancellation under arbitrary OS/hardware conditions is not separately certified by the injected cancellation fixture.

Final `swift test`: **244 discovered, 225 passed, 19 opt-in skipped, zero failures**. Signed Debug application build and deep/strict signature verification passed. The unsigned universal Release build passed; lipo/vtool inspection confirms x86_64 and arm64 slices at the macOS 14.0 floor. This is compile/package evidence, not minimum-OS/Intel runtime acceptance or official notarization.

Relaunched the updated normal signed app without diagnostic flags, microphone capture, permission or preference changes. A transient native launch-inspection timeout was resolved by reading the new actual General screen: Option + Command, Hold to talk, Ready, Pause off. No user-operated test was requested. Manual acceptance and personal-document summary checks remain paused/pending. [DOCUMENTS.md](DOCUMENTS.md) records capability, privacy and limits; the roadmap now marks bounded scanned-PDF OCR implemented while additional formats/chunked summaries remain work.

References: Apple's [Vision text recognition](https://developer.apple.com/documentation/vision/vnrecognizetextrequest) and [Core Graphics PDF transforms](https://developer.apple.com/documentation/coregraphics/cgpdfpage).

## User-operated voice-to-Calendar agenda passed · November 16, 2026

The user confirms that “What's on my calendar tomorrow?” matched tomorrow in the Calendar app. The actual updated app records session A241923D-AB94-4ECA-85A9-7B95BC50D648 with final transcription, native submission, first action and verifiedCompletion after input end. The user's comparison establishes the agenda's correctness. Verification tools inspected only phase/route logs, not event titles, event details, transcript bodies or account contents.

Recorded the sample and limits in [PHYSICAL-ACCEPTANCE.md](PHYSICAL-ACCEPTANCE.md), with a local content-free export at build/voice-calendar-agenda-acceptance.json. This closes a real authorized voice-to-agenda check on this Mac. Empty/all-day content was not specified, so neither is claimed as separately tested. Spoken creation, fresh/revoked consent and other calendar/account configurations remain separate checks. No code, settings, permission, recording or calendar state was changed by verification tools during this pass.

## Bluetooth acceptance deferred for hardware availability · November 16, 2026

The user reports no Bluetooth headphones available. Marked Bluetooth-output/built-in-input acceptance deferred, with neither a pass nor a failure. Earlier inventory likewise showed no connected Bluetooth audio device. No Bluetooth, microphone, output, permission or application preference was changed. This hardware check remains a release gate; read-only physical voice-to-Calendar agenda acceptance can proceed independently.

## Early-recording cancellation, microphone stop and recovery · November 16, 2026

The user confirms clean Escape cancellation, Sotto stopping microphone use and a successful next Documents command. Real-app session B268BE5A-79E3-4B59-873A-FEDBBD9AD1EA ended cancelled with no inputEnded, finalTranscript, firstAction or verifiedCompletion. MicrophoneReady occurred just before cancellation, so the evidence closes early-recording cancellation rather than strictly-before-readiness cancellation. Capsule/microphone shutdown is user-observed.

The subsequent session 3D7E207E-F728-4432-BB0A-8720BFA66368 reached verifiedCompletion through the native provider after input end in the same process. This supports the user-confirmed recovery/visible Documents result. Exact ordering and the local export are recorded in [PHYSICAL-ACCEPTANCE.md](PHYSICAL-ACCEPTANCE.md). Read-only audio inventory shows no Bluetooth audio device currently connected, built-in speakers as output and Aggregate Device as system default input. App capture logs still verify the selected input device used in the preceding built-in checks; no input/output preference was changed by verification tools.

Strict pending-startup cancellation, finalization cancellation and broader hardware acceptance remain separate checks. This pass read content-free logs/audio inventory and updated documents only; it initiated no recording, command, model request, code change or permission change.

## Polite Documents request physical retry passed · November 16, 2026

The user confirms that “Could you open documents, please?” now opens Documents directly without asking for a file path. The updated normal app records session 2934660B-9E98-4948-9B3A-5605247005B4 with confirmed transcription, native submission, first action and verifiedCompletion, all after input end. No reasoning submission appears for that session. The user report establishes the destination/visible behavior; logs establish the direct route and verified tool result.

Recorded the exact sample in [PHYSICAL-ACCEPTANCE.md](PHYSICAL-ACCEPTANCE.md); local content-free export is build/voice-polite-acceptance.json. The imperative correction retry was already user-confirmed. This closes the exact polite folder regression while leaving the original failures in the record and keeping broader language variations, startup/finalization cancellation, cold-start and hardware/accessibility acceptance separate. No code, preference, permission, recording or agent action was changed/started by verification tools during this pass.

## Polite folder question: exact transcription diagnosis and fix · November 16, 2026

The user reports that imperative corrections now work but polite questions do not. Their initial example “Can you please open Documents?” passed a newly added exact runtime regression against the existing code, so punctuation alone was not assumed to be the cause. Asked for a transcription-only check; the supplied screenshot shows the actual final recognized text: “Could you open documents, please?” No command ran during that check. This exact phrase was outside the native grammar because of trailing comma/please and fell through to reasoning; the earlier screenshot shows a reply requesting a document path. Leading courtesy and the final question mark were already supported.

Replaced duplicated folder matching with a shared full-request grammar for Downloads/Documents/Desktop, accepting ordinary courteous prefixes, my/the, optional folder and trailing please with an optional comma. Each clause of a bounded folder correction uses the same grammar. This does not globally strip courtesy words, reinterpret singular “document” as the Documents folder, drop conditions or bypass tool validation/authorization. Requests for an unspecified document continue to require details.

The exact screenshot request passes through the real runtime with a probe folder tool, opening only Documents without reasoning or clarification. Additional tests cover polite variants, polite corrected destinations and refusals to route ambiguous, negated, indirect, conditional or unsupported requests natively. Existing correction/conjunction checks also pass. `swift test`: **237 discovered, 218 passed, 19 opt-in skipped, zero failures**. Seven correction/politeness checks passed. No live reasoning call was required for this parser change; the preceding correction entry records the earlier real Apple model fixture test.

Signed Debug build and deep/strict signature verification passed. Relaunched the normal updated app through native UI. After a transient launch-inspection timeout, actual General UI confirmed Option + Command, Hold to talk, Ready and Pause off. No preference/permission change or command/microphone capture was initiated by verification tools. Physical polite-question retry remains pending; the user's imperative-correction success is recorded separately in [PHYSICAL-ACCEPTANCE.md](PHYSICAL-ACCEPTANCE.md). No new universal Release build is claimed for this change.

## Spoken correction failure, bounded native fix and reasoning regression · November 16, 2026

The user clarified that they said “Open downloads--actually open documents” and Sotto opened Downloads. Inspected actual native Activity: the 21:08 entry confirms Downloads. Session 9620C5D9-5365-49A2-A13A-3269F41FE188 latched hands-free, submitted through Apple reasoning after input end and reached a verified tool result. This is a semantic acceptance failure despite runtime verifiedCompletion. No action was recorded before input ended. The recognized words were not inspected, so this evidence does not establish whether transcription also differed.

Added an anchored, bounded correction grammar to NativeCommandProvider for explicit revisions among Downloads, Documents and Desktop. Every clause must be a known folder-opening command, with one or two correction markers; only the last destination produces a step. Unknown/negated/quoted/additional work cannot be silently discarded to obtain a native match. Additive conjunctions retain both actions. Runtime instructions and Apple's remaining-work guidance now exclude withdrawn intent from execution, while preserving actual additions and asking when final intent is unclear. No arbitrary request trimming, model-authored path authorization, new tool, shell execution or credential handling was added.

Four new offline regressions pass: exact reported wording executes only Documents through the real runtime with a probe tool; reverse/punctuation/multiple-correction variants select the final folder; ambiguous/negated/unsupported cases do not enter the correction route; additive folder requests still execute both. `swift test`: **234 discovered, 215 passed, 19 opt-in skipped, zero failures**. Separately ran the actual on-device provider correction loop using fixture tools: **passed**, with exactly one Documents execution and no later execution of withdrawn Downloads. No physical microphone, native folder opening, cloud or personal document was used by these tests.

Signed Debug build and deep/strict signature verification passed. Quit the old app and relaunched the updated normal copy. A transient native inspection timeout was resolved by checking process/lifecycle state and then the actual General UI, which reports Option + Command, Hold to talk, Ready and Pause off. No permission/preference change was made by the verification tools. Physical retry remains required; the correction row in [PHYSICAL-ACCEPTANCE.md](PHYSICAL-ACCEPTANCE.md) remains failed/fixed-awaiting-retest rather than passed. The previous universal Release evidence predates this fix; no new Release build is claimed in this entry.

## User-operated press-to-toggle and preference restoration · November 16, 2026

The user confirmed that in Press to toggle mode the second Option + Command press submitted the request, Downloads opened, and Hold to talk was restored afterward. The new real-app session records input end followed by confirmed transcription, native submission, first action and verifiedCompletion. The log contains no submission/action phase before input ended. Generic phase markers do not identify which physical input caused submission; the user's observation establishes the second press and mode restoration.

Recorded session B777A6C7-804A-448F-B184-9065EA69E822 and its durations in [PHYSICAL-ACCEPTANCE.md](PHYSICAL-ACCEPTANCE.md), with a local content-free export at build/voice-acceptance-toggle.json. This closes one physical press-to-toggle test on this Mac. Combined with preceding evidence, hold/release, double-tap/Send and press-to-toggle now have user-confirmed real-command acceptance. Corrections, startup/finalization cancellation, cold-start benchmarking and broader hardware/accessibility checks remain separate.

Verification only read content-free logs and updated records; no code, preferences, permissions, recordings, model calls or agent actions were changed/started by the verification tools.

## User-operated double-tap hands-free and Send · November 16, 2026

The user confirmed that double-tapping Option + Command kept listening after both keys were released, performed no action until Send, then opened Downloads. The actual app's keyboard log records Hands-free recording latched for the new session; its voice-timing log records input end followed by native submission, first action and verifiedCompletion. No submission/action phase appears before input ended. User observation supplies the click/visible-folder evidence; content-free logs supply the gesture latch and runtime ordering.

Recorded exact session ID/durations in [PHYSICAL-ACCEPTANCE.md](PHYSICAL-ACCEPTANCE.md), with a local content-free export at build/voice-acceptance-double-tap.json. This closes one physical double-tap/Send test on the current Mac and also establishes a successful later recording/action after the previous Escape cancellation, in the same app process. It does not certify repeated hands-free behavior, cold startup, toggle, spoken corrections, microphone-indicator clearing or startup/finalization cancellation.

Only logs and source labels were read and acceptance documents updated. No recording, UI action, preference/permission change, model call or agent action was triggered by the verification tools.

## First user-operated hold/release and Escape batch · November 16, 2026

The user confirmed that Downloads opened correctly and Escape prevented the final action. Read the real running app's content-free voice-timing/audio-route/agent logs, without starting another recording or reading transcript/history bodies. Four new native requests reached verifiedCompletion. A later activation ended cancelled without inputEnded, finalTranscript, firstAction or verifiedCompletion; no submission/action was logged for that session. This closes repeated hold/release and the requested Escape-prevents-action behavior on this Mac with the current Option + Command shortcut, built-in input and on-device Apple Speech.

An earlier new request used Apple reasoning and ended in a clarification question after a runtime action. Its words and question were not inspected, so it remains separate from the four successful native runs. The failed pre-batch baseline also remains in the record. No universal success rate, root cause for the question, uncached cold-start or cross-device latency claim is made.

Exact session IDs/durations and evidence limits are recorded in [PHYSICAL-ACCEPTANCE.md](PHYSICAL-ACCEPTANCE.md); the local content-free export is build/voice-acceptance-batch-1.json. Microphone-indicator clearing, successful activation after Escape, double-tap/toggle, corrections, startup/finalization cancellation, Bluetooth/disconnect, accessibility and other OS/hardware remain pending. No code, preferences, permissions or running-app state was changed during this verification.

## Physical acceptance baseline · November 16, 2026

Inspected the actual running signed Debug app's native General, Voice and Permissions screens. The Option + Command modifier shortcut is configured for Hold to talk and reports Ready. Built-in microphone, English on-device Apple Speech and required voice/keyboard grants are ready. Read-only system audio inventory reports built-in microphone and speakers as default input/output at 48 kHz; no Bluetooth device was connected. No preferences or permissions were changed and no recording or tool action was started by this inspection.

A recent real-app log sample reports microphone readiness at 357.850709 ms and input end at 602.519626 ms, followed by a failed outcome/ToolError. No partial/final transcript or verified action phase was recorded. User speech and the error's visible contents were not observed, so the cause is unestablished. The failed sample is retained as evidence, not counted as an accepted voice command or a successful cold-start benchmark.

Prepared a user-operated batch of three hold/release Downloads requests plus one Escape cancellation. The follow-up content-free log export still contained only the same failed baseline sample; no new user batch or success is claimed. One normal app process remains running. [PHYSICAL-ACCEPTANCE.md](PHYSICAL-ACCEPTANCE.md) records the observed configuration, exact evidence and pending physical tests.

## Bounded modern speech initialization · November 16, 2026

The physical-session report still contained no new activations, so continued with an independently reproducible startup failure. The previous worker deadline canceled state but could not make its caller return while an awaited Apple API remained suspended; awaiting worker teardown on the error path could also hold that caller. Moved the eight-second production initialization deadline to a one-result coordinator around the modern worker, after microphone authorization. Timeout/cancellation returns without awaiting an uncooperative framework task. Failure synchronously invalidates its session token, cancels pending work/timer and schedules token-scoped cleanup. The provider rechecks cancellation on success and clears only its own failed token.

The coordinator serializes completion, cancellation and deadline races under a lock, including cancellation before continuation/task registration. Original framework errors are preserved. Worker session checks from the earlier pass still reject late results and protect replacement recordings. Permission dialogs are not timed out. This bounds the caller's wait; it cannot forcibly interrupt native OS work or a blocked hardware driver. Earlier capability/asset selection remains a separate phase. No fallback upload, partial submission or idle capture was added.

Five new regressions cover an uncooperative suspended operation, cancellation before it resumes, already-canceled entry with zero framework work, success canceling its deadline and original framework error propagation with exactly one abort. Fixtures explicitly release suspended operations after proving the caller returned. The tests use no microphone, cloud, model, native permission prompt or agent action.

`swift test`: **229 discovered, 211 passed, 18 opt-in skipped, zero failures**. The signed Debug build and deep/strict signature verification passed. The opt-in actual Apple analyzer test now uses the same startup deadline wrapper with synthetic PCM and passed: live provisional text preceded input completion, and the final transcript retained the expected Downloads request. This exercises real local recognition, with no microphone or agent tools.

The unsigned universal Release build also passed. Inspected its actual executable with lipo/vtool: x86_64 and arm64 slices both declare macOS 14.0 minimum. This is compilation/packaging evidence, not Intel/minimum-OS runtime or official notarized distribution.

Gracefully relaunched the updated signed Debug app in normal command-enabled mode and confirmed one new running process, with no diagnostic override or permission/preference change. No physical microphone capture or agent action was triggered.

Physical startup/cancellation, controlled cold-start, native route transitions and minimum-OS/Intel runtime acceptance remain pending. This pass does not label the absence of user speech samples as success.

## Repeatable voice measurements and early release timing · November 16, 2026

Added session-scoped content-free activation, phase and terminal-outcome records to the existing voice-timing category. Cancel/failure/replacement, transcription-only, questions, missing intelligence and verified actions close distinct samples. Microphone recovery closes the original sample as inputChanged so discarded partial timing cannot later appear as a verified success. Terminal logging clears the live trace while preserving the latest visible timings.

Fixed early shortcut release/Send timing: inputEnded is now recorded immediately by endListening, including when speech startup is pending. Previously it was first recorded after startup completed, hiding that remaining wait from Send-to-final and Send-to-action intervals. A real AppModel regression holds injected startup pending, releases, waits 80 ms, then permits transcription to finish; it asserts that this delay appears in the measured interval and no verified action is reported. No microphone, model or native tool is used.

`Scripts/voice_benchmark.py` reads scoped Sotto unified logs or an existing JSON/NDJSON export and emits at most 100 session summaries with measured phase/interval durations and terminal status. It starts no recording and copies no free-form log content into the report. Test processes, malformed/unknown records, negative/nonfinite durations, missing-activation sessions and late callbacks after terminal outcomes are excluded. An outcome label without verifiedCompletion evidence cannot certify an action. No hardware/backend/shortcut-mode comparison is inferred automatically; record those conditions alongside each physical run. The protocol and commands are in REALTIME-VOICE.md.

Validation: **224 Swift tests discovered, 206 passed, 18 opt-in skipped, zero failures**; **six Python report tests passed**. The signed Debug build and deep/strict signature verification passed. Added report tests to CI; no remote CI execution is claimed. Ran the real log-export command successfully: it returned an empty session list, correctly excluding XCTest instrumentation and the previous app's older unstructured logs. Empty output is not physical acceptance.

Gracefully quit the previous app and relaunched one updated normal command-enabled copy through LaunchServices, with no diagnostic override, preference or permission changes. Process inventory and native lifecycle logs confirmed the new launch. No physical speech, shortcut press, microphone capture or agent tool was executed during this pass. User-performed repeated hold/double-tap/toggle, correction, cancellation, route and verified-action checks remain pending.

## Speech startup overlap and session isolation · November 16, 2026

Continued the responsiveness milestone. Modern Apple capture now starts alongside audio-format negotiation as well as analyzer preparation, after explicit activation and native microphone authorization. No idle capture or asset download was added. Pending first-buffer capture has a task cancellation handler so structured startup teardown can stop it. The existing eight-second startup deadline now includes locale resolution.

Session identity/cancellation is checked after asynchronous locale resolution, audio-format negotiation, analyzer preparation/start and capture startup. A generation guard protects replacement during asynchronous previous-session teardown. Unsupported locale failures enter cleanup. Old startup errors cannot borrow a newer session's failure; feeder completion waits for its own result reader; finalization rechecks identity after microphone shutdown before changing shared state.

Two new offline tests suspend locale resolution, cancel or replace the recording, then resume the stale lookup with a valid locale. They assert cancellation, zero capture starts/updates and preservation of the replacement token. Unsupported replacement locales also clean up. These tests use injected locale resolution and capture probes; they never touch the microphone or download speech assets.

`swift test`: **223 discovered, 205 passed, 18 opt-in skipped, zero failures**. The signed Debug application build and deep/strict signature verification passed. `SOTTO_MODERN_SPEECH_TEST=1 swift test --filter LiveModernSpeechTests` also passed against the actual installed Apple analyzer with synthetic PCM: provisional words arrived before input ended, then the confirmed final transcript contained the expected Downloads request. This invocation used no microphone, cloud, credentials or agent tools and requested no asset installation.

This establishes startup/session regressions and continued real recognition after the overlap change. It does not establish a physical cold-start speedup, repeated shortcut performance, first-buffer teardown under a blocked hardware driver, minimum-OS/Intel runtime or accessibility acceptance. Those remain roadmap checks. The Debug app was built and signature-verified; the running app was not relaunched during this pass.

## Real Calendar account acceptance and universal Release · November 16, 2026

Observed the actual signed app's Permissions UI reporting Calendar allowed, without changing any grant. Explicitly launched the Debug-only `--verify-calendar` acceptance mode through LaunchServices. The first run created a uniquely named five-minute event through NativeCommandProvider → AgentRuntime → the real EventKit creation tool, verified identifier/title/start/end, repeated the request with the same registry and confirmed the same identifier, found exactly one owned event and removed it with absence verification. The second run also exercised the production agenda reader in the exact five-minute interval and found exactly one matching event before verified cleanup. Both runs displayed **Calendar check passed** in the actual native capsule. No test events were left behind.

The harness does not request permissions or run inference, and it does not upload or retain unrelated agenda titles. It uses existing full access, real adapters and actual results; the status is not an inert preview. Cleanup is Debug-only and restricted to this run's exact native receipt, unique title, five-minute duration, unchanged dates and no attendees. It is not exposed to the model or included in Release. Escape cancels the harness; any already verified owned event is cleaned up on the error path. Cancellation cannot retract a save already committed.

This closes real-account timed Calendar creation/read/retry/cleanup on this Mac. It does not certify the physical microphone/shortcut path, first-use/revoked consent, arbitrary/default-calendar configurations, real all-day/empty agendas, minimum macOS or Intel runtime. Earlier entries saying account writes were untested are historical and superseded by this result.

`swift test`: **221 discovered, 203 passed, 18 opt-in skipped, zero failures**. The **15 release-policy tests** also pass. Signed Debug build and strict signature verification pass. A separate unsigned **universal Release build** completed for arm64 and x86_64 with the macOS 14 deployment floor. Inspected the actual Release executable/resources and verified that Debug acceptance/review flags are excluded. The unsigned artifact was not launched or distributed and is not a notarized official release.

Added CI steps for release-policy tests and universal unsigned Release compilation. The equivalent local checks passed; no GitHub CI run or publication is claimed. Official Developer ID/notarization credentials, the two-version permission-preservation test, minimum/current OS runtime and physical accessibility acceptance remain release gates. Normal command-enabled Sotto was restored after the account test.

To repeat the account check deliberately, quit the normal app and run `open build/Build/Products/Debug/Sotto.app --args --verify-calendar` with existing Calendar full access. It creates and removes a real disposable test event in the default writable calendar. Never run this flag as unattended CI or against an account without authorization. Quit afterward and reopen normally; this mode intentionally stops the global shortcut to isolate the check.

## Accessible result handling · November 16, 2026

Added direct Summarize buttons to cached PDF/TXT/Markdown results. The supported-format list is shared by extraction, native explicit-path routing and UI availability. AppModel rejects invented, stale, unsupported and busy selections; a legitimate selection submits the exact cached path. Missing intelligence preserves that request in the existing native setup flow. Clicking Summarize uses the selected provider/consent, not an automatic remote fallback.

Short confirmation dismissal now pauses for pointer hover or explicit panel keyboard focus, including when interaction begins before completion. Leaving both restarts a full countdown; cancellation cannot revive it. VoiceOver or Switch Control suppresses the short countdown, and the timer rechecks assistive-reading state before hiding. The existing five-minute context/privacy expiry still applies. Menu-bar Review response explicitly focuses available controls; normal activation still preserves the foreground application. Stable outcomes/questions/approvals post native VoiceOver announcements, with no live-word or microphone-level announcement loop.

Reduce Motion/Reduce Transparency excludes the animated glow subtree and shows a native meter driven by actual microphone levels. Reduce Motion also hides the animated dismissal ring. Native material accessibility fallbacks remain in place.

Validation: **221 tests discovered, 203 passed, 18 opt-in skipped, zero failures**. Five new checks cover assistive result retention, pause/resume/cancel behavior, hover before completion plus independent keyboard focus, stable-only announcements, and exact cached-path summary handoff with rejected forged/unsupported selections. Native signed Debug build, strict code-signature verification and x86_64 cross-build pass. No account, microphone or provider call was required for these regressions; existing real-provider/recognition evidence is recorded in the preceding entries.

Inspected General's actual native accessibility tree, then an explicitly inert `--review-capsule files` fixture. The native tree exposed distinct Open/Summarize/Show in Finder actions and locations, a status heading and no Summarize for DOCX. Controls were intentionally disabled in the fixture. The initial screenshot showed spare list height; fixed that in one batch and confirmed compact rows, visible footer/actions and the preserved glass shell. No file was opened/read/uploaded, no OS accessibility preference/permission was changed and no model inference was performed in this UI review. The normal app was restored afterward.

Actual spoken VoiceOver output, Switch Control use, keyboard traversal with the new review command, reduced-motion/transparency behavior under real OS preferences and minimum-OS/Intel runtime remain manual acceptance. AX labels, source checks and cross-compilation are not accessibility certification. References: Apple's [announcement API](https://developer.apple.com/documentation/appkit/nsaccessibility-swift.struct/notification/announcementrequested) and [VoiceOver state](https://developer.apple.com/documentation/appkit/nsworkspace/isvoiceoverenabled).

## Calendar creation, document understanding and release checks · November 16, 2026

Implemented personal Calendar event creation through EventKit's real default writable calendar, synchronous save and exact title/time read-back. Start/end and title validation precede the adapter. Clear creation requests use the existing trusted reversible-action policy; first-use Calendar access suspends/resumes the original request through the existing native flow. No invitations, attendees, recurrence, edits or deletion are exposed. A 15-minute/64-entry in-memory ledger blocks retries of uncertain saves and reuses previously confirmed identifiers; it is not persistent cross-launch idempotency. No personal calendar was modified by automated tests.

A bounded native grammar handles “Schedule Review tomorrow at 5 PM for 30 minutes” without a model. Title case is retained. Missing AM/PM/duration, invalid values, past starts, compound clauses and nonexistent/repeated daylight-saving wall times fall back to reasoning/clarification rather than guessing. The tool accepts explicit timezone-bearing dates and durations of up to seven days. Native permission and capability copy now honestly describes event creation.

Added real local PDF/TXT/Markdown extraction, limited to 20 MB, 50 PDF pages and 16,000 characters. Runtime DocumentReadScope enforces actual current-request search evidence or a literal user path; provider-authored paths/results cannot authorize reads. Truncation, locked/invalid files, unsupported formats, absent text and scanned/no-OCR PDFs are explicit. Extracted content is untrusted data. History records the read summary, not the body. Selected reasoning receives content under its existing consent; Apple's adapter uses a marked 2,500-character excerpt.

Final offline suite: **216 discovered, 198 passed, 18 opt-in skipped, zero failures**. New checks cover native dates/title preservation/DST, invalid arguments before writes, canceled writes, verified receipts and no redundant approval, uncertain/successful duplicate retries, actual CoreGraphics-generated PDF extraction, empty PDF/no OCR, UTF-8 bounds, unsupported/oversized files, cancellation, trusted read scope, explicit-path summary routing and partial on-device prompt projection. Existing gate, voice, settings, Calendar agenda and provider checks still pass. **15 release-policy tests pass**.

Real on-device testing used synthetic requests/probe tools, not desktop side effects. Calendar generation selected the actual new tool and produced the exact explicit dates. An actual generated text file was read through the production tool/runtime and summarized by Apple intelligence, asserting its Friday deadline and 200-dollar budget. Full-registry checks exposed “summary ready” without facts and intermittent unnecessary questions about an already supplied path. Prompt/retry guidance was corrected, and strict explicit-path summary requests now route their first read deterministically before real model summarization. The full-registry test then passed. Named/ambiguous documents still require search/reasoning. This is local fixture-based end-to-end evidence, not acceptance of arbitrary personal documents or all model outputs.

Signed arm64 Debug application build and deep/strict signature verification passed. A separate **x86_64 application cross-build** also succeeded against the macOS 14 deployment floor. This establishes compilation/linking, not runtime acceptance on Intel or macOS 14. No Developer ID Application identity is installed in this keychain; official notarization/distribution and the two-version TCC test remain blocked on release credentials/artifacts. Existing development identity and OS grants were preserved.

After the final explicit-path routing fix, all **seven expanded live Apple-model checks passed together**, including Calendar generation, actual document reading/fact-based summary, conversation, recall, application intent and tool-result completion. Final native and Intel builds, strict native signature verification and the 198-test offline pass were repeated successfully. The suite uses no real Calendar writes or unrelated desktop actions.

Manual acceptance: request a clearly named test event with explicit duration, allow Calendar access yourself if needed and inspect title/start/end in Calendar. Repeat once and verify no duplicate during the protection window. Ask to summarize a chosen PDF and compare the actual facts; excerpt summaries must disclose the limit. Personal Calendar writes, fresh/revoked OS consent, physical voice-to-new-tool trials, minimum-OS/Intel runtime and accessibility acceptance remain required before release. Neither new tool is a claim that the entire future-integration roadmap is complete.

## Response latency · November 16, 2026

Recent real-app logs isolated the reported delay: recognition finalized in 68–214 ms, followed by approximately 5.4–9.5 seconds until the first Apple-model action. Those observations include different requests and are not a controlled benchmark. The earlier Bluetooth fix is present: input routing is verified and output-only configuration notifications no longer discard an unchanged running input. The user reports the actions now work.

This pass shortens planning text, removes unused reply generation before tool calls and avoids injecting every tool's argument schema into selection. Selection retains capability descriptions; argument generation still receives the selected tool's typed schema and runtime validation remains intact. A first experiment removing planning entirely failed the real action-selection test and was rejected; a concise planning field is retained. Native requests skip speculative-result waits. AVAudioEngine startup and analyzer preparation now overlap within the existing bounded/cancellable recording, rather than running sequentially.

Validation: 200 offline tests discovered, 184 passed, 16 opt-in skipped, zero failures. Five opt-in Apple model checks passed: real action generation, conversational response, opening-app intent after ended conversation, previous-conversation recall and tool-result completion without repetition. All tools in these live model checks are probes; no desktop settings, personal files or accounts were changed. Real Apple analyzer synthetic-input streaming also passed after the startup change: first provisional words before input end, then confirmed final text (1,452 ms analysis-start-to-first-partial and 34 ms input-end-to-final in this individual run). Signed Debug build passed.

Removing full argument schemas from selection reduced the five-model-test run from 34.0 to 24.9 seconds in consecutive runs of the revised planner. The small one-tool case varied from 1.7 to 2.3 seconds, so no universal speedup or instant-response claim is made. Warm caches, model variability and differing test requests matter. These durations exclude actual hardware speech and desktop actions. Cold-start and full voice-to-action performance still require repeated physical trials.

Voice's Advanced timing disclosure now includes `inputEndToFirstActionMs`, `inputEndToVerifiedCompletionMs` and `finalTranscriptToFirstActionMs`, which exclude the user's speaking time. Missing action/completion phases remain absent; successful prose alone never becomes verified task evidence. Native timing regression checks cover the new intervals. `on-device-timing` logs selection and argument durations without request/response text.

Apple's [guided generation guidance](https://developer.apple.com/documentation/foundationmodels/generating-swift-data-structures-with-guided-generation) explains the latency cost of generated properties and descriptions. Further prewarming/KV-cache work must preserve context correctness and be measured before adoption.

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

## Apple Notes integration — November 18, 2026

All 361 automated tests pass, with 24 optional/live tests skipped. Eleven AppleNotesTests cover controlled mutation/verification cases and real private-stdin AppleScript transport, timeout/cancellation and installed-dictionary compilation. These are not real Notes-account operations. Full macOS build and the native connection/capability UI mechanical scan pass.

The adapter remains Implemented pending owned real account creation/read/update and cleanup, just-in-time grant/revocation/resume, unsupported-note fixtures and spoken acceptance. Replacement removes rich formatting; shared/locked/attachment-bearing updates are refused. No private Notes database was accessed. See INTEGRATIONS.md and TOOLS.md for bounded search/read limits.

Actual org.sotto.mac no-prompt Automation preflight returned notRequested; no Notes launch/read/write was attempted. Evidence: [native permission report](acceptance/2026-11-18-apple-notes.json). This is permission observation only, not real-account verification.

## Read-only Apple Mail — November 18, 2026

All 372 automated tests pass, with 24 optional/live tests skipped; the native macOS application build succeeds. Eleven new AppleMailTests combine controlled account/reference/identity/partial-result cases with actual Foundation AppleScript date/UTF-8 helper execution and complete installed-dictionary compilation. These do not certify a live inbox. Private-origin tests cover same-Mail reads and refusal of unapproved cross-source/network calls. Date validation additionally rejects Foundation's normalization of impossible calendar dates and time-zone offsets.

The real org.sotto.mac no-prompt Automation preflight returned notRequested: [native permission evidence](acceptance/2026-11-18-apple-mail.json). No Mail launch, account/content read, consent prompt, sending or mailbox change was performed. mail.accounts/search/read remain Implemented pending an owned real-account fixture, permission grant/revocation/resume, moved/oversized messages and service-failure acceptance. Search is bounded to inbox sender/subject metadata; no globally latest/all-folder/body-search guarantee is made.
