"""codegen_meta.py — Validate & report asset name lists for runtime loading.

Reads JSON files from gml_scheme/data/meta/ and reports stats.
Word-boundary trie and char bitmasks are now built at GML runtime
(see scm_comp__build_trie / scm_comp__build_masks in scm_comp.gml).

Usage:
    python gml_scheme/codegen_meta.py

Input:  gml_scheme/data/meta/{objects,sprites,sounds,rooms,scripts,functions,globals}.json
        gml_scheme/data/meta/obj_tree.json

JSON data files are copied to build/scm_data/ by bundle.py at build time.
Scheme code (comp-init.scm) loads them at runtime via file->string.
"""

from __future__ import annotations

import json
from pathlib import Path


# ── Namespace config ─────────────────────────────────────────────

# Maps namespace prefix → source JSON filename
_NS_FILES: dict[str, str] = {
    "obj":    "objects.json",
    "spr":    "sprites.json",
    "snd":    "sounds.json",
    "rm":     "rooms.json",
    "scr":    "scripts.json",
    "fn":     "functions.json",
    "global": "globals.json",
}


def generate(meta_dir: Path) -> None:
    """Validate asset name lists and report stats."""

    # Load JSON files (empty arrays if missing)
    def load_json(name: str) -> list[str] | dict:
        p = meta_dir / name
        if p.exists():
            return json.loads(p.read_text(encoding="utf-8"))
        return []

    # Load all namespace arrays
    ns_data: dict[str, list[str]] = {}
    for ns, filename in _NS_FILES.items():
        ns_data[ns] = load_json(filename)  # type: ignore

    has_data = any(ns_data.values())

    # Stats
    counts = {ns: len(names) for ns, names in ns_data.items()}

    status = "with data" if has_data else "STUB (no meta JSON found)"
    print(
        f"codegen_meta {status}:"
        f" {counts['obj']}o {counts['spr']}s"
        f" {counts['snd']}snd {counts['rm']}r"
        f" {counts['scr']}scr {counts['fn']}fn"
        f" {counts['global']}g"
    )


def main() -> None:
    here = Path(__file__).parent
    meta_dir = here / "data" / "meta"
    generate(meta_dir)


if __name__ == "__main__":
    main()
