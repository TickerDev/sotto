# Settings window audit

November 15, 2026 · v0.2.2 (4) · macOS 27 · development-signed app.

The user clarified that the reported Verify “crash” was the window disappearing/minimizing. The old window styling enabled dragging from the entire background and used interactive AppKit decorative views. v0.2.2 disables background dragging, makes decorative views ignore hit testing, applies chrome once per attached window, and explicitly restores a minimized Settings window when opened again. These correct window-wide interaction hazards; the exact original gesture was not independently isolated.

## Live coverage

All nine sections were opened in the actual app. “Checked” below describes the completed interaction, not every possible side effect in that section.

| Section | Completed live checks | Result / exclusions |
| --- | --- | --- |
| Setup | Open section; Verify connection, including double-click | Connected for the selected model; Settings accessible afterward. Setup completion flags, microphone test and voice command left unchanged. |
| General | Toggle-to-talk off/on; pause on/off; shortcut modifier and key menus; retry registration; appearance System → Light → System | Window remained accessible and original values restored. Shortcut access correctly remains unavailable without Input Monitoring. Launch at login left off. Notifications briefly returned the existing OS denial alert; dismissed it and restored the toggle to off. |
| AI Providers | Connect & refresh models; repeated/double-click verification; reasoning-model menu | Actual saved-key request returned Connected. Key field left empty, saved key preserved, model unchanged. Save/Disconnect not exercised on real credentials. |
| Voice | Repeated microphone refresh; microphone selection menu; audio feedback off/on/off | Selected microphone and on-device speech preference preserved; window remained accessible. Language changes, speech policy changes and recording were not exercised in this window audit. |
| Integrations | Check current track | Actual Spotify read returned playback state and current title; no playback change or model upload. Tool descriptions inspected. |
| Permissions | Repeated Refresh permission status; Open Microphone Settings | Native System Settings opened the Microphone page; Sotto remained available. No OS grants or revocations performed. |
| Privacy | Local history on/off/on; retention menu and existing 30-day selection | History preserved; remote consent unchanged. No deletion or shorter retention selected. |
| Activity | Open and inspect actual entries | Existing activity plus the real Spotify check remained visible. No deletion performed. |
| About | Open and inspect | Correct v0.2.2 version and implementation disclosures displayed. |

Intentional minimization was also exercised using the yellow window control. Lifecycle diagnostics recorded the explicit minimize/restore pair, and Settings was accessible afterward in the same process. No other minimize event appeared in the observed process during this audit. Opening the app again through LaunchServices also showed General with the original appearance, shortcut, voice mode, pause and notification values.

## Automation limits

The native automation tool intermittently reported external interaction, unavailable capture windows and a ScreenCaptureKit invalid-parameter error. It also returned transient menu snapshots before selection changes settled. Checks were retried from fresh snapshots; failed tool calls are not counted as successful interactions. Scroll attempts could not be reliably verified in this pass and remain a manual check. An early window-close event occurred during the interrupted portion of the audit; no crash or process exit accompanied it, and its cause was not established.

This is not a claim that every Settings side effect was exercised. Destructive history operations, credential replacement/removal, new permission grants, launch registration, setup completion, live recording and every picker value still need isolated fixture or manual coverage. This audit intentionally preserved the user's data and access settings.

## Automated checks

`swift test`: 46 passed, 2 opt-in live API tests skipped, zero failures (48 discovered). New AppKit regressions assert that the Settings policy disables background movement and hiding on deactivation, keeps intentional minimization available, remains idempotent without changing the frame, and prevents decorative material/chrome from intercepting clicks. Existing provider tests cover cancellation, denial and stale responses with fixture credentials.

`./Scripts/build.sh`: succeeded. `codesign --verify --deep --strict` passed for the resulting app. Cross-version macOS, alternate global title-bar double-click preferences and physical keyboard/window gestures remain release checks.
