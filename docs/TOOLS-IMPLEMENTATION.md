# Native tools expansion — engineering record

## Audit and implementation plan

Inspected on November 17, 2026, before adding capabilities. This checkout already contained extensive uncommitted voice, document, settings and calendar work. Those edits were retained.

- Swift Package modules separate Tools, Security, Providers, Agent, Integrations, Persistence, Audio and UI. The Xcode application consumes these package libraries.
- Deployment target: macOS 14. Swift 6. Liquid Glass branches require a recent SDK and preserve material fallbacks on older systems.
- Registry: `NativeTools.registry`. Existing implementations include Spotlight name search with folder fallback, document extraction/PDF OCR, app launching, EventKit reads/creation, Spotify and settings.
- Agent: `AgentRuntime`, provider function calls, bounded rounds, contextual document-read scope, clarification and approval events. NativeCommandProvider handles an intentionally narrow offline grammar.
- Speech: Apple streaming/on-device speech and optional OpenAI realtime transcription, microphone selection, cancellation, startup deadlines and latency traces. These were preserved.
- Providers: Apple on-device reasoning, managed/local Ollama, OpenAI Responses. Credentials use Keychain. Namespaced identifiers are encoded for OpenAI's function-name restrictions.
- Authorization: existing consequential approval gate and separate Calendar/Reminders/Accessibility preparation. Document extraction is restricted to literal user paths or actual search results.
- Existing tests exercise speech, provider transport, permissions, file ranking, calendar parsing, OCR and UI state. Live tests are gated for hardware, credentials and permissions.

Plan followed: preserve existing adapters; extend contracts and execution policy; implement everyday/context tools; implement bounded public web retrieval and native results; add workflows, aliases and capability discovery; build and test; distinguish verified behavior from untested or unavailable features.

## Execution and privacy boundaries

Tool results have seven explicit states. Only success counts as a successful activity/result in AppModel. Native command chains and workflows stop on incomplete results. The runtime bounds rounds and total calls, records duration through OSLog, applies cooperative timeouts, remembers successful side effects within a request, and refuses automatic replay of an already attempted side effect.

Timeouts cannot undo a macOS API operation already accepted, and Swift task groups wait for non-cooperative native operations to finish. There is no hard process kill for application actions. Workflow runs now have durable local execution records and explicit continuation of pending steps; other agent requests remain bounded to their current execution. This is not a transaction or automatic rollback system.

Workflow steps are validated before the first action. Saved names expand to an immutable step sequence before approval. Only an allowlist of ordinary native actions is permitted; no arbitrary shell, nested workflows or sensitive reads. Shortcuts uses a fixed executable with validated argument arrays, bounded output and cancellation. A successful Shortcut process is reported as unverified application effects.

Selected text, clipboard reads, screenshots and OCR require explicit approval. OCR text is shared with the active reasoning provider only after that approval. Screenshots are saved locally, not uploaded. Document summarization preserves the existing scoped read policy. Retrieved web content cannot authorize local actions: subsequent non-web/private operations or side effects require approval, including across retained conversation context. This is defense in depth, not a claim that prompt injection is solved.

## Web service boundaries

General web search has a zero-configuration DuckDuckGo browser fallback. It opens a search and explicitly supplies **no retrieved evidence**. Structured encyclopedia results use the documented MediaWiki Search API. Image discovery uses Wikimedia Commons Imageinfo with real thumbnail/original/source URLs and available licensing. Scholarly discovery uses Crossref bibliographic metadata, with publication dates and publisher-supplied PDF links; access rights are not inferred.

Public API references:
- https://www.mediawiki.org/wiki/API:Search
- https://www.mediawiki.org/wiki/API:Imageinfo
- https://www.crossref.org/documentation/retrieve-metadata/rest-api/
- https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app

There is no paid general-search backend or search-engine scraping. An optional Brave Search adapter and native Web settings now support a user-supplied plan/key. The key has its own Keychain account; no service credential is bundled. No live Brave request is claimed without a supplied credential. There is still no operated zero-configuration general-search backend.

URLSession retrieval uses ephemeral sessions without credential/cookie storage, disables automatic redirects, validates every redirect destination, restricts hosts to listed public publishers, accepts only supported MIME types, and caps transfer time and decoded bytes. It does not fetch arbitrary hosts, private IP literals, custom ports, login pages or authenticated browser sessions. This host allowlist is deliberately narrower than arbitrary public-web support. PDFs served as octet-stream must still pass PDF signature and PDFKit checks.

HTML extraction is bounded and strips scripts/styles; it is not a full HTML readability engine, does not execute JavaScript, and can include navigation or miss malformed markup. Research accepts up to three explicit source URLs or discovers sources using a connected provider (Wikipedia fallback). It makes at most two searches and three page requests, returns at most 24000 excerpt characters, deduplicates URLs, prefers publisher diversity, labels snippets versus page reads, and records exact citation URLs/failures. Lexical relevance and source diversity are not fact verification; automatic independence/authority evaluation remains incomplete.

Downloads support selected publishers and PDF/PNG/JPEG/GIF/plain text formats, show actual received-byte progress, validate signatures where appropriate and save into a unique Downloads subdirectory. Publisher attachment responses are permitted only for explicit document retrieval. No downloaded content is executed. Crossref PDF links on unsupported hosts remain unavailable for in-app download; users can open the source in their browser.

## Phase status

1. Everyday Mac: adapters implemented; app launch, discovery and audio enumeration exercised. Calendar/reminder mutations, timer notifications and media control still need permission-dependent physical acceptance.
2. Local context: AX windows/selection, ScreenCaptureKit/OCR, clipboard and metadata implemented. Content discovery uses scoped local Spotlight, with exclusions. An opt-in local PDF/TXT/Markdown excerpt index and optional Apple NaturalLanguage English sentence embeddings are implemented. Selected folders, exclusions, stale-file checks, local owner-only storage and scope revocation are enforced.
3. Web foundations: implemented and real public API/page retrieval exercised. General search has an optional Brave connection and native settings; browser and Wikipedia paths remain available without it. Brave requires a user-supplied plan/key and remains unverified live.
4. Images/documents: implemented, with real image/publication API, PDF transfer and extraction tests. Native interfaces compile; physical keyboard/VoiceOver/light/dark verification remains outstanding.
5. Research: bounded evidence collection implemented; explicit three-publisher source reads are live-tested; dates/snippets and lexical relevance are labeled. Independent fact verification and general-publisher retrieval remain incomplete.
6. Productivity: safe moves/renames, fixed Shortcuts CLI, an ordered native editor for allowlisted workflow actions, voice workflow management, typed file/folder/app/workflow aliases and durable reviewed workflow recovery are implemented. See the continuation records below for validation; physical editor/recovery acceptance remains pending.
7. Advanced: selection-to-reasoning and capability browser implemented. Opt-in English semantic discovery is tested on a local fixture. Browser extension integration, authenticated browser tasks and broader computer use remain unavailable.

