#!/usr/bin/env python3
"""Reproduce strict portability checks; reports stay outside the package."""
import argparse
import json
import pathlib
import subprocess
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]
EXAMPLES = ["multitenant", "typed_provider", "observability"]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--moon", default="moon")
    parser.add_argument("--native", action="store_true", help="also build/test/run with an installed native C compiler")
    parser.add_argument("--report", type=pathlib.Path)
    args = parser.parse_args()
    report = {"results": [], "native_execution": "requested" if args.native else "not requested"}
    report["production_lines"] = {p.name: sum(1 for line in p.read_text(encoding="utf-8").splitlines() if line.strip() and not line.lstrip().startswith("//"))
                                  for p in sorted(ROOT.glob("*.mbt"))
                                  if not p.name.endswith(("_test.mbt", "_wbtest.mbt"))}
    report["production_total"] = sum(report["production_lines"].values())
    if report["production_total"] < 1500:
        raise SystemExit("Core production source is below the participant threshold")
    commands = [[args.moon, "version", "--all"], [args.moon, "info"],
                ["git", "diff", "--exit-code", "--", "*.mbti"],
                [args.moon, "fmt", "--check"]]
    for target in ["wasm-gc", "wasm", "js", "native"]:
        commands.append([args.moon, "check", "--deny-warn", "--target", target])
        if target != "native" or args.native:
            for operation in ["build", "test"]:
                commands.append([args.moon, operation, "--deny-warn", "--target", target])
            for example in EXAMPLES:
                commands.append([args.moon, "run", "examples/" + example, "--deny-warn", "--target", target])
    failed = False
    for command in commands:
        print("+ " + " ".join(command), flush=True)
        start = time.monotonic()
        result = subprocess.run(command, cwd=str(ROOT), stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, encoding="utf-8", errors="replace")
        print(result.stdout, end="", flush=True)
        report["results"].append({"command": command[1:], "exit_code": result.returncode,
                                  "seconds": round(time.monotonic() - start, 3), "output": result.stdout})
        if result.returncode:
            failed = True
            break
    report["passed"] = not failed
    if args.report:
        destination = args.report.resolve()
        if destination == ROOT or ROOT in destination.parents:
            raise SystemExit("Verification reports must stay outside the source/package")
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
