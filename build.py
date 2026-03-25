"""build.py — GML Scheme build orchestrator.

Usage:
    python gml_scheme/build.py              # full rebuild (codegen → bundle → verify)
    python gml_scheme/build.py --quick      # bundle + verify only (skip codegen)
    python gml_scheme/build.py --export     # export meta from game, then full rebuild
    python gml_scheme/build.py --no-verify  # skip verification step

Pipeline:
    1. [--export only] run_export_meta  → data/meta/*.json
    2. codegen_builtins                → src/scm_gml_builtins.gml
    3. codegen_meta                    → validates data/meta/*.json (trie/masks built at GML runtime)
    4. codegen_help                    → src/scm_help.gml
    5. bundle                          → build/scm_bundle.gml + stubs + assets
    6. verify                          → check all refs resolve
"""

from __future__ import annotations

import argparse
import shutil
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent


def _step(name: str) -> float:
    """Print step header and return start time."""
    print(f"\n{'─' * 60}")
    print(f"  {name}")
    print(f"{'─' * 60}")
    return time.perf_counter()


def _done(t0: float) -> None:
    elapsed = time.perf_counter() - t0
    print(f"  ({elapsed:.2f}s)")


def step_export_meta() -> bool:
    t0 = _step("Export Meta (run_export_meta.py)")
    import run_export_meta
    try:
        run_export_meta.main()
    except SystemExit as e:
        if e.code:
            print(f"  Export meta failed (exit {e.code})")
            return False
    _done(t0)
    return True


def step_codegen_builtins() -> bool:
    t0 = _step("Codegen Builtins (codegen_builtins.py)")
    import codegen_builtins
    codegen_builtins.main()
    _done(t0)
    return True


def step_codegen_meta() -> bool:
    t0 = _step("Codegen Meta (codegen_meta.py)")
    import codegen_meta
    codegen_meta.main()
    _done(t0)
    return True


def step_codegen_help(locale: str = "zh") -> bool:
    t0 = _step(f"Codegen Help (codegen_help.py, locale={locale})")
    import codegen_help
    content = codegen_help.generate(locale=locale)
    out_path = HERE / "src" / "scm_help.gml"
    out_path.write_text(content, encoding="utf-8")
    from help_db import all_entries
    print(f"Generated {len(all_entries())} help entries → {out_path} (locale={locale})")
    _done(t0)
    return True


def step_lint() -> bool:
    t0 = _step("Lint (UMT bytecode 17 compatibility)")
    import _verify_bundle
    ok = _verify_bundle.lint_sources(HERE)
    _done(t0)
    return ok


def step_bundle() -> bool:
    t0 = _step("Bundle (bundle.py)")
    import bundle
    build_dir = HERE / "build"
    # Clean build directory to remove stale artifacts
    if build_dir.exists():
        shutil.rmtree(build_dir)
    src_dir = HERE / "src"
    out_path = build_dir / "scm_bundle.gml"
    bundle.bundle(src_dir, out_path)
    bundle.copy_build_assets(HERE, out_path.parent)
    _done(t0)
    return True


def step_verify() -> bool:
    t0 = _step("Verify (_verify_bundle.py)")
    import _verify_bundle
    ok = _verify_bundle.verify(HERE)
    _done(t0)
    return ok


def main() -> None:
    parser = argparse.ArgumentParser(description="GML Scheme build orchestrator")
    parser.add_argument("--quick", action="store_true",
                        help="Skip codegen, only bundle + verify")
    parser.add_argument("--export", action="store_true",
                        help="Run ExportMeta.csx before codegen (needs UTMT CLI)")
    parser.add_argument("--no-verify", action="store_true",
                        help="Skip verification step")
    parser.add_argument("--locale", default="zh", choices=["zh", "en"],
                        help="Help text locale (default: zh)")
    args = parser.parse_args()

    t_total = time.perf_counter()
    steps: list[tuple[str, bool]] = []

    if args.export:
        ok = step_export_meta()
        steps.append(("export_meta", ok))
        if not ok:
            _print_summary(steps, t_total)
            sys.exit(1)

    if not args.quick:
        ok = step_codegen_builtins()
        steps.append(("codegen_builtins", ok))

        ok = step_codegen_meta()
        steps.append(("codegen_meta", ok))

        ok = step_codegen_help(locale=args.locale)
        steps.append(("codegen_help", ok))

    ok = step_lint()
    steps.append(("lint", ok))
    if not ok:
        _print_summary(steps, t_total)
        sys.exit(1)

    ok = step_bundle()
    steps.append(("bundle", ok))

    if not args.no_verify:
        ok = step_verify()
        steps.append(("verify", ok))

    _print_summary(steps, t_total)

    if not all(ok for _, ok in steps):
        sys.exit(1)


def _print_summary(steps: list[tuple[str, bool]], t_total: float) -> None:
    elapsed = time.perf_counter() - t_total
    print(f"\n{'═' * 60}")
    for name, ok in steps:
        status = "✓" if ok else "✗"
        print(f"  {status} {name}")
    print(f"{'═' * 60}")
    failed = [n for n, ok in steps if not ok]
    if failed:
        print(f"  FAILED: {', '.join(failed)}  ({elapsed:.2f}s total)")
    else:
        print(f"  All steps passed  ({elapsed:.2f}s total)")


if __name__ == "__main__":
    main()