## Browser investigation

Opening HTTPS websites uses the default browser through NSWorkspace. Sotto does not inspect cookies, sessions, private tabs or authenticated pages. Future deeper integration should use an explicitly installed browser extension with per-site grants and a native messaging host. Accessibility is an optional user-authorized visible-UI mechanism, not a substitute for website access controls. No extension is installed by Sotto. The foreground Accessibility bridge described below now provides narrowly approved page reading; it does not provide browser-session automation.

## Remaining acceptance work

All 28 spoken end-to-end acceptance scenarios are **not** certified. In particular: live credential-backed internet search, independent fact verification, arbitrary publisher PDF download, broader semantic-search evaluation, full workflow editing, notification delivery across sleep/termination, screen/selection permissions, and assistive-technology interaction require further work or physical validation. No speech-to-usable-result benchmark is claimed by this expansion.

## Validation on this checkout

Initial expansion combined run on November 17, 2026:

```sh
SOTTO_LIVE_WEB=1 SOTTO_LIVE_NATIVE=1 swift test
Scripts/build.sh
```

263 tests, 19 skipped, zero failures. The remaining skips are permission/hardware/provider-dependent tests. The application build succeeded. The build emits an existing package build-system warning for the VoiceGlowKit bundle.

Real operations exercised: temporary-file metadata and move/collision safety; timer deadline-store restoration/removal in an isolated temporary file; installed/running application discovery; foreground app identity; Core Audio output enumeration; Safari launch; Wikipedia search; Commons Yosemite image search; Crossref phishing publication metadata; Swift documentation fetch; download of Mozilla PDF.js's public tracemonkey PDF to a unique Downloads directory; PDFKit extraction. The downloaded test directory was removed.

Controlled safety tests verify schema rejection, unsafe URL/destination rejection, relative-link extraction, blocked Shortcuts option injection, workflow preflight before any side effect, stopping on partial results, no automatic replay of successful or uncertain side effects, approval before a private read following web content, cooperative timeout cancellation and backward-compatible result decoding. These controlled tests are not represented as physical integration verification.

The SwiftUI mechanical design scan returned no findings. New result/editor/capability screens compile, but their physical visual, VoiceOver and keyboard acceptance remains outstanding. No screenshots, microphone tests, private-calendar edits, reminder edits, clipboard reads or screen capture were used as substitutes for those checks.

## Spoken acceptance matrix

“Implemented” below describes a code path, not certified spoken end-to-end acceptance.

| # | Request | Current coverage / limitation |
|---|---|---|
| 1 | Open Safari | Native offline parser and actual Safari adapter launch tested. |
| 2 | Find my résumé | Existing alias-aware filename ranking; explicit remembered paths available to reasoning. |
| 3 | Find my most recent PDF | Existing PDF date ranking; scoped search also supports date/extension. |
| 4 | Open Downloads | Existing native offline folder action. |
| 5 | Ten-minute timer | Offline parser and timer engine implemented; real alert delivery unverified. |
| 6 | Reminder tomorrow | Existing EventKit creation; permission/list dependent. |
| 7 | Calendar agenda | Existing native date parser and EventKit adapter; permission dependent. |
| 8 | Volume 30 percent | Existing offline settings parser and Core Audio adapter; device dependent. |
| 9 | Pause music | Offline routing to supported Spotify adapter; not universal media control. |
| 10 | Explain selection | Approved AX text read followed by active reasoning; physical AX acceptance pending. |
| 11 | Current application | Offline parser; actual foreground identity read tested. |
| 12 | Find/open research notes | Search result resource references plus existing open action; ambiguous matches require choice. |
| 13 | Study workflow | Saved setup builder and approved sequence; controlled execution-policy tests pass. |
| 14 | Bluetooth settings | Existing pane catalog and native parser; destination opens through System Settings. |
| 15 | Active timers | Offline parser; persistent deadlines returned, including recently elapsed entries. |
| 16 | Web Apple Intelligence | Zero-setup browser search; optional Brave connection provides native results (live credential acceptance pending). |
| 17 | Official Swift docs | Known URL fetch tested; connected search can discover sources when configured. |
| 18 | Yosemite images | Actual Commons API tested; native gallery/preview implemented. |
| 19 | Three phishing PDFs | Crossref metadata search tested; three accessible PDFs are not guaranteed. |
| 20 | Open first result | Exact ordinal follow-up routes actual current search-result URLs directly; browser-only results remain unreadable. |
| 21 | Download PDF | Actual supported-host download tested; arbitrary publishers rejected. |
| 22 | Summarize webpage | Supported-host extraction tested; synthesis uses active reasoning; JavaScript pages unsupported. |
| 23 | Official Swift GitHub repo | Supported URL can be opened/fetched; connected search can discover it when configured. |
| 24 | Compare three sources | Three explicitly selected public publishers live-tested, with native citations and page/snippet labels; independent fact verification incomplete. |
| 25 | Recipe books online | Browser search works; optional connected search returns structured results. |
| 26 | Recipe book on Mac | Scoped Spotlight and opt-in local excerpt/English semantic index; coverage and model availability disclosed. |
| 27 | Sources for answer | Actual source URLs are retained; no source is invented for browser-only searches. |
| 28 | Paper/download/open | Supported-host tools can chain with approval; arbitrary-publisher/general-search path incomplete. |

## Continuation — November 17, 2026

This continuation implements optional structured general-web search, broader cited research, online scanned-PDF reading, and opt-in local document discovery.

### Search connection

