"""Analyze scm_bundle bytecode for cross-reference patterns."""
import re
from pathlib import Path

BUNDLE_BC = Path(__file__).parent / "src" / "scm_bundle"


def main():
    content = BUNDLE_BC.read_text(encoding="utf-8")

    # Pattern: call.i @@This@@ + push.v builtin.scm_xxx + callv.v N
    pattern = r"call\.i @@This@@\(argc=0\)\npush\.v builtin\.(scm_\w+)\ncallv\.v (\d+)"
    matches = re.findall(pattern, content)
    print(f"Total cross-ref call sites: {len(matches)}")

    funcs: dict[str, set[str]] = {}
    for name, argc in matches:
        funcs.setdefault(name, set()).add(argc)

    print(f"Unique functions called via builtin: {len(funcs)}")
    for name in sorted(funcs):
        argcs = sorted(funcs[name])
        print(f"  {name} argc={{{','.join(argcs)}}}")

    # Also check for non-scm builtin refs
    all_builtin = re.findall(r"push\.v builtin\.(\w+)", content)
    non_scm = [b for b in all_builtin if not b.startswith("scm_")]
    if non_scm:
        print(f"\nNon-scm builtin refs: {set(non_scm)}")
    else:
        print("\nNo non-scm builtin refs (all are scm_*)")

    # Check: any callv.v NOT preceded by the @@This@@+builtin pattern?
    all_callv = list(re.finditer(r"callv\.v \d+", content))
    pattern_callv = list(re.finditer(pattern, content))
    pattern_positions = {m.end() for m in pattern_callv}
    orphan_callv = [m for m in all_callv if m.end() not in pattern_positions]
    print(f"\nTotal callv.v: {len(all_callv)}, matched by pattern: {len(pattern_callv)}, orphan: {len(orphan_callv)}")
    for m in orphan_callv[:5]:
        start = max(0, m.start() - 400)
        context = content[start : m.end() + 50]
        print(f"--- Orphan callv at offset {m.start()} ---")
        print(context)
        print()


if __name__ == "__main__":
    main()
