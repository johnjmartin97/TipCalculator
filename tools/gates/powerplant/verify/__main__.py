"""Run the deterministic gate suite against a checkout.

    python -m powerplant.verify /path/to/project

This is what CI invokes. It is the same code the build loop runs per ticket, so
the check that decides a merge and the check a ticket passed locally cannot
disagree.

Exit code is the gate result: 0 green, 1 red. That exit code is the evidence —
not the summary it prints, and not anything written into a pull request body.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import sys
from pathlib import Path

from .suite import run_suite


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="powerplant.verify",
        description="Run the deterministic gates against a project checkout.",
    )
    parser.add_argument("project_dir", help="the checkout to verify")
    parser.add_argument("--scheme", default=None, help="override the descriptor's scheme")
    parser.add_argument("--bundle-id", default=None, help="override the descriptor's bundle id")
    parser.add_argument(
        "--no-launch",
        action="store_true",
        help="skip the simulator launch gate (for runners without a simulator)",
    )
    parser.add_argument("--json", action="store_true", help="emit results as JSON")
    parser.add_argument("--screenshot", default=None, help="where to write the launch screenshot")
    args = parser.parse_args(argv)

    project_dir = Path(args.project_dir).expanduser().resolve()
    if not project_dir.exists():
        print(f"error: {project_dir} does not exist", file=sys.stderr)
        return 2

    try:
        result = asyncio.run(
            run_suite(
                project_dir,
                scheme=args.scheme,
                bundle_id=args.bundle_id,
                screenshot=args.screenshot,
                include_launch=not args.no_launch,
            )
        )
    except FileNotFoundError as exc:
        # A CI log should say what is wrong on one line, not raise a traceback
        # at whoever has to read it at two in the morning.
        print(f"error: {exc}", file=sys.stderr)
        return 2

    if args.json:
        print(json.dumps({"passed": result.passed, "gates": result.as_dicts()}, indent=2))
    else:
        for gate in result.gates:
            print(gate.summary_line())
        print(f"\n{result.summary()}")
        if not result.passed:
            print(f"\n{result.detail()[:4000]}", file=sys.stderr)

    return 0 if result.passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
