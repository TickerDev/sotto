# Security and privacy

## Current enforcement

Trusted application code validates tool schemas, prepares native permission access, freezes review arguments, requests consequential-action approval, executes and checks results. The model cannot grant OS permissions or override the broker through arguments. Existing namespaced/compatibility IDs remain registered; no unrestricted shell or generated-script agent tool is exposed.

Tool loops, calls, file/content sizes, OCR work, indexing, timer storage and workflow steps are bounded. Timeouts and cancellation are cooperative; native actions already accepted may finish. Successful/uncertain side effects must not be blindly replayed. Workflow recovery journals durable dispatch/result evidence, and unknown outcomes require review/skipping rather than automatic retry.

Contacts writes require exact card/revision review and read-back. Local notes use versioned UUIDs and complete final-content review. Requested same-integration reads use account authorization without repeated confirmations. After private integration content, cross-source/network tools and writes require approval. Web, browser and document content has separate untrusted-content boundaries. Provider results, card names, filenames, note text and links are data, never authorization.

## Data and permissions

Use only current native OS authorization; never reset TCC, extract another app's tokens or change private account databases. Contacts, Calendar, Reminders, Apple Notes/Mail Automation and Accessibility setup is just-in-time and the suspended request resumes only after access is verified. Screen capture remains explicit and permission-scoped. OAuth account connectors are not shipped yet.

Reasoning/transcription destinations follow the existing processing choices. Keychain stores provider credentials separately. Activity history can contain titles/paths but not raw audio or complete document/note bodies. Local indexing, timer state, notes and workflow recovery have separate local files/retention; clearing history does not remove or undo them. FileVault is recommended for disk protection; application records are not a substitute for full-disk encryption.

Apple Notes uses fixed reviewed source with JSON over private stdin. The temporary descriptor is created exclusively with mode 0600 and unlinked before note content is written; user content never enters AppleScript source or command-line arguments. Notes-specific preflight must allow access before any native operation. Consequential changes freeze the actual destination or note ID/revision and final visible text. Edits refuse locked/shared/attachment-bearing notes, and replacement explicitly discloses rich-format loss. Native content is rechecked before mutation, then independently read back; cloud synchronization and cross-process atomicity are not guaranteed. Failed/uncertain writes must not be replayed blindly. No Notes private database is read.

Apple Mail offers read-only account/inbox discovery and selected text extraction, plus a separately reviewed unsent compose tool. Search results mint opaque in-memory references bound to actual account/native/RFC message IDs and displayed metadata. Reads cannot accept invented native IDs, cross accounts, reuse expired references or follow a message after its identity/mailbox changes. Result text remains untrusted, uses selected-provider consent and cannot authorize cross-source disclosure or writes. Account results project only declared fields, excluding passwords or unexpected adapter data. The reviewed helper receives private stdin and returns bounded JSON; no email content is placed in executable source or process arguments. Raw source, attachments, links and private account stores are not accessed. Native read-status changes are disclosed as partial outcomes.

Mail draft creation requires exact sender/account/recipient/subject/body review and revalidates the configured sender before dispatch. No send command is exposed. Durable hash-only reservations precede creation; uncertain/cancelled attempts cannot be automatically repeated across relaunch. Independent outgoing-message read-back checks exact fields and rejects extra CC/BCC or signatures. Receipts do not prove saved Drafts-folder persistence or delivery. A compose window may remain after cancellation or partial failure; no unapproved cleanup is performed.

## Validation boundary

Real Sotto-identity checks observed owned Calendar create/list/update, Reminders create/list/complete, timer Notification Center scheduling/presence/removal and native read-only inventory/context/system/audio reads. Owned fixture resources were removed. This does not certify every account or all permission transitions.

Screen Recording was unavailable and no screenshot was taken. The controlled external AX fixture could not become foreground; focus/management/selection remain unverified. Contacts permission is unavailable, so account writes remain implemented with controlled adapter tests rather than verified real saves. Personal browser tabs, playback, arbitrary shortcuts and actual output changes were not exercised.

## Pending systems

Mail sending/other mailbox state changes, messaging, provider OAuth, general UI action policy, browser forms, external packages, SDK/MCP runtimes and marketplace installation are not exposed yet. Their design must enforce the same boundaries, with durable send-attempt evidence, reviewed recipients/body, verified destinations, no secret typing into unverified targets, publisher/grant verification and explicit code-launch consent.

Process isolation alone is not sandboxing. A future integration that executes code with ordinary user privileges cannot truthfully be described as confined by Sotto's model-facing tool policy. Resolve the OS sandbox/trusted-code boundary before shipping package execution.

## Reporting

Report security issues privately through a maintainer-approved channel when one is published. No dedicated security inbox or vulnerability-disclosure service is configured in this checkout; do not post credentials, private messages or personal account data into public issues.
