"""The deterministic gate suite, runnable without a graph or a runtime.

This exists as its own module for one reason: the same code has to run in three
places — per ticket in the build loop, as the integration check on `main`, and
in CI, where it becomes the evidence a reviewer is allowed to trust. Three
implementations would drift, and a gate that drifts is not a gate.

Two kinds of project run through here.

**Declared** — the project's `.powerplant.json` lists the commands that check
it. The agent that researched the stack chooses them, which is why a new kind
of work costs no change to PowerPlant. What the agent does not get to choose is
whether those commands work: every declared gate carries a canary, and the
meta-gate proves the gate goes red when the canary is present. A gate that
stays green on deliberately broken code is not a gate.

**Built-in** — iOS, whose suite is xcodebuild and the simulator. It predates
the descriptor and stays because `.pbxproj` generation is a genuine special
case rather than a stack like any other.

No model runs here. Nothing takes a `RunState`.
"""

from __future__ import annotations

import asyncio
import fnmatch
import re
import subprocess
import time
from dataclasses import dataclass, field
from pathlib import Path

from ..assets import manifest as M
from . import assets as vassets
from . import descriptor as D
from .xcode import GateResult, boot_install_launch_screenshot, build, test

DESCRIPTOR = D.DESCRIPTOR

# Test files and the build configuration are frozen for every project. What
# counts as a test file is declared per project; these are the iOS defaults.
DEFAULT_TEST_SUFFIXES = ("Tests.swift", "Test.swift", "Spec.swift", "UITests.swift")
FROZEN_CONFIG = ("project.yml",)

# A test gate that passes on zero executed tests is not a gate. `xcodebuild`
# reports the count; below this the suite fails regardless of exit status.
MIN_EXECUTED_TESTS = 1

_COMMAND_TIMEOUT_S = 1800


@dataclass
class SuiteResult:
    """Every gate that ran, and whether the set of them passed."""

    gates: list[GateResult] = field(default_factory=list)

    @property
    def passed(self) -> bool:
        return bool(self.gates) and all(g.passed for g in self.gates)

    def as_dicts(self) -> list[dict]:
        return [g.as_dict() for g in self.gates]

    def as_markdown(self) -> str:
        """The gate section of a pull request body.

        Note for anything reading this downstream: it is a *report*. It is not
        evidence, because the process that writes it can also edit it. The
        reviewer's merge decision reads a CI check run, not this text.
        """
        lines = ["## Deterministic gates", ""]
        for gate in self.gates:
            mark = "PASS" if gate.passed else "FAIL"
            lines.append(f"- **{mark}** `{gate.name}` ({gate.duration_s:.1f}s)")
        lines += [
            "",
            "These ran on the branch tip before this pull request was opened. "
            "They are the merge requirement; review adds reasons not to merge "
            "and cannot waive them.",
        ]
        return "\n".join(lines)

    def summary(self) -> str:
        failed = [g.name for g in self.gates if not g.passed]
        if not self.gates:
            return "no gates ran"
        if not failed:
            return f"{len(self.gates)} gates passed"
        return f"{len(failed)} of {len(self.gates)} gates failed: {', '.join(failed)}"

    def detail(self) -> str:
        """Why it failed, failures first. Callers must truncate from the head."""
        parts = [f"### {g.name}\n{g.detail}" for g in self.gates if not g.passed]
        return "\n\n".join(parts) or "all gates passed"


# --------------------------------------------------------------------------
# The project descriptor
# --------------------------------------------------------------------------


def write_descriptor(project_dir: str | Path, info: dict) -> Path:
    """Record how this project is built and checked.

    Written by setup once the scaffold is proven. Without it the gate suite
    would have to re-derive the toolchain, and a re-derivation that disagrees
    with the one the build used is a silent wrong answer.
    """
    return D.write(project_dir, info)


def read_descriptor(project_dir: str | Path) -> dict:
    return D.load(project_dir).raw


# --------------------------------------------------------------------------
# Running a declared command
# --------------------------------------------------------------------------


async def _shell(command: str, cwd: Path, timeout_s: float = _COMMAND_TIMEOUT_S) -> tuple[int, str]:
    """Run a declared gate command.

    Through a shell, because what is declared is a command line — `npx tsc
    --noEmit`, `npm run build`. That is the agent's own command running with
    the agent's own privileges, so it grants nothing it did not already have;
    the protection that matters is that `.powerplant.json` is frozen, so the
    command cannot be swapped mid-ticket.
    """
    proc = await asyncio.create_subprocess_shell(
        command,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.STDOUT,
        cwd=str(cwd),
    )
    try:
        out, _ = await asyncio.wait_for(proc.communicate(), timeout=timeout_s)
    except asyncio.TimeoutError:
        proc.kill()
        await proc.wait()
        return 124, f"timed out after {timeout_s}s: {command}"
    return proc.returncode or 0, out.decode("utf-8", errors="replace")


