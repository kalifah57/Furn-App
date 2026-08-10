"""The manifest that sits beside `catalog.json`.

Consumers poll this file — a few hundred bytes — and only pull the catalogue
when `sha256` changes. That makes it load-bearing in a quiet way: a manifest
whose hash does not match the file it describes either pins a consumer to a
stale catalogue forever, or makes it re-download an unchanged one on every
poll. Neither failure raises anything anywhere.

So the manifest is never written by hand. It is derived from the bytes actually
written to disk, in the same call that writes them, and `verify()` re-reads both
files afterwards to confirm they agree.

    {
      "schema_version": 1,
      "record_count": 50,
      "sha256": "83e17aa4…",
      "generated_at": "2026-08-10T14:22:07Z"
    }
"""

from __future__ import annotations

import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from .schema import SCHEMA_VERSION

MANIFEST_SUFFIX = ".manifest.json"


def manifest_path_for(catalogue: Path) -> Path:
    """`catalog.json` -> `catalog.manifest.json`, in the same directory.

    Built by string surgery rather than `with_suffix`, which replaces the last
    dotted segment: a per-retailer name like `catalog.homecentre.json` came back
    as `catalog.manifest.json`, the same path IKEA's manifest already occupies.
    Publishing a second catalogue would have silently overwritten the first
    one's manifest, leaving a hash that describes neither file.
    """
    stem = catalogue.name[:-5] if catalogue.name.endswith(".json") else catalogue.name
    return catalogue.parent / f"{stem}{MANIFEST_SUFFIX}"


def sha256_of(path: Path) -> str:
    """Hash the bytes on disk — not the in-memory object.

    The consumer hashes bytes it downloaded, so anything else (hashing a
    re-serialised copy, say) can disagree over trailing newlines or key order
    and produce a mismatch nobody can explain.
    """
    return hashlib.sha256(path.read_bytes()).hexdigest()


def build(catalogue: Path, *, record_count: int, generated_at: str | None = None) -> dict[str, Any]:
    return {
        "schema_version": SCHEMA_VERSION,
        "record_count": record_count,
        "sha256": sha256_of(catalogue),
        "generated_at": generated_at
        or datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
    }


def write(catalogue: Path, *, record_count: int) -> Path:
    """Write the manifest beside `catalogue` and return its path."""
    target = manifest_path_for(catalogue)
    payload = build(catalogue, record_count=record_count)
    target.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    return target


def verify(catalogue: Path) -> list[str]:
    """Problems found comparing a manifest against the catalogue it describes.

    Empty means the pair is publishable. Run after writing, and in CI, because
    the two files are committed together and a mismatch between them is exactly
    what a consumer cannot detect on its own.
    """
    target = manifest_path_for(catalogue)
    if not catalogue.exists():
        return [f"{catalogue} does not exist"]
    if not target.exists():
        return [f"{target} does not exist"]

    problems: list[str] = []
    try:
        manifest = json.loads(target.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        return [f"{target} is not valid JSON: {exc}"]

    for key in ("schema_version", "record_count", "sha256", "generated_at"):
        if key not in manifest:
            problems.append(f"manifest is missing {key!r}")
    if problems:
        return problems

    actual_hash = sha256_of(catalogue)
    if manifest["sha256"] != actual_hash:
        problems.append(
            f"sha256 mismatch: manifest says {manifest['sha256'][:16]}…, "
            f"{catalogue.name} hashes to {actual_hash[:16]}… "
            "(a consumer polling the manifest would never see the change)"
        )

    try:
        records = json.loads(catalogue.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        problems.append(f"{catalogue} is not valid JSON: {exc}")
        return problems

    if manifest["record_count"] != len(records):
        problems.append(
            f"record_count mismatch: manifest says {manifest['record_count']}, "
            f"file holds {len(records)}"
        )
    if manifest["schema_version"] != SCHEMA_VERSION:
        problems.append(
            f"schema_version is {manifest['schema_version']} but this build emits "
            f"{SCHEMA_VERSION} — regenerate, or bump deliberately"
        )
    return problems


__all__ = ["MANIFEST_SUFFIX", "build", "manifest_path_for", "sha256_of", "verify", "write"]