Web settings now supports an optional Brave Search connection using its documented fixed HTTPS endpoint and subscription header. Credentials use the separate `brave_search` Keychain account, through the existing off-main-thread credential transport. They never appear in tool arguments, URLs, results or logs. The connection test sends one public query only after the user clicks Connect and test; it then enables subsequent user-requested searches/research. No account was provisioned, no paid account was created, and no credential was supplied during development.

The adapter bounds response size/time, refuses redirects, preserves actual URLs and provider-reported page dates, supports pagination and day/week/month/year filtering, and reports authentication/rate-limit failures without inventing results. Provider page dates may indicate either publication or modification and are not presented as verified publication dates. This Mac's daily attempted-request limit defaults to 50 and can be set in Web settings; reservations occur before dispatch, include failures, and reset at midnight UTC. It does not govern other applications or replace the provider account's billing limits. Explicit browser mode remains available without a connection.

Official reference: https://api-dashboard.search.brave.com/api-reference/web/search/get . Provider prices/plans are linked from native settings instead of hardcoded.

### Evidence, citations and PDFs

Research accepts up to three explicit user-selected HTTPS URLs or discovers candidates through the connected provider, with Wikipedia as the structured fallback. It makes at most two searches and three page requests, deduplicates URLs/fragments and final redirects, prefers different publisher groups, and limits excerpts to 24000 characters. Returned evidence includes stable citation labels, exact URLs, page/snippet provenance, unknown versus reported date fields, per-source failures, lexical relevance scores and uncertainty. These scores are not fact verification and publisher diversity does not establish independence.

The floating interface now shows citations alongside the generated answer and offers source excerpts and native source links. Exact ordinal follow-ups such as “Open the first search result” route an actual current result URL through trusted native execution without a new reasoning call. Browser-only results remain unreadable.

HTML extraction prefers main/article content and retains page-declared publication/modification metadata and same-origin canonical links. Citations continue to identify the actual retrieved URL; a cross-origin canonical declaration is not accepted.

Online PDF reading reuses the existing bounded DocumentTextReader/Vision pipeline: at most 20 MB, 50 inspected pages, 16000 characters and five textless pages OCRed locally. Results disclose OCR, skipped/unreadable pages and truncation. Owner-only temporary directories are removed on completion/failure/cancellation. The real Vision path was exercised on a synthetic scanned-PDF fixture; the actual public PDF transfer/extraction tests also pass.

### Local documents

Documents settings lets the user select up to ten folders and explicitly build or clear an index. The new `files.index` tool requires approval and cannot add folders itself. Builds inspect at most 5000 filesystem entries, 200 documents, 2 MB per file, ten PDF pages per document and 8000 excerpt characters per file, with a 40-second between-document budget. PDF scans are skipped during indexing; explicit document reading retains its OCR path.

The owner-only local JSON index stores excerpts and optional Apple NaturalLanguage English sentence vectors. No excerpt/vector is returned through search results or sent to a network service. Semantic availability is checked at runtime; lexical phrase matching remains available when the local model is missing. Semantic ranking uses a representative leading excerpt and is a suggestion mechanism, not complete document understanding. Only a small English fixture has been semantically evaluated.

`files.search` mode semantic returns actual current file references from this index, with extension/date filters. It excludes unreadable, moved/changed and out-of-scope files; it respects excluded folders and rejects symlink traversal during builds. Removing a folder/exclusion prunes persisted excerpts, and scope revocation during an in-flight build invalidates that build. Search results still pass through the existing scoped document-reading policy before contents enter reasoning context. Files are never modified by indexing.

### Continuation validation

```sh
SOTTO_LIVE_WEB=1 swift test
Scripts/build.sh
```

**280 tests, 20 skipped, zero failures; application build succeeded.** Live web tests include the existing APIs and PDF transfer plus explicit three-publisher research against Swift.org, Apple and the Swift repository. Actual local file/index persistence, local English semantic ranking, stale-file filtering, exclusions, symlink rejection, scope removal/revocation and real Vision OCR passed. Controlled tests additionally cover Brave fixed-origin requests, credential placement, result parsing, unsafe URL rejection, pagination/date semantics, daily-cap persistence, unavailable credentials, research budgets/deduplication/cancellation, page-versus-snippet provenance and canonical-link restrictions. The 20 skips include Safari relaunch (not enabled in this run) and pre-existing hardware/permission/provider checks.

The mechanical SwiftUI design scan returned no findings. New native views compile; physical VoiceOver/keyboard/visual acceptance and live authenticated Brave verification remain unperformed. No benchmark or complete 28-scenario spoken acceptance certification is claimed.

Remaining work includes an operated zero-configuration structured-search service, arbitrary public-host retrieval with stronger network controls, source-independence/fact-verification evaluation, broader multilingual/large-library indexing, full workflow step editing, browser-extension integration and the outstanding physical acceptance checks.

## Product behavior correction — automatic discovery and pictures in the pill

This section supersedes the earlier manual folder-selection/build requirement and implicit browser-search fallback.

- Local document discovery is enabled by default and starts on a utility-priority background task after app startup. User-accessible home documents and available cloud-document locations are discovered without choosing folders or pressing Build. Spotlight searches accessible indexed local volumes immediately; semantic requests fall back to Spotlight content when the richer cache has no matches.
- Background work retains its enumeration cursor between bounded passes, skips unchanged documents, and processes subsequent batches automatically. There is no permanent first-200-document coverage ceiling. The local excerpt cache is capped at 2000 entries/64 MB and retained entries prefer recent modifications; this cache supplements macOS's index rather than replacing it. Hidden directories, application packages and application/dependency caches are not recursively ingested. Existing additional document locations remain compatible.
- Documents settings is now an automatic-discovery toggle, readable status and optional exclusions. No technical vector settings or mandatory index build actions appear. Disabling discovery/removing access/excluding paths prunes cached content; index updates and document reads still obey macOS access controls. Metadata discovery covers files Spotlight can index; content extraction remains format/access dependent. “Automatic” does not mean permission bypass or complete binary-format understanding.
- Default web searches stay headless. A configured general-web provider returns structured results; absent that connection, the fallback is explicitly encyclopedia-only Wikipedia. A browser search occurs only for explicit browser mode. Chrome is a browser, while DuckDuckGo was the previously hardcoded search engine; replacing one browser with another does not provide a search API.
- Common singular picture requests, including “red parrot picture” and “show me a picture of a red parrot,” now route directly to the public image API without a reasoning call. The generic web tool also redirects recognizable picture queries to the image tool, preventing the earlier browser handoff.
- Image results include an actual selected result. The pill features its thumbnail with source attribution, loading/failure states, licensing details, save action and alternatives. Plural requests can show the gallery. Selection uses actual returned search rank, not invented URLs or a claim of visual classification.
- Rich results no longer generate a duplicate generic completion notification. API search completion is distinguished from actual SwiftUI image-loading success; an image-load failure is displayed with a way to try another result.

