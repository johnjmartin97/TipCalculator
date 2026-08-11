"""The asset manifest — the contract between art direction and art production.

Direct declares what must exist. Assets produces it. `verify.assets` confirms
it. Because every entry carries target dimensions and a named generator, an
asset is either right or it isn't — which is the property "is this image good?"
can never have.
"""

from __future__ import annotations

import json
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any

# Generators are the ways an asset can be produced. Each maps to a real local
# renderer in `assets.render`; `imagegen` is the seam for a future diffusion
# backend and is not wired up.
GENERATORS = {"svg", "pil", "blender", "appicon", "swift", "audio", "imagegen"}


class ManifestError(ValueError):
    """Raised when a manifest is malformed. Halts the run before any UI depends on it."""


@dataclass
class AssetSpec:
    """One file the run promises to produce."""

    id: str
    path: str                  # relative to the project dir
    generator: str
    purpose: str = ""
    source: str = ""           # the SVG / script that generates it
    width: int | None = None
    height: int | None = None
    no_alpha: bool = False     # true for the marketing app icon
    min_bytes: int = 1
    non_blank: bool = True     # reject a flat, empty render
    sizes: list[int] = field(default_factory=list)  # appicon: every required edge

    def as_dict(self) -> dict:
        return asdict(self)


def _require(entry: dict, key: str, index: int) -> Any:
    if key not in entry or entry[key] in (None, ""):
        raise ManifestError(f"asset[{index}] is missing required field {key!r}")
    return entry[key]


def parse(data: Any) -> list[AssetSpec]:
    """Validate raw manifest data into specs, or raise.

    Accepts either a bare list or an object with an `assets` key, because a
    model asked for JSON will produce both.
    """
    if isinstance(data, str):
        try:
            data = json.loads(data)
        except json.JSONDecodeError as exc:
            raise ManifestError(f"manifest is not valid JSON: {exc}") from exc
    if isinstance(data, dict):
        data = data.get("assets", data.get("manifest"))
    if not isinstance(data, list):
        raise ManifestError("manifest must be a list of assets")
    if not data:
        raise ManifestError("manifest is empty — art direction promised nothing")

    specs: list[AssetSpec] = []
    seen_ids: set[str] = set()
    seen_paths: set[str] = set()

    for i, entry in enumerate(data):
        if not isinstance(entry, dict):
            raise ManifestError(f"asset[{i}] is not an object")

        asset_id = str(_require(entry, "id", i))
        path = str(_require(entry, "path", i))
        generator = str(_require(entry, "generator", i))

        if generator not in GENERATORS:
            raise ManifestError(
                f"asset[{i}] {asset_id!r}: unknown generator {generator!r} "
                f"(known: {', '.join(sorted(GENERATORS))})"
            )
        if asset_id in seen_ids:
            raise ManifestError(f"asset[{i}]: duplicate id {asset_id!r}")
        if path in seen_paths:
            raise ManifestError(f"asset[{i}]: duplicate path {path!r}")
        if Path(path).is_absolute() or ".." in Path(path).parts:
            raise ManifestError(f"asset[{i}] {asset_id!r}: path must be inside the project")

        spec = AssetSpec(
            id=asset_id,
            path=path,
            generator=generator,
            purpose=str(entry.get("purpose", "")),
            source=str(entry.get("source", "")),
            width=_opt_int(entry.get("width"), i, "width"),
            height=_opt_int(entry.get("height"), i, "height"),
            no_alpha=bool(entry.get("no_alpha", False)),
            min_bytes=int(entry.get("min_bytes", 1)),
            non_blank=bool(entry.get("non_blank", True)),
            sizes=[int(s) for s in entry.get("sizes", []) or []],
        )

        # A raster asset with no declared dimensions cannot be verified, which
        # defeats the purpose of the manifest.
        if spec.generator in {"svg", "pil", "blender"} and not (spec.width and spec.height):
            raise ManifestError(
                f"asset[{i}] {asset_id!r}: generator {spec.generator!r} needs width and height "
                "so the render can be checked"
            )
        if spec.generator == "appicon" and not spec.sizes:
            raise ManifestError(f"asset[{i}] {asset_id!r}: appicon needs a non-empty `sizes` list")

        specs.append(spec)
        seen_ids.add(asset_id)
        seen_paths.add(path)

    return specs


def _opt_int(value: Any, index: int, field_name: str) -> int | None:
    if value in (None, ""):
        return None
    try:
        parsed = int(value)
    except (TypeError, ValueError) as exc:
        raise ManifestError(f"asset[{index}]: {field_name} must be an integer") from exc
    if parsed <= 0:
        raise ManifestError(f"asset[{index}]: {field_name} must be positive")
    return parsed


def load(path: str | Path) -> list[AssetSpec]:
    p = Path(path)
    if not p.exists():
        raise ManifestError(f"manifest not found at {p}")
    return parse(p.read_text(encoding="utf-8"))


def dump(specs: list[AssetSpec], path: str | Path) -> Path:
    p = Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps([s.as_dict() for s in specs], indent=2), encoding="utf-8")
    return p
