#!/usr/bin/env python3
"""Fail-closed release identity and update compatibility checks. Never launches apps."""
import argparse
import json
import plistlib
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
POLICY = ROOT / "Config/ReleaseIdentity.json"


class ReleaseError(Exception):
    pass


def run(arguments):
    result = subprocess.run([str(arg) for arg in arguments], capture_output=True, check=False)
    if result.returncode:
        raise ReleaseError(f"{arguments[0]} failed: {result.stderr.decode(errors='replace').strip()}")
    return result


def build_number(value):
    if not isinstance(value, str) or not re.fullmatch(r"[0-9]+(?:\.[0-9]+){0,2}", value):
        raise ReleaseError("CFBundleVersion must be a numeric build number with at most three components")
    parts = tuple(int(part) for part in value.split("."))
    return parts + (0,) * (3 - len(parts))


def inspect(app, team, policy, runner=run):
    app = Path(app).resolve()
    if not re.fullmatch(r"[A-Z0-9]{10}", team):
        raise ReleaseError("An explicit ten-character release Team ID is required")
    with (app / "Contents/Info.plist").open("rb") as file:
        info = plistlib.load(file)
    if app.name != policy["bundleName"] or info.get("CFBundleIdentifier") != policy["bundleIdentifier"] or info.get("CFBundleExecutable") != policy["executable"]:
        raise ReleaseError("Bundle name, identifier or executable changed; review the release identity policy")
    build_number(info.get("CFBundleVersion"))
    runner(["/usr/bin/codesign", "--verify", "--deep", "--strict", "--all-architectures", app])
    # Evaluate the certificate chain with Apple's tool, not just its display name.
    requirement = (f'identifier "{policy["bundleIdentifier"]}" and anchor apple generic '
                   f'and certificate leaf[field.1.2.840.113635.100.6.1.13] exists '
                   f'and certificate leaf[subject.OU] = "{team}"')
    runner(["/usr/bin/codesign", "--verify", "--strict", "--all-architectures", "-R", "=" + requirement, app])
    result = runner(["/usr/bin/codesign", "--display", "--verbose=4", app])
    details = (result.stdout + result.stderr).decode(errors="replace")
    if f"TeamIdentifier={team}" not in details.splitlines():
        raise ReleaseError("Signing team does not match the configured release team")
    flags = re.search(r"\bflags=0x([0-9a-fA-F]+)", details)
    if not flags or not int(flags[1], 16) & 0x10000:
        raise ReleaseError("Hardened Runtime is required")
    timestamp = next((line.partition("=")[2] for line in details.splitlines() if line.startswith("Timestamp=")), "")
    if not timestamp or timestamp.lower() == "none":
        raise ReleaseError("A secure signing timestamp is required")
    result = runner(["/usr/bin/codesign", "--display", "-r-", app])
    text = (result.stdout + result.stderr).decode(errors="replace")
    designated = re.search(r"^#?\s*designated => (.+)$", text, re.MULTILINE)
    if not designated:
        raise ReleaseError("No designated requirement found")
    if re.search(r"\bcdhash\b|\bcertificate\s+(?:leaf|0)\s*=", designated[1]):
        raise ReleaseError("Release identity must not pin a build hash or leaf certificate hash")
    result = runner(["/usr/bin/codesign", "--display", "--entitlements", ":-", app])
    entitlements = plistlib.loads(result.stdout) if result.stdout.strip() else {}
    if entitlements != policy["entitlements"]:
        raise ReleaseError("Entitlements differ from the reviewed release policy (debug entitlements are forbidden)")
    executable = app / "Contents/MacOS" / policy["executable"]
    architectures = runner(["/usr/bin/lipo", "-archs", executable]).stdout.decode().split()
    return {
        "bundleIdentifier": info["CFBundleIdentifier"], "executable": info["CFBundleExecutable"],
        "version": info.get("CFBundleShortVersionString"), "build": info["CFBundleVersion"],
        "team": team, "designatedRequirement": designated[1], "entitlements": entitlements,
        "architectures": sorted(architectures), "timestamp": timestamp,
    }


def verify(app, team, previous=None, first_release=False, notarized=False, runner=run):
    if bool(previous) == bool(first_release):
        raise ReleaseError("Supply the previous official Sotto.app, or explicitly select the first public release")
    policy = json.loads(POLICY.read_text())
    current = inspect(app, team, policy, runner)
    if not set(policy["architectures"]).issubset(current["architectures"]):
        raise ReleaseError("Release must contain both Apple Silicon and Intel architectures")
    if previous:
        old = inspect(previous, team, policy, runner)
        if build_number(current["build"]) <= build_number(old["build"]):
            raise ReleaseError("Update build number must be greater than the previous release")
        # Test semantic compatibility in BOTH directions, allowing certificate renewal
        # only when Apple's actual requirement evaluation accepts the two signatures.
        for target, requirement in [(app, old["designatedRequirement"]), (previous, current["designatedRequirement"])]:
            runner(["/usr/bin/codesign", "--verify", "--strict", "--all-architectures", "-R", "=" + requirement, Path(target).resolve()])
        current["previousBuild"] = old["build"]
    if notarized:
        runner(["/usr/bin/xcrun", "stapler", "validate", Path(app).resolve()])
        runner(["/usr/sbin/spctl", "--assess", "--type", "execute", "--verbose=2", Path(app).resolve()])
    current["notarizationChecked"] = notarized
    return current


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("--team", required=True)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--previous-app", type=Path)
    group.add_argument("--first-release", action="store_true")
    parser.add_argument("--notarized", action="store_true", help="Also require stapling and Gatekeeper acceptance")
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    try:
        report = verify(args.app, args.team, args.previous_app, args.first_release, args.notarized)
        if args.report:
            args.report.write_text(json.dumps(report, indent=2) + "\n")
        print(f"Release identity verified: {report['bundleIdentifier']} build {report['build']}")
    except (ReleaseError, OSError, ValueError, plistlib.InvalidFileException) as error:
        print(f"Release rejected: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
