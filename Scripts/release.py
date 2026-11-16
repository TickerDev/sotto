#!/usr/bin/env python3
"""Archive, export, check continuity, notarize and package an official Sotto build."""
import argparse
import json
import os
import plistlib
import re
import subprocess
import sys
import tempfile
from pathlib import Path

from verify_release import ROOT, ReleaseError, verify


def command(arguments):
    subprocess.run([str(arg) for arg in arguments], check=True, cwd=ROOT)


def required_environment():
    names = ["SOTTO_RELEASE_TEAM", "SOTTO_RELEASE_IDENTITY", "SOTTO_NOTARY_PROFILE"]
    values = {name: os.environ.get(name, "").strip() for name in names}
    missing = [name for name, value in values.items() if not value]
    if missing:
        raise ReleaseError("Set explicit release configuration: " + ", ".join(missing))
    if not re.fullmatch(r"[A-Z0-9]{10}", values["SOTTO_RELEASE_TEAM"]):
        raise ReleaseError("SOTTO_RELEASE_TEAM must be a ten-character Team ID")
    if not (values["SOTTO_RELEASE_IDENTITY"].startswith("Developer ID Application: ") or re.fullmatch(r"[0-9A-Fa-f]{40}", values["SOTTO_RELEASE_IDENTITY"])):
        raise ReleaseError("An explicit Developer ID Application identity name or certificate SHA-1 is required; no development/ad-hoc fallback")
    return values


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--previous-app", type=Path, help="The unchanged app from the last official release")
    group.add_argument("--first-release", action="store_true", help="Only for establishing the initial official identity")
    args = parser.parse_args()
    try:
        config = required_environment()
        previous = args.previous_app.resolve() if args.previous_app else None
        if previous and not (previous / "Contents/Info.plist").is_file():
            raise ReleaseError("The previous official app is missing")
        # A new directory prevents stale archives or failed submissions being packaged.
        base = ROOT / "build/releases"
        base.mkdir(parents=True, exist_ok=True)
        output = Path(tempfile.mkdtemp(prefix="release-", dir=base))
        archive, exported = output / "Sotto.xcarchive", output / "export"
        export_options = output / "ExportOptions.plist"
        export_options.write_bytes(plistlib.dumps({
            "method": "developer-id", "signingStyle": "manual",
            "teamID": config["SOTTO_RELEASE_TEAM"], "signingCertificate": config["SOTTO_RELEASE_IDENTITY"],
        }))
        command(["/usr/bin/xcodebuild", "-project", "Sotto.xcodeproj", "-scheme", "Sotto", "-configuration", "Release",
                 "-derivedDataPath", output / "DerivedData", "-archivePath", archive,
                 "CODE_SIGN_STYLE=Manual", "CODE_SIGN_IDENTITY=" + config["SOTTO_RELEASE_IDENTITY"],
                 "DEVELOPMENT_TEAM=" + config["SOTTO_RELEASE_TEAM"], "CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO",
                 "OTHER_CODE_SIGN_FLAGS=--timestamp", "ENABLE_HARDENED_RUNTIME=YES", "ONLY_ACTIVE_ARCH=NO", "ARCHS=arm64 x86_64", "archive"])
        command(["/usr/bin/xcodebuild", "-exportArchive", "-archivePath", archive, "-exportOptionsPlist", export_options, "-exportPath", exported])
        app = exported / "Sotto.app"
        verify(app, config["SOTTO_RELEASE_TEAM"], previous, args.first_release)
        submission = output / "notary-submission.zip"
        command(["/usr/bin/ditto", "-c", "-k", "--keepParent", app, submission])
        result_file = output / "notary-result.json"
        with result_file.open("wb") as file:
            subprocess.run(["/usr/bin/xcrun", "notarytool", "submit", str(submission), "--keychain-profile", config["SOTTO_NOTARY_PROFILE"], "--wait", "--output-format", "json"], stdout=file, check=True)
        result = json.loads(result_file.read_text())
        if result.get("status") != "Accepted":
            raise ReleaseError(f"Notarization was not accepted; inspect {result_file}")
        command(["/usr/bin/xcrun", "stapler", "staple", app])
        report = verify(app, config["SOTTO_RELEASE_TEAM"], previous, args.first_release, notarized=True)
        report["notarizationSubmission"] = result["id"]
        (output / "identity-report.json").write_text(json.dumps(report, indent=2) + "\n")
        package = output / f"Sotto-{report['version']}-{report['build']}.zip"
        command(["/usr/bin/ditto", "-c", "-k", "--keepParent", app, package])
        print(f"Signed, notarized package: {package}\nKeep the exported app and identity-report.json as the next release baseline.")
        print("Permission continuity still requires the documented in-place upgrade acceptance test before publishing.")
    except (ReleaseError, OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"Release stopped: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
