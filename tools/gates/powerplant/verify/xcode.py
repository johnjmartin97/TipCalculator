"""The oracle: xcodebuild and the iOS Simulator.

Nothing in this file involves a model. A build either compiles or it doesn't, a
test suite either passes or it doesn't, and the app either appears on a booted
simulator or it doesn't. That is the entire point — a loop closed on real
compilers and real tests measures better than one closed on the agent's own
judgement, and by a wide margin.

The agent can call these. It cannot change what they mean.
"""

from __future__ import annotations

import asyncio
import json
import logging
import shutil
import subprocess
import time
from dataclasses import dataclass, field
from pathlib import Path

log = logging.getLogger(__name__)

DEFAULT_DEVICE = "iPhone 17"
DEFAULT_OS = "latest"
_MAX_DETAIL = 6000


@dataclass
class GateResult:
    """The outcome of one deterministic check."""

    name: str
    passed: bool
    detail: str = ""
    duration_s: float = 0.0
    artifacts: list[str] = field(default_factory=list)

    def as_dict(self) -> dict:
        return {
            "name": self.name,
            "passed": self.passed,
            "detail": self.detail[-_MAX_DETAIL:],
            "duration_s": round(self.duration_s, 2),
            "artifacts": self.artifacts,
        }

    def summary_line(self) -> str:
        mark = "PASS" if self.passed else "FAIL"
        return f"{mark}  {self.name}  ({self.duration_s:.1f}s)"


async def _run(
    argv: list[str], *, cwd: str | Path | None = None, timeout_s: float = 1800
) -> tuple[int, str]:
    """Run a command, returning (exit code, combined output)."""
    proc = await asyncio.create_subprocess_exec(
        *argv,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.STDOUT,
        cwd=str(cwd) if cwd else None,
    )
    try:
        out, _ = await asyncio.wait_for(proc.communicate(), timeout=timeout_s)
    except asyncio.TimeoutError:
        proc.kill()
        await proc.wait()
        return 124, f"timed out after {timeout_s}s: {' '.join(argv[:4])}"
    return proc.returncode or 0, out.decode("utf-8", errors="replace")


def toolchain_available() -> tuple[bool, str]:
    """Check the Xcode toolchain exists before a run depends on it."""
    missing = [t for t in ("xcodebuild", "xcrun", "xcodegen") if not shutil.which(t)]
    if missing:
        return False, f"missing tools: {', '.join(missing)}"
    return True, "ok"


# -- simulator -------------------------------------------------------------


def find_simulator(device: str = DEFAULT_DEVICE) -> tuple[str, str] | None:
    """Return (udid, name) for an available simulator, preferring `device`."""
    try:
        raw = subprocess.run(
            ["xcrun", "simctl", "list", "devices", "available", "-j"],
            capture_output=True,
            text=True,
            timeout=60,
        ).stdout
        data = json.loads(raw)
    except (subprocess.SubprocessError, json.JSONDecodeError, OSError) as exc:
        log.warning("could not list simulators: %s", exc)
        return None

    candidates: list[tuple[str, str]] = []
    for runtime, devices in (data.get("devices") or {}).items():
        if "iOS" not in runtime:
            continue
        for dev in devices:
            if dev.get("isAvailable") and dev.get("udid"):
                candidates.append((dev["udid"], dev.get("name", "")))

    if not candidates:
        return None
    for udid, name in candidates:
        if name == device:
            return udid, name
    for udid, name in candidates:
        if name.startswith("iPhone"):
            return udid, name
    return candidates[0]


def destination(device: str = DEFAULT_DEVICE) -> str:
    return f"platform=iOS Simulator,name={device},OS={DEFAULT_OS}"


# -- gates -----------------------------------------------------------------


async def build(
    project_dir: str | Path,
    *,
    scheme: str,
    device: str = DEFAULT_DEVICE,
    derived_data: str | Path | None = None,
) -> GateResult:
    """Compile the app. The cheapest, most independent check there is."""
    started = time.monotonic()
    argv = [
        "xcodebuild",
        "build",
        "-scheme",
        scheme,
        "-destination",
        destination(device),
        "-quiet",
    ]
    if derived_data:
        argv += ["-derivedDataPath", str(derived_data)]
    code, out = await _run(argv, cwd=project_dir)
    return GateResult(
        name="xcodebuild-build",
        passed=code == 0,
        detail=out[-_MAX_DETAIL:],
        duration_s=time.monotonic() - started,
    )


async def test(
    project_dir: str | Path,
    *,
    scheme: str,
    device: str = DEFAULT_DEVICE,
    only_testing: str | None = None,
    derived_data: str | Path | None = None,
) -> GateResult:
    """Run the test suite, including the exhaustive game-logic oracle."""
    started = time.monotonic()
    argv = [
        "xcodebuild",
        "test",
        "-scheme",
        scheme,
        "-destination",
        destination(device),
    ]
    if only_testing:
        argv += ["-only-testing", only_testing]
    if derived_data:
        argv += ["-derivedDataPath", str(derived_data)]
    code, out = await _run(argv, cwd=project_dir)
    return GateResult(
        name="xcodebuild-test" if not only_testing else f"xcodebuild-test:{only_testing}",
        passed=code == 0,
        detail=_test_summary(out),
        duration_s=time.monotonic() - started,
    )


