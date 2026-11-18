# Official releases and permission continuity

Sotto must keep the same code identity across normal updates. A System Settings switch alone is not proof that the running executable is authorized. Re-adding the current development app resolved the user's Input Monitoring mismatch; development/ad-hoc signing transitions must not become the production update process.

Apple documents that privacy authorization tracks designated requirements, and that development and distribution signing can produce different requirements. Use Apple's default Developer ID requirements unless there is a reviewed reason to customize them. A new binary hash is normal; pinning a release identity to that hash would break continuity. Certificate renewal must be checked for requirement compatibility rather than assuming that one exact certificate must be retained forever. See [Apple's distribution signing guidance](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac), [TN3127](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements), and [TN2206](https://developer.apple.com/library/archive/technotes/tn2206/).

## Establish the first official identity

- Choose the permanent publishing Apple Developer team and bundle identifier before shipping. `Config/ReleaseIdentity.json` currently specifies `org.sotto.mac`, `Sotto.app`, and executable `Sotto`. Changing these requires an explicit policy review.
- Use a Developer ID Application identity from that team. Release builds never select an arbitrary available certificate or fall back to ad-hoc/development signing. Private keys belong in the signing Keychain/CI secret store, not source control.
- Keep Hardened Runtime and the reviewed audio-input/Apple Events entitlements. Release configuration disables injected debug entitlements and requires a secure signing timestamp.
- Distribute a notarized, stapled bundle. Notarization establishes distribution trust; it does not itself migrate privacy grants. [Apple's notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)
- Settle development/beta identifiers before public distribution. They should have separate identities and installation locations so their signatures cannot interfere with the production app. The existing pre-release developer copy is deliberately unchanged by this work; moving it to a separate development identifier is still a pre-launch task and may require one-time consent again.

## Build an official package

Prerequisites: Xcode 26+, Python 3, the explicit Developer ID Application certificate/private key, and a `notarytool` Keychain credential profile configured by the release owner. No Apple account credentials are accepted by these scripts. Increment `CFBundleVersion` in `Config/Info.plist` for each release.

Set these environment variables through the release environment (values below are placeholders):

```sh
export SOTTO_RELEASE_TEAM="YOURTEAMID"
export SOTTO_RELEASE_IDENTITY="Developer ID Application: Your Publisher (YOURTEAMID)"
export SOTTO_NOTARY_PROFILE="sotto-notary"

# Only for establishing the first public release:
python3 Scripts/release.py --first-release

# Every later release must supply the unchanged previous official app:
python3 Scripts/release.py --previous-app /path/to/previous/export/Sotto.app
```

The script archives and exports using Xcode's Developer ID distribution method. Before uploading to Apple's notary service, it checks signatures, the explicit team, identifier, executable, entitlements, build number, universal architectures and secure timestamp. It then evaluates the old designated requirement against the new app and the new requirement against the old app using `codesign`. A mismatch stops the release. This supports compatible certificate renewal without accepting an unreviewed identity change.

Only an Accepted notarization submission proceeds to stapling, ticket validation, Gatekeeper assessment and final ZIP creation. Every run uses a new directory under `build/releases/`, so a failed run cannot package stale output. Nothing is installed, launched, published or uploaded to a release host. Keep the exported app, archive, identity report and notarization result as immutable release records; the exported app is the baseline for the next update. `--first-release` is not an escape hatch for an incompatible update.

The read-only checker can also validate an independently exported app:

```sh
python3 Scripts/verify_release.py /path/to/new/Sotto.app \
  --team YOURTEAMID --previous-app /path/to/previous/Sotto.app \
  --notarized --report /path/to/identity-report.json
python3 -m unittest discover -s Tests/ReleaseTests -v
```

## Required upgrade acceptance test

Signing checks reduce identity mistakes; they cannot guarantee TCC behavior on every macOS version. Before publishing each release:

1. On clean test accounts on minimum/current supported macOS, install the **previous official** app at `/Applications/Sotto.app` and grant permissions for real voice, shortcut and native-tool tests. Include both supported CPU architectures.
2. Quit Sotto. Replace the bundle in place with the exact new notarized artifact, preserving its name and install location. Launch through LaunchServices. Do not run from archive staging, remove TCC records, or reset consent as part of an update.
3. Verify the global shortcut actually starts/stops recording while another app is foreground, then test microphone/transcription, Spotify Automation and Reminders. Check actual tool effects, not only green permission labels.
4. Verify provider credentials remain readable from Keychain, history/preferences survive, and no unexpected prompt or manual remove/re-add is needed. Test denial/revocation separately so recovery remains honest.
5. Repeat when renewing a certificate, changing signing infrastructure, adding a helper, or changing entitlements. A new helper needs explicit identity/lifecycle continuity coverage before introduction. New capabilities may legitimately require new consent.

Any future updater must verify the update signature and replace the same installed bundle after a clean shutdown. It must not re-sign an installed app, migrate the publisher/team silently, or erase privacy records to hide failures. No automatic updater is implemented yet.

## Current validation limits

The 15 release policy/control-flow tests pass. Real `codesign` correctly rejects the existing Apple Development app as an official release. Xcode resolves Release to manual Developer ID signing with a timestamp, Hardened Runtime and no injected debug entitlements. CI also cross-compiles an unsigned universal Release app; this verifies production compilation and does not create a notarized distribution artifact. No Developer ID Application identity is installed here, so an actual distribution archive/export, notarization and two-version permission upgrade have **not** been executed. Those remain release-owner prerequisites, not completed certification.
