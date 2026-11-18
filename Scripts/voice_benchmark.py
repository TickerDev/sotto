#!/usr/bin/env python3
"""Read content-free Sotto voice samples from unified logs; never launch capture."""
import argparse
import json
import math
import re
import subprocess
from pathlib import Path

PHASES = {"activation", "microphoneReady", "firstPartial", "inputEnded", "finalTranscript", "firstAction", "verifiedCompletion"}
OUTCOMES = {"replaced", "transcriptionOnly", "question", "failed", "response", "verified", "needsIntelligence", "cancelled", "inputChanged"}
EVENT = re.compile(r"sample session=([A-Fa-f0-9-]{36}) (?:(?:phase=(\w+) elapsedMs=([0-9.eE+-]+))|(?:outcome=(\w+)))\Z")


def report(records, limit=100):
    sessions = {}
    for record in records:
        if not isinstance(record, dict) or record.get("subsystem") != "org.sotto.mac" or record.get("category") != "voice-timing":
            continue
        process = record.get("processImagePath")
        if process and Path(process).name != "Sotto":
            continue
        message = record.get("eventMessage", "")
        if not isinstance(message, str):
            continue
        match = EVENT.fullmatch(message)
        if not match:
            continue
        identifier, phase, elapsed, outcome = match.groups()
        if phase:
            if phase not in PHASES:
                continue
            try:
                value = float(elapsed)
            except ValueError:
                continue
            if not math.isfinite(value) or value < 0:
                continue
        elif outcome not in OUTCOMES:
            continue
        # Do not turn a partial log window into an apparently complete sample.
        if phase == "activation" and identifier not in sessions:
            sessions[identifier] = {"session": identifier, "outcome": "incomplete", "phasesMs": {}}
            if len(sessions) > limit:
                del sessions[next(iter(sessions))]
        sample = sessions.get(identifier)
        if sample is None or sample["outcome"] != "incomplete":
            continue
        if phase:
            sample["phasesMs"].setdefault(phase, value)
        else:
            # A terminal label alone is insufficient evidence of a verified action.
            sample["outcome"] = "incomplete" if outcome == "verified" and "verifiedCompletion" not in sample["phasesMs"] else outcome
    for sample in sessions.values():
        phases = sample["phasesMs"]
        intervals = {}
        for name, start, end in [
            ("inputEndToFinalMs", "inputEnded", "finalTranscript"),
            ("inputEndToFirstActionMs", "inputEnded", "firstAction"),
            ("inputEndToVerifiedCompletionMs", "inputEnded", "verifiedCompletion"),
            ("finalTranscriptToFirstActionMs", "finalTranscript", "firstAction"),
        ]:
            if start in phases and end in phases:
                intervals[name] = max(0, phases[end] - phases[start])
        sample["intervalsMs"] = intervals
    return {"schemaVersion": 1, "sessions": list(sessions.values())}


def read_records(raw):
    try:
        decoded = json.loads(raw)
        return decoded if isinstance(decoded, list) else [decoded]
    except json.JSONDecodeError:
        records = []
        for line in raw.splitlines():
            try:
                records.append(json.loads(line))
            except json.JSONDecodeError:
                pass  # log show may include a non-JSON preamble
        return records


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--last", default="15m", help="Unified log interval, for example 15m or 1h")
    parser.add_argument("--input", type=Path, help="Read an existing JSON/NDJSON log export instead")
    args = parser.parse_args()
    if args.input:
        raw = args.input.read_text()
    else:
        result = subprocess.run(["/usr/bin/log", "show", "--style", "ndjson", "--info", "--last", args.last,
                                 "--predicate", 'process == "Sotto" AND subsystem == "org.sotto.mac" AND category == "voice-timing"'],
                                check=True, capture_output=True, text=True, timeout=30)
        raw = result.stdout
    print(json.dumps(report(read_records(raw)), indent=2, allow_nan=False))


if __name__ == "__main__":
    main()
