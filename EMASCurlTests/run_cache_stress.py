#!/usr/bin/env python3
"""Run opt-in cache scenarios from existing Xcode test builds; preserve every result."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import re
import signal
import subprocess


def configured_run(source, output, iterations):
    source = source.resolve()
    data = plistlib.loads(source.read_bytes())

    def visit(value):
        if isinstance(value, dict):
            result = {key: visit(item) for key, item in value.items()}
            if "TestBundlePath" in result:
                result.setdefault("EnvironmentVariables", {})["EMASCURL_CACHE_STRESS_ITERATIONS"] = str(iterations)
            return result
        if isinstance(value, list):
            return [visit(item) for item in value]
        if isinstance(value, str):
            return value.replace("__TESTROOT__", str(source.parent))
        return value

    output.write_bytes(plistlib.dumps(visit(data)))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--variant", action="append", required=True, metavar="NAME=FILE.xctestrun")
    parser.add_argument("--destination", required=True, help="xcodebuild destination, including a concrete device id")
    parser.add_argument("--iterations", type=int, default=20000)
    parser.add_argument("--rounds", type=int, default=3)
    parser.add_argument("--timeout", type=int, default=240)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if not 1 <= args.iterations <= 1000000 or not 1 <= args.rounds <= 100 or args.timeout <= 0:
        parser.error("iterations must be 1..1000000, rounds 1..100 and timeout positive")
    args.output.mkdir(parents=True, exist_ok=False)
    variants = []
    names = set()
    for variant in args.variant:
        name, separator, path = variant.partition("=")
        if not separator or not re.fullmatch(r"[A-Za-z0-9_-]+", name):
            parser.error("variant must be NAME=FILE.xctestrun with a simple NAME")
        if name in names:
            parser.error("variant names must be unique")
        names.add(name)
        configured = args.output / (name + ".xctestrun")
        configured_run(Path(path), configured, args.iterations)
        variants.append((name, configured))
    methods = ["testTwoReadersWithCallbackHandoff", "test304UpdatesWithTwoReadersAndCallbackHandoff"]
    records = []
    for round_number in range(1, args.rounds + 1):
        for method in methods:
            # Reverse build order on alternating rounds to reduce fixed ordering bias.
            for name, configured in variants[::1 if round_number % 2 else -1]:
                stem = f"{name}-{method}-{round_number}"
                result_path = args.output / (stem + ".xcresult")
                log_path = args.output / (stem + ".log")
                command = ["xcodebuild", "test-without-building", "-xctestrun", str(configured),
                           "-destination", args.destination, "-parallel-testing-enabled", "NO",
                           "-only-testing:EMASCurlTests/EMASCurlCacheStressTest/" + method,
                           "-resultBundlePath", str(result_path)]
                timed_out = False
                with log_path.open("w") as log:
                    process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
                    try:
                        returncode = process.wait(timeout=args.timeout)
                    except subprocess.TimeoutExpired:
                        timed_out = True
                        os.killpg(process.pid, signal.SIGTERM)
                        try:
                            returncode = process.wait(timeout=15)
                        except subprocess.TimeoutExpired:
                            os.killpg(process.pid, signal.SIGKILL)
                            returncode = process.wait()
                text = log_path.read_text(errors="replace")
                reports = []
                for match in re.findall(r"CACHE_STRESS_RESULT (\{[^\n]*\})", text):
                    try:
                        reports.append(json.loads(match))
                    except json.JSONDecodeError:
                        pass
                record = {"variant": name, "method": method, "round": round_number, "returncode": returncode,
                          "timed_out": timed_out, "reports": reports, "log": str(log_path), "xcresult": str(result_path)}
                expected_scenario = "304_two_readers" if "304" in method else "store_two_readers"
                valid_report = (len(reports) == 1 and reports[0].get("passed") is True and
                                reports[0].get("scenario") == expected_scenario and
                                reports[0].get("iterations_per_worker") == args.iterations)
                record["status"] = "passed" if not timed_out and returncode == 0 and valid_report else "needs_inspection"
                records.append(record)
                (args.output / "results.json").write_text(json.dumps(records, indent=2) + "\n")
                print(json.dumps(record), flush=True)
    # A missing report may be a launch failure or test crash; never count it as a pass or classify it without inspecting xcresult.
    return 0 if all(item["status"] == "passed" for item in records) else 1


if __name__ == "__main__":
    raise SystemExit(main())
