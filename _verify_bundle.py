"""Quick verification that all scm_bi_* references in the bundle are defined."""
from __future__ import annotations

import re
import sys
from pathlib import Path


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
