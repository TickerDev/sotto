"""Policy/control-flow fixtures; these do not pretend to validate real signatures."""
import json
import os
import plistlib
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "Scripts"))
import release
import verify_release as gate

TEAM = "ABCDE12345"


class ReleaseIdentityTests(unittest.TestCase):
    def test_calendar_hardened_runtime_entitlement_and_usage_description_are_shipped(self):
        root = Path(__file__).resolve().parents[2]
        entitlements = plistlib.loads((root / "Config/Sotto.entitlements").read_bytes())
        self.assertIs(entitlements.get("com.apple.security.personal-information.calendars"), True)
        self.assertEqual(entitlements, json.loads(gate.POLICY.read_text())["entitlements"])
        info = plistlib.loads((root / "Config/Info.plist").read_bytes())
        self.assertTrue(info.get("NSCalendarsFullAccessUsageDescription"))

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.current = self.make_app("new", "6")
        self.previous = self.make_app("old", "5")
        self.calls = []
        self.team = TEAM
        self.flags = "0x10000(runtime)"
        self.timestamp = "Nov 15 2026"
        self.entitlements = json.loads(gate.POLICY.read_text())["entitlements"]
        self.architectures = b"x86_64 arm64\n"
        self.reject_requirement = None
        self.hash_pinned = False

    def make_app(self, directory, build):
        app = self.root / directory / "Sotto.app"
        (app / "Contents").mkdir(parents=True)
        self.write_info(app, {"CFBundleIdentifier": "org.sotto.mac", "CFBundleExecutable": "Sotto", "CFBundleVersion": build, "CFBundleShortVersionString": "0.2.3"})
        return app

    def write_info(self, app, info):
        (app / "Contents/Info.plist").write_bytes(plistlib.dumps(info))

    def fixture_command(self, arguments):
        self.calls.append(arguments)
        output, error = b"", b""
        if "-R" in arguments and self.reject_requirement and self.reject_requirement(arguments):
            raise gate.ReleaseError("Fixture signature does not satisfy the other release's requirement")
        if "--verbose=4" in arguments:
            error = f"TeamIdentifier={self.team}\nCodeDirectory flags={self.flags}\nTimestamp={self.timestamp}\n".encode()
        elif "-r-" in arguments:
            name = Path(arguments[-1]).parent.name
            requirement = 'cdhash H"0000"' if self.hash_pinned else f'identifier "org.sotto.mac" and info[Fixture] = "{name}"'
            error = f"designated => {requirement}\n".encode()
        elif "--entitlements" in arguments:
            output = plistlib.dumps(self.entitlements)
        elif "-archs" in arguments:
            output = self.architectures
        return subprocess.CompletedProcess(arguments, 0, output, error)

    def verify(self, **options):
        return gate.verify(self.current, TEAM, runner=self.fixture_command, **options)

    def test_update_evaluates_both_designated_requirements(self):
        report = self.verify(previous=self.previous)
        self.assertEqual(report["previousBuild"], "5")
        comparisons = [call for call in self.calls if "-R" in call and "info[Fixture]" in call[-2]]
        self.assertEqual(len(comparisons), 2)
        self.assertEqual(comparisons[0][-1], self.current.resolve())
        self.assertIn('"old"', comparisons[0][-2])
        self.assertEqual(comparisons[1][-1], self.previous.resolve())
        self.assertIn('"new"', comparisons[1][-2])

    def test_failure_in_either_direction_blocks_update(self):
        for name in ["old", "new"]:
            with self.subTest(requirement=name):
                self.reject_requirement = lambda call, name=name: f'"{name}"' in str(call[-2])
                with self.assertRaises(gate.ReleaseError):
                    self.verify(previous=self.previous)

    def test_missing_or_ambiguous_baseline_is_rejected(self):
        for options in [{}, {"previous": self.previous, "first_release": True}]:
            with self.assertRaises(gate.ReleaseError):
                self.verify(**options)

    def test_first_release_is_explicit_and_not_automatically_notarized(self):
        report = self.verify(first_release=True)
        self.assertFalse(report["notarizationChecked"])
        self.assertNotIn("previousBuild", report)

    def test_team_change_is_rejected(self):
        self.team = "OTHER12345"
        with self.assertRaisesRegex(gate.ReleaseError, "team"):
            self.verify(first_release=True)

    def test_debug_or_new_entitlements_are_rejected(self):
        for key in ["com.apple.security.get-task-allow", "com.apple.security.cs.disable-library-validation"]:
            with self.subTest(key=key):
                self.entitlements[key] = True
                with self.assertRaisesRegex(gate.ReleaseError, "Entitlements"):
                    self.verify(first_release=True)
                del self.entitlements[key]

    def test_bundle_identity_change_is_rejected(self):
        info = plistlib.loads((self.current / "Contents/Info.plist").read_bytes())
        info["CFBundleIdentifier"] = "org.sotto.other"
        self.write_info(self.current, info)
        with self.assertRaisesRegex(gate.ReleaseError, "identifier"):
            self.verify(first_release=True)

    def test_non_increasing_build_is_rejected(self):
        for build in ["5", "4"]:
            info = plistlib.loads((self.current / "Contents/Info.plist").read_bytes())
            info["CFBundleVersion"] = build
            self.write_info(self.current, info)
            with self.assertRaisesRegex(gate.ReleaseError, "greater"):
                self.verify(previous=self.previous)

    def test_build_number_comparison_is_numeric(self):
        self.assertGreater(gate.build_number("10"), gate.build_number("9"))
        self.assertEqual(gate.build_number("5"), gate.build_number("5.0.0"))
        for value in [None, "5b1", "1.2.3.4", "5\n"]:
            with self.assertRaises(gate.ReleaseError):
                gate.build_number(value)

    def test_missing_runtime_or_timestamp_is_rejected(self):
        self.flags = "0x0(none)"
        with self.assertRaisesRegex(gate.ReleaseError, "Runtime"):
            self.verify(first_release=True)
        self.flags = "0x10000(runtime)"
        self.timestamp = "none"
        with self.assertRaisesRegex(gate.ReleaseError, "timestamp"):
            self.verify(first_release=True)

    def test_hash_pinned_requirement_is_rejected(self):
        self.hash_pinned = True
        with self.assertRaisesRegex(gate.ReleaseError, "pin"):
            self.verify(first_release=True)

    def test_missing_architecture_is_rejected(self):
        self.architectures = b"arm64\n"
        with self.assertRaisesRegex(gate.ReleaseError, "architectures"):
            self.verify(first_release=True)

    def test_distribution_gate_checks_stapling_and_gatekeeper(self):
        report = self.verify(first_release=True, notarized=True)
        self.assertTrue(report["notarizationChecked"])
        self.assertTrue(any("stapler" in call and "validate" in call for call in self.calls))
        self.assertTrue(any("--assess" in call for call in self.calls))

    def test_release_configuration_never_falls_back_to_development(self):
        with patch.dict(os.environ, {}, clear=True):
            with self.assertRaisesRegex(gate.ReleaseError, "explicit release"):
                release.required_environment()
        config = {"SOTTO_RELEASE_TEAM": TEAM, "SOTTO_NOTARY_PROFILE": "fixture-profile"}
        for identity in ["-", "Apple Development: Fixture", "Developer ID Application"]:
            with patch.dict(os.environ, {**config, "SOTTO_RELEASE_IDENTITY": identity}, clear=True):
                with self.assertRaises(gate.ReleaseError):
                    release.required_environment()


if __name__ == "__main__":
    unittest.main()
