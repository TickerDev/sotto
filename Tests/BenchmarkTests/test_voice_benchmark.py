import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "Scripts"))
from voice_benchmark import read_records, report

A = "00000000-0000-0000-0000-000000000001"
B = "00000000-0000-0000-0000-000000000002"


def event(session, message):
    return {"subsystem": "org.sotto.mac", "category": "voice-timing", "eventMessage": f"sample session={session} {message}"}


class VoiceBenchmarkTests(unittest.TestCase):
    def test_interleaving_and_late_callbacks_cannot_change_finished_samples(self):
        samples = report([event(A, "phase=activation elapsedMs=0"), event(B, "phase=activation elapsedMs=0"),
                          event(A, "outcome=cancelled"), event(A, "phase=verifiedCompletion elapsedMs=900"),
                          event(B, "phase=finalTranscript elapsedMs=300"), event(B, "outcome=transcriptionOnly")])["sessions"]
        self.assertEqual([s["outcome"] for s in samples], ["cancelled", "transcriptionOnly"])
        self.assertNotIn("verifiedCompletion", samples[0]["phasesMs"])
        self.assertNotIn("firstAction", samples[1]["phasesMs"])

    def test_partial_windows_invalid_durations_and_unrelated_content_are_excluded(self):
        records = [event(B, "phase=firstAction elapsedMs=10"), event(A, "phase=activation elapsedMs=0"),
                   event(A, "phase=microphoneReady elapsedMs=1e999"), event(A, "phase=firstAction elapsedMs=-2"),
                   event(A, "phase=transcript elapsedMs=10"), event(A, "outcome=private words"),
                   {"eventMessage": "Personal content"}, event(A, "outcome=verified")]
        sample = report(records)["sessions"][0]
        self.assertEqual(sample["phasesMs"], {"activation": 0})
        self.assertEqual(sample["outcome"], "incomplete")
        self.assertEqual(len(report(records)["sessions"]), 1)

    def test_test_processes_and_malformed_messages_cannot_become_physical_samples(self):
        fixture = event(A, "phase=activation elapsedMs=0")
        fixture["processImagePath"] = "/tmp/SottoTests.xctest"
        malformed = event(B, "phase=activation elapsedMs=0")
        malformed["eventMessage"] = None
        self.assertEqual(report([fixture, malformed])["sessions"], [])

    def test_bound_and_verified_evidence(self):
        samples = report([event(A, "phase=activation elapsedMs=0"), event(B, "phase=activation elapsedMs=0"),
                          event(B, "phase=verifiedCompletion elapsedMs=500"), event(B, "outcome=verified")], limit=1)["sessions"]
        self.assertEqual(len(samples), 1)
        self.assertEqual(samples[0]["session"], B)
        self.assertEqual(samples[0]["outcome"], "verified")

    def test_intervals_use_actual_release_and_keep_missing_action_phases_absent(self):
        sample = report([event(A, "phase=activation elapsedMs=0"),
                         event(A, "phase=inputEnded elapsedMs=50"),
                         event(A, "phase=microphoneReady elapsedMs=200"),
                         event(A, "phase=finalTranscript elapsedMs=250"),
                         event(A, "outcome=transcriptionOnly")])["sessions"][0]
        self.assertEqual(sample["intervalsMs"], {"inputEndToFinalMs": 200})

    def test_json_array_and_ndjson_with_preamble(self):
        self.assertEqual(read_records('[{"a":1}]'), [{"a": 1}])
        self.assertEqual(read_records('Filtering log data\n{"a":1}\n{"b":2}\n'), [{"a": 1}, {"b": 2}])


if __name__ == "__main__":
    unittest.main()