Validation includes a real red-parrot API search, download and AppKit image decode; exact request-routing tests; rejection of local-photo/generation/compound-action misrouting; and incremental indexing of 205 isolated documents across multiple passes. The native build includes a debug-only live-image review route. A UI inspection attached to the already-running Settings window, so it did not certify the new response panel visually; the diagnostic review process was stopped without closing the user's existing Sotto process. The prior full physical accessibility/visual acceptance limitations remain.

Final correction checks: `SOTTO_LIVE_WEB=1 swift test` ran **287 tests, 20 skipped, zero failures**; `Scripts/build.sh` succeeded. Real image retrieval and decoding passed, and the mechanical native UI scan returned no findings. No complete physical pill/VoiceOver certification is claimed.

## Roadmap continuation — personal workflow management

The fixed study-template builder has been replaced by a native ordered-action editor. It can create or edit routines using the runner's registered folder, file open/reveal, installed application, volume, output-device, timer, foreground-context and System Settings actions. Users can add, remove and reorder up to ten actions without scripting or entering tool identifiers. The editor refuses unknown action fields instead of silently discarding them. Saving applies shared schema/range validation and does not execute the routine.

The agent now exposes workflows.list, workflows.save and workflows.remove. Creation/update requires approval of the exact proposed name and ordered sequence. Updates/removal use actual identifiers and revisions; duplicate names are rejected instead of silently overwriting a routine. Existing saved workflow records without revisions migrate to revision 1 while preserving their identity and steps. Bounded preference decoding refuses corrupt storage and preserves its bytes. Updates are serialized within the app process; optimistic revisions prevent a stale editor or voice request from replacing a newer record. This is not a claim of a cross-process database transaction.

“Run/start/begin [exact saved name]” can resolve in trusted application code before model selection, including a unique optional “my” variant. Ambiguous names remain unresolved for clarification. Native approvals now describe each action in plain language. Saved routines expand to an immutable inline sequence before approval, so later edits cannot change what will execute.

Workflow execution applies each step's cooperative timeout, stops on cancellation/incomplete results, preserves completed and failed step records with one execution identifier, step numbers and actual measured durations, and never automatically replays earlier actions. Saving/removing a routine does not execute or undo any action. There is still no durable cross-session execution journal or resume command.

Validation: SOTTO_LIVE_WEB=1 swift test ran **299 tests, 20 skipped, zero failures**; Scripts/build.sh succeeded. Actual isolated UserDefaults save/list/restore/update/remove and a saved workflow invoking the real native foreground-app adapter passed. Controlled tests cover stale revisions, duplicate names, legacy migration, corrupt-store preservation, invalid ranges, unknown/script/nested actions, exact/ambiguous command matching, editor action preservation, frozen approval snapshots, failure evidence, per-step timeouts and cancellation preventing the next action. No personal saved workflow was changed for these tests.

The native editor compiles. Physical editor/VoiceOver/keyboard acceptance remains outstanding; neither controlled adapters nor compilation is represented as certification. Application/workflow aliases, durable resume, browser interaction and the remaining account/device/release gates are still open on the updated roadmap.

## Roadmap continuation — remembered names and workflow recovery

Remembered associations now distinguish files, folders, installed applications and saved workflows. Legacy file associations retain their names/targets and migrate to revision 1. Application references resolve through NSWorkspace; workflow aliases retain the saved UUID across title changes. Exact native commands resolve these names without a model, and ambiguous matches request clarification. Voice save/change/forget requires approval, an existing canonical target and the actual current revision. Settings lists these names and allows forgetting them. Unsupported applications do not gain media-control interfaces from being remembered.

Alias persistence is bounded to 100 associations/512 KiB, serialized within the app process and verified by reading back stored bytes. Corrupt storage is preserved and refused. Explicitly named, approved file aliases can authorize document reading in the current request; merely listing other aliases does not grant access to their contents. File contents still follow the selected intelligence-processing preferences.

Every workflow run now creates an owner-only local JSON journal in Application Support/Sotto/WorkflowRecovery. Before each native dispatch, the engine atomically writes and synchronizes a running marker, synchronizes the parent directory and checks the saved bytes. It records successful outcomes and measured step durations after execution. A storage failure prevents further dispatch. A process interrupted between dispatch and result recording leaves an uncertain action rather than permission to retry it. This protects against ordinary interruption conservatively; it does not claim hardware power-loss durability or exactly-once external API transactions.

The new workflows.runs tool exposes actual saved execution identities and states. workflows.resume freezes the actual revision, remaining actions and uncertain-action list before central approval, then rechecks those values under an exclusive cross-process lease. Completed actions never run again. Uncertain/running actions cannot be retried: the user must inspect them and explicitly choose to skip them before continuing pending actions. Skipped actions remain unverified, including when skipping the final action leaves no work to dispatch. Terminal executions refuse replay. Recovery never starts automatically at launch. Timeouts remain cooperative and cannot retract an effect already accepted by macOS.

Workflows settings includes an interrupted-routine review, per-step states, explicit continuation/skip controls and removal of recovery evidence. Removing a record does not undo earlier actions. Completed records are pruned after seven days or for capacity when starting a new run; interrupted records remain until reviewed/forgotten. Storage is bounded to 50 records/1 MB each, and refuses new execution when retained records fill it. These records contain local arguments/results and are separate from activity-history retention; README documents the privacy boundary.

