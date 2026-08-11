"""What a project declares about how it is checked.

The factory used to know, in Python, that a project was iOS and was checked by
`xcodebuild`. That made every new kind of work a change to PowerPlant itself —
a template, a verifier module, and a branch in intake. It also meant the thing
best placed to decide the toolchain, the agent that just researched the stack,
was not allowed to.

So the project declares it instead, in `.powerplant.json`:

    {
      "work_type": "web",
      "gates": [
        {"name": "typecheck", "run": "npx tsc --noEmit",
         "canary": {"path": "src/__canary__.ts",
                    "content": "const n: number = 'no';"}},
        {"name": "test", "run": "npx vitest run",
         "canary": {"path": "src/__canary__.test.ts",
                    "content": "..."}}
      ],
      "test_globs": ["**/*.test.ts"],
      "frozen": ["package.json", "tsconfig.json", ".github/workflows/**"]
    }

The agent chooses the toolchain. It does **not** get to decide what passing
means, because a declaration is only a claim until something checks it. Each
gate carries a canary — a change that must make it fail — and the meta-gate in
`suite.py` proves every declared gate actually goes red when it should. A gate
that stays green on deliberately broken code is not a gate, and `"run": "true"`
is caught by construction rather than by reading the JSON hopefully.

This file only parses and validates. Nothing here runs anything.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

DESCRIPTOR = ".powerplant.json"

# The descriptor defines the oracle, so it is itself part of the oracle. If an
# agent could edit this it could rewrite what "passing" means mid-ticket, which
# is the same failure as editing a test — one level up. Always frozen, never
# by declaration, because a file that declares its own immutability is not
# immutable.
ALWAYS_FROZEN = (DESCRIPTOR, ".github/workflows/**")

# Gates that decide whether the code is *correct* have to be proven. A build
# gate is largely self-proving — it either produces output or it does not — but
# a test gate that never fails is indistinguishable from no tests at all.
MUST_BE_PROVEN = ("test",)


class DescriptorError(ValueError):
    """Raised when a project's declaration is malformed or unprovable."""


@dataclass(frozen=True)
class Canary:
    """A change that must make its gate fail.

    Written into the tree, the gate is run, and the file is removed again. The
    gate is only trusted if it went red while the canary was present.
    """

    path: str
    content: str


@dataclass(frozen=True)
class GateSpec:
    name: str
    run: str
    canary: Canary | None = None

    @property
    def provable(self) -> bool:
        return self.canary is not None


@dataclass
class Descriptor:
    """Everything the gate suite needs, taken from the project rather than code."""

    work_type: str
    gates: list[GateSpec] = field(default_factory=list)
    test_globs: tuple[str, ...] = ()
    frozen: tuple[str, ...] = ()
    # iOS keeps its built-in suite; these stay for that path.
    scheme: str = ""
    bundle_id: str = ""
    raw: dict = field(default_factory=dict)

    @property
    def declares_gates(self) -> bool:
        """True when the project brings its own gates rather than using the
        built-in Xcode suite."""
        return bool(self.gates)

    def frozen_patterns(self) -> tuple[str, ...]:
        return tuple(dict.fromkeys((*self.frozen, *ALWAYS_FROZEN)))


def _canary(data: Any, gate_name: str) -> Canary | None:
    if data in (None, {}):
        return None
    if not isinstance(data, dict):
        raise DescriptorError(f"gate {gate_name!r}: canary must be an object")
    path = str(data.get("path", "")).strip()
    content = data.get("content", "")
    if not path:
        raise DescriptorError(f"gate {gate_name!r}: canary needs a path")
    if Path(path).is_absolute() or ".." in Path(path).parts:
        raise DescriptorError(f"gate {gate_name!r}: canary path must be inside the project")
    if not str(content).strip():
        raise DescriptorError(
            f"gate {gate_name!r}: canary needs content that actually breaks the gate"
        )
    return Canary(path=path, content=str(content))


def parse(data: dict) -> Descriptor:
    """Validate a descriptor, or raise."""
    if not isinstance(data, dict):
        raise DescriptorError("descriptor must be a JSON object")

    work_type = str(data.get("work_type") or "ios").strip()

    raw_gates = data.get("gates") or []
    if not isinstance(raw_gates, list):
        raise DescriptorError("`gates` must be a list")

    gates: list[GateSpec] = []
    seen: set[str] = set()
    for i, entry in enumerate(raw_gates):
        if not isinstance(entry, dict):
            raise DescriptorError(f"gates[{i}] is not an object")
        name = str(entry.get("name", "")).strip()
        command = str(entry.get("run", "")).strip()
        if not name:
            raise DescriptorError(f"gates[{i}] has no name")
        if not command:
            raise DescriptorError(f"gate {name!r} declares no command to run")
        if name in seen:
            raise DescriptorError(f"duplicate gate name {name!r}")
        seen.add(name)
        gates.append(GateSpec(name=name, run=command, canary=_canary(entry.get("canary"), name)))

    if gates:
        # A project that brings its own gates has to bring proof they work.
        unprovable = [g.name for g in gates if g.name in MUST_BE_PROVEN and not g.provable]
        if unprovable:
            raise DescriptorError(
                f"gate(s) {', '.join(unprovable)} must declare a canary. "
                "A test gate that is never shown to fail cannot be told apart "
                "from one that runs no tests."
            )
        if not any(g.provable for g in gates):
            raise DescriptorError(
                "no gate declares a canary, so nothing here has been shown to "
                "detect a fault. At least one gate must be provable."
            )

    return Descriptor(
        work_type=work_type,
        gates=gates,
        test_globs=tuple(str(g) for g in data.get("test_globs") or ()),
        frozen=tuple(str(f) for f in data.get("frozen") or ()),
        scheme=str(data.get("scheme", "")),
        bundle_id=str(data.get("bundle_id", "")),
        raw=data,
    )


def load(project_dir: str | Path) -> Descriptor:
    path = Path(project_dir) / DESCRIPTOR
    if not path.exists():
        raise FileNotFoundError(
            f"{path} not found — the gate suite cannot know how this project is "
            "checked. It is written by the setup stage."
        )
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise DescriptorError(f"{path} is not valid JSON: {exc}") from exc
    return parse(data)


def write(project_dir: str | Path, data: dict) -> Path:
    """Validate then write. Never writes something that would not load."""
    parse(data)
    path = Path(project_dir) / DESCRIPTOR
    path.write_text(json.dumps(data, indent=2, sort_keys=True), encoding="utf-8")
    return path
