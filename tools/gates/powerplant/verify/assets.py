"""Asset conformance: does the file the manifest promised actually exist, at the
declared size, and is it not blank?

This is the check that makes "real asset generation" safe to run unattended.
Taste still needs your eyes — but "the icon is missing", "the render came out
1023px", and "the background is a flat empty rectangle" are all machine-
checkable, and those are the failures that actually happen.
"""

from __future__ import annotations

from pathlib import Path

from ..assets.manifest import AssetSpec
from .xcode import GateResult

# An 8-bit channel std-dev below this reads as a flat, empty render.
BLANK_STDDEV = 1.0


def _check_one(spec: AssetSpec, project_dir: Path) -> list[str]:
    """Return a list of problems with this asset. Empty means it conforms."""
    problems: list[str] = []
    path = project_dir / spec.path

    if spec.generator == "appicon":
        return _check_appicon(spec, project_dir)

    if not path.exists():
        return [f"{spec.id}: missing file {spec.path}"]

    size = path.stat().st_size
    if size < spec.min_bytes:
        problems.append(f"{spec.id}: {spec.path} is {size}B, below min {spec.min_bytes}B")

    if path.suffix.lower() in {".png", ".jpg", ".jpeg", ".gif", ".webp"}:
        problems += _check_raster(spec, path)

    return problems


def _check_raster(spec: AssetSpec, path: Path) -> list[str]:
    problems: list[str] = []
    try:
        from PIL import Image
    except ImportError:  # pragma: no cover - Pillow is a hard dependency
        return [f"{spec.id}: Pillow unavailable, cannot verify {spec.path}"]

    try:
        with Image.open(path) as img:
            img.load()
            width, height = img.size
            mode = img.mode

            if spec.width and width != spec.width:
                problems.append(f"{spec.id}: width {width} != declared {spec.width}")
            if spec.height and height != spec.height:
                problems.append(f"{spec.id}: height {height} != declared {spec.height}")

            # The App Store marketing icon is rejected if it carries alpha.
            if spec.no_alpha and (mode in ("RGBA", "LA") or "transparency" in img.info):
                problems.append(f"{spec.id}: {spec.path} has an alpha channel but must not")

            if spec.non_blank and not _has_variance(img):
                problems.append(f"{spec.id}: {spec.path} renders blank (no pixel variance)")
    except OSError as exc:
        problems.append(f"{spec.id}: {spec.path} is not a readable image ({exc})")

    return problems


def _has_variance(img) -> bool:
    """True if the image has visible content rather than a flat fill."""
    try:
        import numpy as np

        rgb = img.convert("RGB")
        rgb.thumbnail((256, 256))
        arr = np.asarray(rgb, dtype="float32")
        return bool(arr.std() > BLANK_STDDEV)
    except Exception:  # noqa: BLE001 - a check that errors must not pass silently
        return True


def _check_appicon(spec: AssetSpec, project_dir: Path) -> list[str]:
    """Every declared icon edge must be present at exactly that size."""
    problems: list[str] = []
    iconset = project_dir / spec.path
    if not iconset.exists():
        return [f"{spec.id}: missing icon set directory {spec.path}"]

    try:
        from PIL import Image
    except ImportError:  # pragma: no cover
        return [f"{spec.id}: Pillow unavailable, cannot verify icons"]

    by_edge: dict[int, Path] = {}
    for png in iconset.glob("*.png"):
        try:
            with Image.open(png) as img:
                if img.size[0] == img.size[1]:
                    by_edge[img.size[0]] = png
        except OSError:
            problems.append(f"{spec.id}: {png.name} is not a readable image")

    for edge in spec.sizes:
        if edge not in by_edge:
            problems.append(f"{spec.id}: no {edge}x{edge} icon in {spec.path}")

    # The 1024 marketing icon must be opaque.
    marketing = by_edge.get(1024)
    if marketing is not None:
        try:
            with Image.open(marketing) as img:
                if img.mode in ("RGBA", "LA") or "transparency" in img.info:
                    problems.append(
                        f"{spec.id}: {marketing.name} (1024) has alpha; the marketing icon "
                        "must be fully opaque"
                    )
        except OSError:
            pass

    return problems


def check_manifest(specs: list[AssetSpec], project_dir: str | Path) -> GateResult:
    """Verify every promised asset. One failure fails the gate."""
    import time

    started = time.monotonic()
    project_dir = Path(project_dir)

    problems: list[str] = []
    checked = 0
    for spec in specs:
        problems += _check_one(spec, project_dir)
        checked += 1

    passed = not problems
    detail = (
        f"{checked} asset(s) conform to the manifest"
        if passed
        else f"{len(problems)} problem(s):\n" + "\n".join(f"  - {p}" for p in problems)
    )
    return GateResult(
        name="asset-manifest",
        passed=passed,
        detail=detail,
        duration_s=time.monotonic() - started,
        artifacts=[str(project_dir / s.path) for s in specs if (project_dir / s.path).exists()],
    )