async def boot_install_launch_screenshot(
    project_dir: str | Path,
    *,
    scheme: str,
    bundle_id: str,
    out_png: str | Path,
    device: str = DEFAULT_DEVICE,
    derived_data: str | Path | None = None,
    settle_s: float = 4.0,
) -> GateResult:
    """Prove the app actually runs, not merely that it compiles.

    A silent fallback to the wrong runtime makes every later failure look like
    a product bug, so this boots a real simulator, installs the built app,
    launches it, and captures the screen.
    """
    started = time.monotonic()
    out_png = Path(out_png)
    out_png.parent.mkdir(parents=True, exist_ok=True)

    sim = find_simulator(device)
    if sim is None:
        return GateResult(
            name="simulator-launch",
            passed=False,
            detail="no available iOS simulator found",
            duration_s=time.monotonic() - started,
        )
    udid, sim_name = sim

    dd = Path(derived_data) if derived_data else Path(project_dir) / ".build" / "dd"
    log_parts: list[str] = [f"simulator: {sim_name} ({udid})"]

    code, out = await _run(
        [
            "xcodebuild",
            "build",
            "-scheme",
            scheme,
            "-destination",
            f"id={udid}",
            "-derivedDataPath",
            str(dd),
            "-quiet",
        ],
        cwd=project_dir,
    )
    log_parts.append(out[-2000:])
    if code != 0:
        return GateResult(
            name="simulator-launch",
            passed=False,
            detail="\n".join(log_parts),
            duration_s=time.monotonic() - started,
        )

    apps = sorted(dd.glob("Build/Products/*-iphonesimulator/*.app"))
    if not apps:
        log_parts.append(f"no .app produced under {dd}")
        return GateResult(
            name="simulator-launch",
            passed=False,
            detail="\n".join(log_parts),
            duration_s=time.monotonic() - started,
        )
    app_path = apps[-1]
    log_parts.append(f"app: {app_path}")

    # `boot` on an already-booted device returns non-zero; that is not a failure.
    await _run(["xcrun", "simctl", "boot", udid], timeout_s=180)
    await _run(["xcrun", "simctl", "bootstatus", udid, "-b"], timeout_s=300)

    code, out = await _run(["xcrun", "simctl", "install", udid, str(app_path)], timeout_s=300)
    log_parts.append(f"install: {out.strip()[-500:]}")
    if code != 0:
        return GateResult(
            name="simulator-launch",
            passed=False,
            detail="\n".join(log_parts),
            duration_s=time.monotonic() - started,
        )

    code, out = await _run(["xcrun", "simctl", "launch", udid, bundle_id], timeout_s=180)
    log_parts.append(f"launch: {out.strip()[-500:]}")
    if code != 0:
        return GateResult(
            name="simulator-launch",
            passed=False,
            detail="\n".join(log_parts),
            duration_s=time.monotonic() - started,
        )

    await asyncio.sleep(settle_s)  # let the first frame render
    code, out = await _run(
        ["xcrun", "simctl", "io", udid, "screenshot", str(out_png)], timeout_s=120
    )
    ok = code == 0 and out_png.exists() and out_png.stat().st_size > 0
    log_parts.append(f"screenshot: {out.strip()[-300:]}")

    return GateResult(
        name="simulator-launch",
        passed=ok,
        detail="\n".join(log_parts),
        duration_s=time.monotonic() - started,
        artifacts=[str(out_png)] if ok else [],
    )


async def generate_project(project_dir: str | Path) -> GateResult:
    """Run xcodegen so the .xcodeproj is derived, never hand-edited."""
    started = time.monotonic()
    code, out = await _run(["xcodegen", "generate"], cwd=project_dir, timeout_s=300)
    return GateResult(
        name="xcodegen",
        passed=code == 0,
        detail=out[-2000:],
        duration_s=time.monotonic() - started,
    )


def _test_summary(output: str) -> str:
    """Extract what a person needs to fix the failure.

    Ordered by usefulness rather than by position in the log: the individual
    assertion failures first, then the counts. A summary that is mostly
    "Test Suite ... started" lines pushes the actual failures out of the
    truncation window, which makes a halt report say nothing.
    """
    lines = output.splitlines()

    failures = [
        line.strip()
        for line in lines
        if ("error:" in line and ".swift" in line)
        or "XCTAssert" in line
        or "XCTUnwrap" in line
        or "failed - " in line
    ]
    counts = [
        line.strip()
        for line in lines
        if line.lstrip().startswith("Executed ") and "failure" in line
    ]
    compile_errors = [
        line.strip()
        for line in lines
        if "error:" in line and ".swift" not in line and "Test Suite" not in line
    ]

    parts: list[str] = []
    if failures:
        parts.append("Assertion failures:")
        parts += [f"  {f}" for f in dict.fromkeys(failures)][:40]
    if compile_errors:
        parts.append("Compile errors:")
        parts += [f"  {e}" for e in dict.fromkeys(compile_errors)][:20]
    if counts:
        parts.append("Totals:")
        parts += [f"  {c}" for c in dict.fromkeys(counts)][-4:]

    if not parts:
        # Nothing matched: fall back to the tail, which at least shows how it
        # ended rather than reporting an empty reason.
        return output[-_MAX_DETAIL:] or "(xcodebuild produced no output)"
    return "\n".join(parts)[-_MAX_DETAIL:]