async def run_declared_gate(spec: D.GateSpec, project_dir: Path) -> GateResult:
    started = time.monotonic()
    code, out = await _shell(spec.run, project_dir)
    return GateResult(
        name=spec.name,
        passed=code == 0,
        detail=_head_and_tail(out),
        duration_s=time.monotonic() - started,
    )


def _head_and_tail(output: str, limit: int = 6000) -> str:
    """Keep both ends of a long log.

    The first error is usually at the top and the summary at the bottom, and
    taking only one end reliably discards the half that says what broke.
    """
    if len(output) <= limit:
        return output
    half = limit // 2
    return f"{output[:half]}\n\n... [{len(output) - limit} characters omitted] ...\n\n{output[-half:]}"


# --------------------------------------------------------------------------
# The meta-gate: proving a declared gate detects a fault
# --------------------------------------------------------------------------


async def prove_gate_detects_breakage(spec: D.GateSpec, project_dir: Path) -> GateResult:
    """Break the code on purpose and confirm this gate goes red.

    This is what makes a declared toolchain safe to trust. The agent picks the
    commands; without this, `"run": "echo ok"` and a real test suite are
    indistinguishable to everything downstream — and under optimisation
    pressure the difference between them is exactly what gets exploited.

    The canary is written, the gate is run, and the file is removed again
    whatever happens. A gate that passes with the canary in place has been
    shown not to detect a fault, and fails here.
    """
    started = time.monotonic()
    if spec.canary is None:
        return GateResult(
            name=f"proves:{spec.name}",
            passed=False,
            detail=f"gate {spec.name!r} declares no canary, so it has not been shown to fail",
            duration_s=time.monotonic() - started,
        )

    canary_path = project_dir / spec.canary.path
    if canary_path.exists():
        return GateResult(
            name=f"proves:{spec.name}",
            passed=False,
            detail=(
                f"canary path {spec.canary.path} already exists; refusing to overwrite "
                "a real file to run this check"
            ),
            duration_s=time.monotonic() - started,
        )

    try:
        canary_path.parent.mkdir(parents=True, exist_ok=True)
        canary_path.write_text(spec.canary.content, encoding="utf-8")
        code, out = await _shell(spec.run, project_dir)
    finally:
        canary_path.unlink(missing_ok=True)

    detected = code != 0
    return GateResult(
        name=f"proves:{spec.name}",
        passed=detected,
        detail=(
            f"gate {spec.name!r} correctly failed on a deliberate fault"
            if detected
            else (
                f"gate {spec.name!r} PASSED while {spec.canary.path} was present. "
                f"It does not detect faults, so nothing it reports means anything.\n\n"
                f"{_head_and_tail(out, 2000)}"
            )
        ),
        duration_s=time.monotonic() - started,
    )


async def prove_gates(project_dir: str | Path, desc: D.Descriptor | None = None) -> SuiteResult:
    """Run the meta-gate over every declared gate that carries a canary."""
    project_dir = Path(project_dir)
    desc = desc or D.load(project_dir)
    provable = [g for g in desc.gates if g.provable]
    results = [await prove_gate_detects_breakage(g, project_dir) for g in provable]
    return SuiteResult(results)


# --------------------------------------------------------------------------
# Checks that are not commands
# --------------------------------------------------------------------------


_EXECUTED = re.compile(r"Executed\s+(\d+)\s+test", re.IGNORECASE)


def executed_test_count(output: str) -> int:
    """The highest `Executed N tests` figure xcodebuild reported.

    Highest rather than last: the log carries one line per suite plus a total,
    and which comes last depends on ordering.
    """
    return max((int(m.group(1)) for m in _EXECUTED.finditer(output)), default=0)


def check_tests_ran(test_gate: GateResult) -> GateResult:
    """Fail when the suite passed without running anything.

    Deleting the test target from `project.yml` leaves every test file
    byte-identical and makes `xcodebuild test` exit 0 having executed nothing.
    The tamper guard cannot see that; this can.
    """
    count = executed_test_count(test_gate.detail)
    ok = count >= MIN_EXECUTED_TESTS
    return GateResult(
        name="tests-executed",
        passed=ok,
        detail=(
            f"{count} tests executed"
            if ok
            else f"only {count} tests executed (minimum {MIN_EXECUTED_TESTS}) — "
            "the suite reported success without running anything"
        ),
    )


