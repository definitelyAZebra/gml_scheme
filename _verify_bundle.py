"""Quick verification that all scm_bi_* references in the bundle are defined.

Also provides lint_sources() to catch GML syntax forbidden in UMT bytecode 17.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

# ── UMT bytecode 17 forbidden patterns ──────────────────────────
# These GML syntaxes are NOT supported by UMT's bytecode 17 compiler.
# Using them causes hard-to-debug runtime errors (e.g. "unable to
# convert string to int64" when [$] is misinterpreted as array access).
#
# Replacements:
#   struct[$ key]            → variable_struct_get(struct, key)
#   struct[$ key] = val      → variable_struct_set(struct, key, val)
#   map[? key]               → ds_map_find_value(map, key)
#   map[? key] = val         → ds_map_set(map, key, val)
#   arr[@ i]                 → array_get(arr, i) (reads work with [])
#   arr[@ i] = val           → array_set(arr, i, val)
#   struct_set(s, k, v)      → variable_struct_set(s, k, v)
#   is_instanceof(x, T)      → NOT available, use manual type checks
_FORBIDDEN_PATTERNS: list[tuple[re.Pattern[str], str]] = [
    (re.compile(r'\[\$\s'),
     "[$] struct accessor — use variable_struct_get() / variable_struct_set()"),
    (re.compile(r'\[\?\s'),
     "[?] ds_map accessor — use ds_map_find_value() / ds_map_set()"),
    (re.compile(r'\[@\s'),
     "[@] array accessor — use array_get() / array_set()"),
    (re.compile(r'\bstruct_set\s*\('),
     "struct_set() (GML 2024.6+) — use variable_struct_set()"),
    (re.compile(r'\bis_instanceof\s*\('),
     "is_instanceof() — not available in bytecode 17"),
]


def lint_sources(project_root: Path) -> bool:
    """Scan .gml sources for syntax forbidden in UMT bytecode 17.

    Returns True if no violations found.
    """
    src_dir = project_root / "src"
    violations: list[str] = []

    for gml_path in sorted(src_dir.glob("*.gml")):
        lines = gml_path.read_text(encoding="utf-8").splitlines()
        for lineno, line in enumerate(lines, 1):
            # Skip comments
            stripped = line.lstrip()
            if stripped.startswith("//"):
                continue
            for pattern, msg in _FORBIDDEN_PATTERNS:
                if pattern.search(line):
                    violations.append(
                        f"  {gml_path.name}:{lineno}: {msg}\n"
                        f"    > {line.rstrip()}"
                    )

    if violations:
        print(f"\n!! LINT FAILED — {len(violations)} forbidden pattern(s) found:")
        print("   (UMT bytecode 17 does not support these GML features)\n")
        for v in violations:
            print(v)
        print()
        return False

    print("Lint: no forbidden patterns found.")
    return True


def verify(project_root: Path) -> bool:
    """Verify bundle integrity. Returns True if all checks pass."""
    bundle_path = project_root / "build" / "scm_bundle.gml"
    prelude_path = project_root / "src" / "prelude.scm"

    b = bundle_path.read_text(encoding="utf-8")
    ok = True

    # ── scm_bi_* definitions vs references ───────────────────────
    defs = set(re.findall(r"function (scm_bi_\w+)", b))
    refs = set(re.findall(r"scm_fn\([^,]+,\s*(scm_bi_\w+)\)", b))
    print(f"Defined: {len(defs)}, Referenced: {len(refs)}")

    missing = refs - defs
    if missing:
        print("MISSING:", sorted(missing))
        ok = False
    else:
        print("All references resolved!")

    orphans = defs - refs
    if orphans:
        print("Orphan defs (not registered):", sorted(orphans))

    # ── scm_register_* consistency ───────────────────────────────
    reg_defs = set(re.findall(r"function (scm_register_\w+)", b))
    print(f"\nRegister functions defined: {sorted(reg_defs)}")
    reg_calls = re.findall(r"(scm_register_\w+)\(global", b)
    print(f"Register calls in scm_init: {sorted(reg_calls)}")

    # ── Prelude alias resolution ─────────────────────────────────
    names = set(re.findall(r'scm_env_set\(_env,\s*"([^"]+)"', b))
    prelude = prelude_path.read_text(encoding="utf-8")
    aliases = re.findall(r"\(define\s+\S+\s+(gml:[a-z:-]+)", prelude)
    gml_names = [n for n in names if n.startswith("gml:")]
    print(f"\nPrelude gml: aliases: {len(aliases)}, registered gml: names: {len(gml_names)}")
    alias_missing = [a for a in aliases if a not in names]
    if alias_missing:
        print("MISSING prelude aliases:", alias_missing)
        ok = False
    else:
        print("All prelude aliases resolve!")

    return ok


if __name__ == "__main__":
    # Support both: `python _verify_bundle.py` (from gml_scheme/)
    # and `python gml_scheme/_verify_bundle.py` (from workspace root)
    here = Path(__file__).resolve().parent
    if not verify(here):
        sys.exit(1)
