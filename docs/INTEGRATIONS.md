# Integrations

## Current delivery

Sotto is an open-source macOS 14+ Swift 6 application. It does not require a proprietary Sotto account. This record distinguishes functioning code from the remaining expansion; documentation of a design does not make an adapter available.

| Integration | Status | Actual scope |
|---|---|---|
| Contacts | Implemented; controlled write tests/native card snapshot exercised | Native search/get/create/update, just-in-time OS permission, exact revisions and field review. Actual account save acceptance pending because Contacts permission is absent here. |
| Sotto Notes | Verified with isolated real local files | Local list/search/read/create/update, source labeling, reviewed append/replace, exact revision checks. Separate from Apple Notes. |
| Apple Notes | Implemented; real account operations unverified | Five appleNotes.* tools, native per-app Automation connection, reviewed changes and independent visible-text read-back. Fixed script compiles against installed public dictionary; private transport/timeout/cancellation execute for real. |
| Apple Mail | Planned | Installed Mail.sdef inspected. Accounts, inbox discovery and message operations require a supported Apple Events adapter, scoped references and reviewed/durable sending. No mail tools are registered yet. |
| Gmail / Microsoft Outlook | Planned | Official OAuth/API adapters; no copied browser/account credentials or embedded shared secret. Maintainer application registrations and account verification are not configured. |
| Apple Messages / Slack / Discord | Planned | Application/bot APIs and explicit access only; no history scraping, self-bots or extracted user tokens. No messaging tools are registered. |
| General computer use | Planned | Structured AX references, policies and verification still needed beyond the existing window/browser adapters. No arbitrary keyboard tool is exposed. |
| SDK / MCP / marketplace | Planned | No dynamic package loading, executable-server launch or package installation is available yet. See INTEGRATION-SDK.md. |

## Contacts

The native Contacts sheet uses the existing suspended-request continuation: ask for access only when needed, verify the resulting OS status, resume the same request, and cancel/expire safely. Setup does not preemptively ask for Contacts. Search/get are read-only; create/update require review of the specific target and final supported fields.

Search scans at most 5000 accessible cards/three seconds and returns up to 20 ranked matches. Names, organizations, job titles, email addresses and phone fragments can match. Multiple matches explicitly require disambiguation; an ID or identity is never invented. Oversized cards are skipped/refused rather than silently truncating fields before an update. Supported writes cover given/family name, organization, up to ten emails and ten phone numbers. Other fields remain untouched.

Updates freeze an actual ID and revision derived from current supported values, then reread it before saving. Read-back compares actual values. A save with uncertain/incorrect read-back is not reported as verified success. Exact existing cards can be reused for duplicate creation; uncertain creations are not automatically repeated in the running process. This is not durable cross-session transaction recovery for Contacts.

Returned names/addresses are private and untrusted. Reads use existing selected-provider processing consent. Repeated requested reads within the same integration do not ask redundant confirmations; crossing to another source or network tool after private integration content requires approval. Writes always require approval. User-approved contact aliases remain planned; existing remembered aliases still cover files, folders, apps and workflows only.

## Sotto Notes

These notes live at ~/Library/Application Support/Sotto/Notes/notes.json. The store is local, bounded to 500 notes/10 MB and 16000 characters per note body. It validates and preserves corrupt data, uses owner-only protected atomic writes with read-back, returns actual UUID/revisions, and never modifies Apple Notes data. Search returns references rather than full bodies. A repeated exact create reuses the actual note; stale updates cannot overwrite newer edits.

Append requests are expanded to their final complete content before review and execution. The approval explicitly says Sotto Notes. An explicit Apple Notes request must not be silently redirected here. Bodies/titles are untrusted; histories store operation summaries, not note bodies. Deleting activity history does not remove these separately stored notes.

## Apple Notes

The separate appleNotes.list/search/read/create/update tools use the installed Notes public scripting dictionary and per-target macOS Automation. The native connection sheet preserves the pending request, checks access before continuing, and cancels/expires safely. When access must be changed in System Settings, Sotto waits for the grant rather than requiring the original command again. No private database or account tokens are accessed.

Title search inspects at most 200 notes and returns at most 20; it does not promise most-recent ordering or full-library/content coverage. Reads refuse locked notes and cap HTML/plaintext at 24 KB each. Creation resolves the real default or specified folder before review. Input is limited to 12000 UTF-8 bytes; encoded HTML remains bounded to 24 KB. Text is HTML-escaped by trusted code. No note content is inserted into executable source, process arguments or the environment; private input uses an owner-only descriptor unlinked before content is written.

Updates retain the existing title and bind the actual ID plus a revision of native HTML/title/state. Append shows all final visible text and retains existing markup where supported; replace explicitly warns that rich formatting will be removed. Shared, locked and attachment-bearing notes are not rewritten. Native content is checked again immediately before writing. This optimistic check is not an atomic transaction with other Notes clients. Independent read-back checks the real ID/title and normalized visible text, not visual layout or iCloud synchronization. Mismatch/read-back failure yields partial completion; uncertain attempts must not be automatically repeated. Creation attempts are guarded in process, not durably across relaunch.

Automated checks use controlled note adapters, an actual osascript private-input/timeout/cancellation path, and compilation against the installed Notes dictionary. They do not prove real Notes account behavior. Apple Notes remains Implemented pending an owned-account fixture, permission grant/revocation/resume, locked/shared/attachment fixtures and spoken acceptance. Manual user testing remains paused; no additional manual-test prompts are required to continue development.

## Email and communication adapter contract — not implemented yet

Adapters must return actual provider account/message/thread/draft IDs and bounded normalized text. Account selection, sender, reply targets and original messages must survive the draft-to-send flow without model-generated substitutions. Mail sending must freeze recipients, subject and full body for review; a durable send-attempt record must precede dispatch. Queued/uncertain results cannot be retried blindly or presented as delivered.

Apple Mail's public dictionary has accounts, local message IDs, RFC message IDs, mailbox membership, recipient addresses, read status, outgoing drafts and send commands. It has no universal archive command or canonical exposed thread object. Archive must therefore resolve a real authorized mailbox, and any subject-based related-message search must disclose that it is not authoritative provider threading. A successful send command alone is not delivery evidence.

Gmail and Outlook need official public-client authorization with PKCE/state, narrowly scoped consent, secure token storage, refresh/revocation, verified account binding and a suspended request resumed only after verification. Normal users must not be asked to understand client IDs or scopes; maintainer OAuth registrations belong to distribution configuration. Gmail's desktop and Microsoft redirect requirements must be implemented separately rather than assuming one callback scheme works everywhere.

References: [Google desktop OAuth](https://developers.google.com/identity/protocols/oauth2/native-app), [Microsoft authorization code/PKCE](https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-auth-code-flow).

## Remaining major expansion

Mail and messaging tools, structured UI actions, browser navigation/forms, file/text/network/notification utilities, dynamic integration SDK, HelloSotto package, MCP transports, curated registry/install/update/revoke UI and general task recovery remain unfinished. Existing workflow recovery is implemented; it does not make all new operations resumable.