def _matches(path: str, pattern: str) -> bool:
    if pattern.endswith("/**"):
        return path.startswith(pattern[:-3].rstrip("/") + "/")
    return fnmatch.fnmatch(path, pattern) or Path(path).name == pattern


def check_frozen_files_clean(
    project_dir: str | Path, desc: D.Descriptor | None = None
) -> GateResult:
    """No uncommitted changes to the oracle.

    The oracle is more than the tests: it is the tests, the configuration that
    decides whether they run, and `.powerplant.json`, which declares what
    checking even means. All three are frozen, because an agent that cannot
    edit a test can otherwise unhook it, and an agent that cannot unhook it can
    otherwise redefine the gate.
    """
    project_dir = Path(project_dir)
    if desc is None:
        try:
            desc = D.load(project_dir)
        except (FileNotFoundError, D.DescriptorError):
            desc = D.Descriptor(work_type="ios")

    patterns = list(desc.frozen_patterns()) + list(desc.test_globs) + list(FROZEN_CONFIG)

    result = subprocess.run(
        ["git", "status", "--porcelain"],
        cwd=str(project_dir),
        capture_output=True,
        text=True,
    )
    dirty: list[str] = []
    for line in result.stdout.splitlines():
        path = line[3:].strip()
        if not path:
            continue
        if path.endswith(DEFAULT_TEST_SUFFIXES) or any(_matches(path, p) for p in patterns):
            dirty.append(path)

    return GateResult(
        "tamper-guard",
        passed=not dirty,
        detail=(
            "no uncommitted changes to tests, build configuration or the descriptor"
            if not dirty
            else f"uncommitted: {', '.join(sorted(set(dirty)))}"
        ),
    )


# --------------------------------------------------------------------------
# The suite
# --------------------------------------------------------------------------


async def run_suite(
    project_dir: str | Path,
    *,
    scheme: str | None = None,
    bundle_id: str | None = None,
    screenshot: str | Path | None = None,
    include_launch: bool = True,
    prove: bool = True,
) -> SuiteResult:
    """Run every deterministic gate against a working tree.

    A project that declares its own gates runs those, preceded by the meta-gate
    that shows each one detects a fault. Otherwise the built-in iOS suite runs.
    """
    project_dir = Path(project_dir)
    desc = D.load(project_dir)

    if desc.declares_gates:
        return await _run_declared_suite(project_dir, desc, prove=prove)

    return await _run_ios_suite(
        project_dir,
        desc,
        scheme=scheme,
        bundle_id=bundle_id,
        screenshot=screenshot,
        include_launch=include_launch,
    )


async def _run_declared_suite(
    project_dir: Path, desc: D.Descriptor, *, prove: bool
) -> SuiteResult:
    gates: list[GateResult] = []

    # Proof first. If a gate cannot detect a fault, its verdict is worthless,
    # and running it before establishing that just produces a confident number.
    if prove:
        gates.extend((await prove_gates(project_dir, desc)).gates)

    for spec in desc.gates:
        gates.append(await run_declared_gate(spec, project_dir))

    gates.append(check_frozen_files_clean(project_dir, desc))
    return SuiteResult(gates)


async def _run_ios_suite(
    project_dir: Path,
    desc: D.Descriptor,
    *,
    scheme: str | None,
    bundle_id: str | None,
    screenshot: str | Path | None,
    include_launch: bool,
) -> SuiteResult:
    scheme = scheme or desc.scheme
    bundle_id = bundle_id or desc.bundle_id
    if not scheme:
        raise D.DescriptorError("no scheme declared and none supplied")

    gates: list[GateResult] = [await build(project_dir, scheme=scheme)]

    test_gate = await test(project_dir, scheme=scheme)
    gates.append(test_gate)
    gates.append(check_tests_ran(test_gate))
    gates.append(check_frozen_files_clean(project_dir, desc))

    manifest_path = project_dir / "assets.json"
    if manifest_path.exists():
        try:
            specs = M.load(manifest_path)
        except M.ManifestError as exc:
            gates.append(GateResult("asset-manifest", False, f"manifest will not parse: {exc}"))
        else:
            gates.append(vassets.check_manifest(specs, project_dir))

    if include_launch:
        shot = Path(screenshot) if screenshot else project_dir / ".build" / "launch.png"
        gates.append(
            await boot_install_launch_screenshot(
                project_dir, scheme=scheme, bundle_id=bundle_id, out_png=shot
            )
        )

    return SuiteResult(gates)