Validation: SOTTO_LIVE_WEB=1 swift test ran **310 tests, 20 skipped, zero failures**; Scripts/build.sh succeeded. Real operations used isolated UserDefaults and temporary recovery directories, actual installed Safari resolution, and a native foreground-context action continued through a freshly loaded journal. Controlled tests cover legacy migration, corrupt-store preservation, missing targets, ambiguous names, stale alias updates/removal, requested-file-only alias read scopes, completed-action non-replay, unknown-outcome skipping, final-step skipping without dispatch, stale recovery approval, concurrent execution refusal and refusing dispatch without writable recovery storage. Existing workflow timeout, cancellation and partial-result regressions pass. Personal saved workflows and remembered names were not changed.

The mechanical scan of changed workflow settings/recovery views returned no findings. The application compiles; physical termination/relaunch, editor/recovery controls, VoiceOver and keyboard acceptance remain pending. The next implementation priorities are a narrowly authorized browser bridge and the general-search service model. This continuation supersedes the earlier limitations about app/workflow aliases and absent durable recovery.

## Roadmap continuation — authorized foreground browser bridge

Four native tools are registered: browser.currentTab, browser.readPage, browser.find and browser.openLink. The adapter uses public AXUIElement APIs on macOS 14+, rather than private browser endpoints, generated scripts or a headless scraper. Safari, Chrome, Edge and Brave bundle identifiers are allowlisted; a browser must expose a single accessible HTTPS web area in its focused window. Unsupported browsers/pages fail explicitly. No extension installation or “Allow JavaScript from Apple Events” setting is required by this implementation.

Browser tools request Accessibility before resolving their approval snapshot; other tools retain their existing validation-before-permission behavior. The snapshot holds a random page reference and the actual browser/title/address. At most eight native references are cached, with two-minute validity and pruning on access. Before and after extraction, the adapter checks the original focused window, AX web-area identity and URL. A different foreground app, tab, window, address, unknown reference or expired reference refuses the request. Sotto's own approval surface can be foreground while the original browser page remains unchanged.

Approval describes source metadata and processing by the selected intelligence. Metadata is resolved locally for review; body text is not read before approval. Private/authenticated browsing mode cannot be reliably detected through this bridge: the approved current page must therefore be treated as potentially sensitive. It does not enumerate background tabs, obtain cookies/credentials, execute page JavaScript, submit forms or bypass site restrictions. Browser excerpts can enter the existing selected-provider conversation only after approval; they are not independently persisted by the bridge. Activity history retains the tool summary/title, not the excerpt body.

Extraction stays off the UI thread, bounds individual AX messaging, and limits page identification to 300 nodes/12 levels/three seconds. Text traversal is bounded to 1200 nodes/24 levels/five seconds, 16000 characters and 50 safe links. Editable/form-control subtrees and embedded web areas are excluded. Only static text and actual HTTPS links are returned. Coverage is always labeled as an accessible excerpt; exhausted limits are disclosed. Accessibility may omit offscreen, canvas, PDF or otherwise unexposed content. Literal text finding accepts 1–200 characters and returns at most ten context matches; no match does not establish absence from the full page.

Opening a page link accepts only an actual reference/link number previously returned by a read. Approval resolves its exact URL from native state, and execution rereads the source and verifies that URL remains exposed. The default browser receives the validated HTTPS destination via NSWorkspace. OS handoff acceptance is reported partially completed because page loading cannot be independently verified. Same-tab navigation, page clicking, downloads, form submission and authenticated multi-step browser workflows are outside this adapter's contract.

The pill now has a native source link, excerpt disclosure and reviewed page-link actions. Narrow “What tab am I on?” and “Read this webpage” requests route without a model; summarization remains reasoning over the approved excerpt with the actual URL. Capabilities and Accessibility permission copy describe the implemented scope. Browser titles, URLs, excerpts and links are untrusted data. After browser results enter the conversation, any subsequent tool call requires approval—including public web searches—to prevent untrusted page instructions from disclosing local/page information. The same protection applies when the browser result comes from the preceding turn.

Validation: SOTTO_LIVE_WEB=1 swift test ran **322 tests, 20 skipped, zero failures**; Scripts/build.sh succeeded. BrowserToolTests uses explicitly controlled adapters to test real runtime approval/denial and result propagation, frozen references, changed tabs, forged links, partial handoff reporting, missing text, field filtering, extraction bounds, Unicode/literal matching, cancellation and narrow routing. ToolRuntimeSafetyTests covers page-driven private reads/search disclosure, follow-up context and preserving ordinary preflight before permission prompts. Native unknown-reference/permission refusal was exercised without reading any personal browser page. These checks do not mark browser reading/navigation as verified.

One earlier broad live run timed out at Wikipedia and encountered protected-file EPERM failures in index/workflow tests. The focused storage retry passed without weakening file protection, and the final full live run passed. Both changed SwiftUI mechanical scans returned no findings. Physical Safari/Chrome/Edge/Brave page reading, actual link handoff, first/revoked Accessibility access, VoiceOver/keyboard controls and private-mode behavior remain acceptance work; no personal tabs were inspected and no manual testing prompt was issued.

Public API references: [AX attribute reading](https://developer.apple.com/documentation/applicationservices/1462085-axuielementcopyattributevalue), [bounded AX array reading](https://developer.apple.com/documentation/applicationservices/1462060-axuielementcopyattributevalues), [AX page URL](https://developer.apple.com/documentation/applicationservices/kaxurlattribute). These document the native interfaces, not a guarantee that every browser/page exposes usable content.

## Roadmap continuation — local rich-document coverage

General web-search expansion remains deferred. Local document reading and automatic indexing now share support for PDF, TXT/Markdown, RTF and DOCX. The shared format capability also enables existing file-result Summarize actions and explicit-path summary routing for the new formats, while the runtime still requires actual search evidence, a requested approved alias or a literal user path. No guessed path is authorized by a file extension.

RTF uses AppKit's in-memory attributed-string importer, capped at 2 MB. Fields (including field hyperlinks), pictures, file tables, binary data and embedded objects are refused before import. TXT/Markdown support UTF-8 and BOM-marked UTF-16 LE/BE, with strict byte round trips, complete code units and binary/NUL rejection. A regression fixture exposed Foundation accepting an incomplete UTF-16 code unit; explicit length/round-trip validation now refuses it.

DOCX uses selected in-memory ZIP entries, system zlib and Foundation XMLParser. No shell, archive extraction to disk, relationship loading or third-party document service is used. The reader validates central/local headers, exact entry names, sizes, flags, duplicate selected entries and CRCs, and requires standard non-macro main-document content types. It caps archives at 20 MB/512 entries, selected XML at 8 MB/200:1 expansion and type metadata at 512 KB. Only stored/raw-deflate data is supported; split/encrypted/ZIP64 and malformed inputs are refused. XML DTD/entities are rejected before parsing, external resolution is disabled, nesting is bounded, and output remains capped at 16000 characters.

Word main-body paragraph/table text is returned with explicit text-only coverage. Headers, footers, comments, images, objects, deleted/explicitly hidden runs and linked resources are omitted; styles, pagination and layout are not resolved. RTF formatting is not preserved. Local indexing reuses these readers with its existing 2 MB input/8000-character excerpt bounds, exclusions, stale-file checks and local-only persistence. It does not run OCR.

Document content now receives the same follow-on tool approval boundary as sensitive browser content, including subsequent-turn context. A real fixture read through the runtime followed by an attempted search was denied at the central gate, with no disclosure sink execution. Initial requested document reading continues to use existing file scope and selected-provider consent; it does not acquire permanent access to other files.

Validation: swift test ran **330 tests, 24 skipped, zero failures**; Scripts/build.sh succeeded. Live web checks were not enabled while search expansion is on hold. New reproducible synthetic fixtures exercise stored/deflated DOCX, Unicode, paragraph/table text, omitted parts, macro/encryption flags, CRC/header corruption, duplicate entries, compression amplification, malformed/entity XML, empty documents, native RTF import/refusal, encoding errors, cancellation and partial output. Actual rich-document index build/search/restoration passed without returning cached bodies in search results. The fixture generator uses Python's standard zipfile library solely for tests; application execution uses native code. No personal file, folder association or account was changed.

One existing feedback test treated DOCX as unsupported; it now uses Pages to retain the unsupported-format guard. PDF/OCR, browser, workflow, speech and other offline regressions pass. No UI layout was changed; the existing file-result action follows the shared supported-format list. Personal-document summaries over speech, broad Word/RTF corpus compatibility and full-document chunking remain acceptance/future work. See DOCUMENTS.md for limits.

API references: [native RTF import](https://developer.apple.com/documentation/foundation/nsattributedstring/init%28rtf%3Adocumentattributes%3A%29), [XML external entity policy](https://developer.apple.com/documentation/foundation/xmlparser/shouldresolveexternalentities), [system zlib raw-deflate semantics](https://zlib.net/manual.html).

## Roadmap continuation — timer reliability

Native timers now retain notification state alongside the original absolute deadline. Legacy three-field records migrate to needs-scheduling without changing identity or deadlines. Loading is bounded to 200 records/1 MB with identity/name validation; corrupt, oversized, duplicate or linked storage is refused and preserved. Atomic protected writes, owner-only files, synchronization and read-back precede native scheduling/removal. This is ordinary interruption recovery, not a hardware power-loss or exactly-once external transaction guarantee.

Start reserves and persists the timer before requesting notification access. A permission dialog does not reset or extend the deadline. Only an undetermined status can request consent; maintenance never prompts. Authorized alerts, quiet/restricted notifications, denied access, failed scheduling and elapsed/unverified delivery have separate result states. Scheduling failures retain the actual timer and return partial evidence; cancellation during setup requests cleanup rather than returning content as a completed timer.

Scheduling now uses a non-repeating Gregorian UTC calendar trigger at the original deadline (rounded upward to the next whole second). Verification checks the actual pending request identifier and next trigger date within two seconds. Legacy interval triggers can be replaced once at the saved deadline; existing matching absolute requests are not dispatched again. Scheduled is never treated as delivered. Elapsed deadlines are not replayed, including after sleep or relaunch. macOS remains responsible for delivery while the app is terminated, and restrictions/sleep/Focus can delay or prevent alerts.

Cancellation is persisted as cancellation-pending before native removal. If scheduling is in flight, the marker prevents relaunch restoration and the scheduling completion removes the late request. Removal is verified against both pending and delivered notifications. Unverified cleanup retains the marker and reports partial completion; later maintenance can complete it. An alert already presented cannot be undone. Per-timer operation ownership and persistence before async waits prevent concurrent starts exceeding 50 active slots or cancellation resurrecting a timer.

Maintenance runs at app launch, wake, activation and timer listing. Old elapsed records are pruned after 24 hours; unresolved cancellations are retained, with a 200-record total cap. Active, elapsed and cancellation-pending records are returned separately. Lists now return an object rather than a bare array, fixing the native response formatter interpreting timer results as file paths/PDF search results. Names are optional and bounded; labels with control characters are refused.

The app notification delegate now requests foreground banner/list/sound presentation only for an actual retained, non-cancelled timer identity. Ordinary optional task-completion notifications keep their existing behavior. System permission and presentation policy still applies; this wiring is not evidence of real banner/sound delivery.

Validation: swift test ran **340 tests, 24 skipped, zero failures**; Scripts/build.sh succeeded. No live search/provider requests were enabled. TimerReliabilityTests uses real isolated protected JSON files and actual UserNotifications calendar-trigger construction. Controlled adapters verify deadline preservation, idempotent matching requests, repair after missing requests, expiry without replay, quiet/denied access, scheduling/date-readback failures, cancellation during in-flight add, persistent unverified removals, permission-delay expiry/cancellation, reserved active limits, legacy migration, storage corruption/oversize/duplicates/unwritable paths and native listing output. Existing document, browser, workflow, speech and other offline checks pass. No personal timer, OS permission or notification was changed by these tests.

Foreground banners/sound, actual pending/delivered removal, termination/relaunch delivery and physical sleep/Focus behavior remain acceptance checks. The timer UI provides status on request; there is no continuously ticking panel or automatic undo. General web-search expansion remains deferred.

API references: [notification settings](https://developer.apple.com/documentation/usernotifications/unnotificationsettings), [foreground presentation delegate](https://developer.apple.com/documentation/usernotifications/unusernotificationcenterdelegate), [presentation options](https://developer.apple.com/documentation/usernotifications/unnotificationpresentationoptions).

## New major expansion — audit and first functioning delivery

Audit covered the module inventory, current tool/evidence records, typed registry and compatibility adapters, central gate, provider/voice boundaries, per-step workflow journal/recovery, settings/connection flows and test corpus. macOS 14/Swift 6 remain the deployment floor/language mode. Existing native/web/provider/workflow code was reused rather than replaced.

Phase 1 added an explicit Debug-only native acceptance report using Sotto's actual application identity. Background voice/index/history services are disabled for the diagnostic process. Reports contain statuses rather than personal application data. Real owned Calendar creation/listing/duplicate reuse/update/read-back/cleanup and Reminders creation/title-filtered listing/completion/read-back/cleanup passed. Actual timer pending scheduling, finished Notification Center presence and pending/delivered removal passed for an owned short timer. App inventory, foreground context, system information and audio enumeration also executed natively.

The first owned AX enumeration passed, but same-process action/selection checks did not. A separate controlled helper was then introduced; it could not become foreground in this environment. Native computer-use inspection bound an older running Sotto Settings window rather than the owned helper, so it was not manipulated or counted as a pass. Only the explicitly created helper was stopped. Window focus code now checks both foreground PID and the exact focused AX window after raising, returning partial if not observed. Focus/management/selection remain Implemented with pending real acceptance. Screen Recording was unavailable, so no screenshot/OCR or permission prompt was attempted. Browser/private tabs, personal playback, other audio routes and arbitrary shortcuts were untouched.

Phase 2 begins with four actual Contacts tools. Apple's framework provides bounded name/organization/job/email/phone search, real IDs and value revisions, exact duplicate reuse, before-save stale checks and result comparison. The existing native permission continuation now includes Contacts, resumes the original request after verified OS access and requires no extra account setup. Create/update approvals display the final person/fields without raw revisions. Controlled writes and a real CNMutableContact snapshot pass; account reading/saving is not Verified because native permission is unavailable.

Five Sotto Notes tools provide actual protected local list/search/read/create/update. They never claim Apple Notes access. Append expands to the full reviewed content; revisions prevent stale overwrite; duplicates reuse actual records; corrupt storage is preserved. The shared schema validator permits an explicitly declared bounded 16000-character note body while retaining ordinary input limits. Real local-file save/reload/search/update and privacy-preserving reference results pass.

Private integration content is treated as untrusted. Same-integration read-only lookup chains remain authorized without redundant prompts. Crossing to another source/network or a write requires approval; follow-up context retains this boundary. Tests verify Contacts-to-search disclosure refusal, Notes-to-Contacts refusal and same-source read continuity.

Validation: swift test ran **350 tests, 24 skipped, zero failures**; Scripts/build.sh succeeded. No live search or AI-provider requests were enabled. The mechanical scan of changed permission/connection/capability UI returned no findings. Machine-independent native evidence is checked in under docs/acceptance; temporary fixture resources were removed. Existing user settings, notes, contacts, email/messages and live application content were not edited by the new integration tests.

This is an initial functioning delivery, not completion of the eight-phase expansion. Apple Mail/Gmail/Outlook, Apple Notes automation, messaging, contact aliases, general UI/browser actions, new utilities, dynamic SDK/runtime/HelloSotto, MCP, marketplace and general task-level recovery remain planned. The requested documentation files now explicitly distinguish those designs from executable features. The new request reopens web improvements in its later internet phase; no proprietary account or hosted service has been introduced.

## Roadmap continuation — Apple Notes through public Automation (November 18)

Five separate appleNotes.list/search/read/create/update tools are registered alongside the unchanged notes.* Sotto-managed store. The native Notes dictionary supplies actual note/folder identifiers, title, HTML/plaintext and locked/shared/attachment state. Title search inspects at most 200 notes/20 results; it is not full-content, complete-library or newest-first discovery. Reads refuse locked/oversized notes and return bounded plaintext without internal HTML.

The existing suspended-request connection flow now handles per-target Notes Automation. Observation uses a no-prompt native permission preflight; an explicit connection action can launch Notes without activating it and request macOS consent. Access is checked before resuming the original request. A Settings-required connection waits for a verified grant; cancellation, expiry and superseded requests cannot resume. Read-only lookup chains do not require repeated approvals; Apple Notes content is its own private/untrusted origin, distinct from Sotto Notes and public search.

Creation freezes the actual default/requested folder and title/body. Update freezes the actual native note ID, HTML/title/state revision and complete final visible text. Native HTML is checked again immediately before mutation; this is an optimistic check rather than atomic cross-application compare-and-swap. Append retains existing markup and inserts escaped text; replace warns about rich-format loss. Locked, shared and attachment-bearing notes are not edited. Input is capped at 12000 UTF-8 bytes, HTML/plaintext snapshots at 24 KB each, with final approval text additionally capped at 16000 characters. No externally supplied HTML is loaded or executed.

The reviewed script is constant. JSON data travels over stdin using an exclusively created owner-only descriptor unlinked before writing any content, avoiding user text in source, process arguments, environment or a named persistent file. Existing bounded output, timeout and process cancellation transport is reused. Creation attempts are remembered in process, not durably across restart. An uncertain operation must not be replayed automatically.

After mutation, a separate native read checks actual ID/title and normalized visible plaintext. Mismatch or read-back failure returns partial completion and preserves the resource reference. This does not verify rendered layout, attachments or iCloud synchronization. Native helper errors can leave uncertain side effects; the runtime's attempted-action protection remains active.

Validation: swift test ran **361 tests, 24 skipped, zero failures**. The 11 new tests include controlled adapters for frozen destinations/final content, append markup, stale/unreviewed writes, unsafe notes, read-back mismatch/failure, escaping/size limits and separate registration. Actual osascript execution passed Unicode/literal data over private stdin and enforced timeout/cancellation. The complete reviewed Notes script compiled with osacompile against this Mac's installed public dictionary without executing it. The changed native UI mechanical scan returned no findings. The macOS application build passed. No live search or model requests were enabled.

Apple Notes remains **Implemented**, not Verified: real account reads/creates/updates, fresh/revoked Automation and permission-sheet resume, locked/shared/attachment fixtures and spoken acceptance remain pending. No personal Notes content was inspected or changed by automated tests. Native Sotto-identity preflight returned notRequested without launching Notes or showing consent; evidence is docs/acceptance/2026-11-18-apple-notes.json. A preflight is not account-operation verification. Existing manual user testing remains paused.

API references: [application-address descriptor](https://developer.apple.com/documentation/foundation/nsappleeventdescriptor/init%28bundleidentifier%3A%29). The installed Notes.sdef and the macOS SDK Apple Events headers define the actual public scripting/authorization surfaces exercised here.

## Roadmap continuation — read-only Apple Mail (November 18)

Pushed the accumulated native-tool, document, voice, workflow and integration work to the existing GitHub main branch before starting this increment. The first Mail delivery adds only mail.accounts/search/read; existing tool IDs and native behavior remain intact. Mail writes and the integration ecosystem are not advertised as available.

The adapter uses Mail's installed public scripting dictionary, reviewed constant AppleScript and private stdin transport. The shared per-target Automation authorizer now handles Notes and Mail without arbitrary application destinations. The existing native connection continuation preserves the original request, verifies permission, waits for Settings grants when appropriate, and expires/cancels without resuming a replaced request. Notes keeps its original compatibility facade. No OAuth service, proprietary account, hosted endpoint or search billing was introduced.

Account discovery projects only actual IDs/names/enabled state/addresses, capped at ten accounts and ten addresses each. Empty/disabled accounts are not treated as a connected inbox. Search matches sender/subject plus optional actual account, unread and explicit date bounds. It examines at most the first 200 accessible inbox messages and returns at most 20, with metadata only. Results are sorted within that returned set; no globally latest, full-body or all-folder search is claimed. Skipped records and truncation are disclosed.

Each result mints a session-local opaque message reference, expiring after ten minutes with a 200-reference cap. A read cannot supply an invented native message ID. Actual account/native/RFC IDs and subject/sender/date/mailbox are checked before and after reading; changed or moved messages require rediscovery. Multiple matches require disambiguation. Accounts and message fields are private, untrusted data; same-source lookup chains retain account authorization while cross-source/network disclosure still requires approval.

Mail's message size and full returned text are guarded at 2 MB, with a maximum 16000-byte valid UTF-8 excerpt. Sotto does not render HTML or follow links/attachments. The script issues no explicit read-status or other mailbox mutation; an observed read-status change during extraction yields partial completion. Mail may obtain body data through its configured service. No account password, private database, raw MIME source or extracted credential is accessed.

A validation check exposed Foundation normalizing impossible dates and offsets. Mail timestamp validation now requires an exact round trip in the stated offset, refusing February 30 and +99:00 before account access. Actual AppleScript Foundation helper execution passed timezone conversion and Unicode clipping at a multibyte boundary. The entire Mail script compiles against the installed public dictionary without running account operations.

Validation: swift test ran **372 tests, 24 skipped, zero failures**; Scripts/build.sh succeeded. Eleven new tests cover actual helper execution/compiler behavior and controlled account projection, absent accounts, expired/fabricated/cross-session references, eviction, incorrect native/account/RFC identity, partial text/read-status changes, ambiguous/skipped/duplicate results, invalid dates/inputs and registration of read-only tools only. Existing private-origin tests now cover Mail-to-network/cross-source refusal and same-source reads. The changed native UI mechanical scan and whitespace checks passed.

Real org.sotto.mac no-prompt Automation preflight returned notRequested, with no Mail launch, account/content read, permission prompt or mutation. Evidence is docs/acceptance/2026-11-18-apple-mail.json. Therefore all three Mail tools remain **Implemented**, not Verified. Real owned-inbox discovery/read, service failures, fresh/revoked permission and connection-resume acceptance remain pending. Existing manual user testing remains paused; no personal email was inspected or changed.

Next: reviewable drafts and deliberate threading scope. Sending remains unavailable until exact recipient/body authorization, durable dispatch evidence and uncertain-send recovery are implemented. Remaining mail.thread/summarize/draft/send/reply/archive/markRead and direct provider APIs are planned rather than fake adapters.

## Roadmap continuation — reviewable new-message compose (November 18)

mail.draft now prepares a new unsent compose window using Mail's public outgoing-message interface. It uses the existing Automation connection continuation and consequential-action gate. Approval resolves and displays the actual account, configured sender address, complete To recipients, subject and full body. Execution revalidates the sender account before dispatch. Input rejects header controls, display-name address forms, duplicate/more than ten recipients and text beyond 12000 UTF-8 bytes. CC/BCC, attachments, threaded reply and sending remain unavailable.

A separate reviewed fixed script receives private JSON through stdin, creates the unsent outgoing message, clears its signature, populates recipients and exposes the compose window. It contains no send command or evaluated user source. Independent lookup by the actual outgoing ID compares sender, all recipients, subject, exact body, zero CC/BCC and visibility. Signature/body differences, missing IDs and native failures yield partial completion; an actual ID is preserved when available. Cancellation may leave an incomplete compose object. No automatic deletion/recreation is attempted. Saved Drafts-folder/cloud persistence is not verified or promised.

A protected hash-only journal at Application Support/Sotto/Mail/draft-attempts.json reserves the full operation before native dispatch. Nonblocking file locking, bounded/validated records, atomic protected writes, synchronization and byte read-back prevent concurrent reservation or silent reset after corruption. Bodies/addresses are not stored there. The 1000-entry journal blocks identical attempted operations across relaunch, including deliberate identical repeats and successful attempts. This conservative limitation is documented; no automatic pruning or retry override is exposed.

Validation: swift test ran **380 tests, 24 skipped, zero failures**; Scripts/build.sh succeeded. Eight new MailDraftTests cover exact human review/read-back, sender/unreviewed refusal, header/address/body bounds, corrupt receipt preservation, cancellation, real temporary receipt permissions, concurrent reservations, relaunch suppression after uncertain dispatch, partial mismatches and actual public-dictionary script compilation. The changed approval presentation's mechanical scan and whitespace checks passed. Existing read-only tools and their identifiers remain registered.

Real org.sotto.mac no-prompt preflight again returned notRequested; evidence is docs/acceptance/2026-11-18-mail-draft.json. No Mail launch, account/content read, compose creation, permission prompt or sending was performed. Therefore mail.draft remains Implemented pending an owned native compose fixture and grant/revocation/resume acceptance. Existing manual user testing remains paused.

The next Mail work is deliberate conversation/thread scope and a send path with separate exact authorization and durable uncertain-send recovery. Draft preparation does not authorize sending, and user-visible compose fields cannot be silently treated as a sent message.
