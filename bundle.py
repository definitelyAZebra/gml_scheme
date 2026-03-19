"""bundle.py — Concatenate GML Scheme source files.

Usage:
    python gml_scheme/bundle.py [-o OUTPUT_PATH]

Produces a single .gml file (all sources concatenated) plus a stubs file
for pre-registering function symbols.
"""

from __future__ import annotations

import argparse
import re
import shutil
from pathlib import Path

# Ordered by dependency
SRC_ORDER = [
    "scm_types.gml",
    "scm_env.gml",
    "scm_read.gml",
    "scm_print.gml",
    "scm_eval.gml",
    "scm_core.gml",
    "scm_gml_builtins.gml",
    "scm_bridge.gml",
    "scm_init.gml",
    "scm_tty.gml",
    "scm_repl_shell.gml",
]

def _load_prelude_as_gml_string(src_dir: Path) -> str:
    """Read prelude.scm and return it as an escaped GML string literal.

    Splits on newlines and joins with \\n so the result is a plain "..."
    string compatible with UMT's GML parser (no @"..." raw strings).
    Backslashes and double-quotes in the source are escaped.
    """
    text = (src_dir / "prelude.scm").read_text(encoding="utf-8")
    lines = text.splitlines()
    escaped = "\\n".join(
        line.replace("\\", "\\\\").replace('"', '\\"')
        for line in lines
    )
    return f'"{escaped}"'


def _load_scm_as_gml_string(src_dir: Path, filename: str) -> str:
    """Read a .scm file and return it as an escaped GML string literal."""
    text = (src_dir / filename).read_text(encoding="utf-8")
    lines = text.splitlines()
    escaped = "\\n".join(
        line.replace("\\", "\\\\").replace('"', '\\"')
        for line in lines
    )
    return f'"{ escaped}"'


def bundle(src_dir: Path, out_path: Path) -> None:
    prelude_str = _load_prelude_as_gml_string(src_dir)
    repl_str = _load_scm_as_gml_string(src_dir, "scm_repl.scm")

    parts: list[str] = []
    parts.append("/// ═══════════════════════════════════════════════════════════")
    parts.append("/// GML Scheme — Bundled interpreter (auto-generated)")
    parts.append("/// Do not edit — regenerate with: python gml_scheme/bundle.py")
    parts.append("/// ═══════════════════════════════════════════════════════════")
    parts.append("")

    # ── Collect all source texts first (with substitutions) ──────────
    file_texts: dict[str, str] = {}
    for filename in SRC_ORDER:
        filepath = src_dir / filename
        if not filepath.exists():
            print(f"WARNING: {filepath} not found, skipping")
            continue
        text = filepath.read_text(encoding="utf-8")
        if filename == "scm_init.gml":
            text = text.replace('"@@PRELUDE@@"', prelude_str)
        if filename == "scm_repl_shell.gml":
            text = text.replace('"@@REPL@@"', repl_str)
        file_texts[filename] = text

    # ── Emit source sections ─────────────────────────────────────────
    for filename in SRC_ORDER:
        if filename not in file_texts:
            continue
        text = file_texts[filename]
        parts.append(f"// ── {filename} {'─' * (55 - len(filename))}")
        parts.append(text)
        parts.append("")

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text("\n".join(parts), encoding="utf-8")
    print(f"Bundled {len(file_texts)} files → {out_path}")

    # Auto-regenerate stubs after bundling
    stubs_path = out_path.parent / "scm_stubs.gml"
    generate_stubs(out_path, stubs_path)


# Regex to extract top-level function signatures from a bundle/source file.
_FUNC_SIG_RE = re.compile(
    r"^function\s+(\w+)\s*\(([^)]*)\)", re.MULTILINE
)


def generate_stubs(bundle_path: Path, stubs_path: Path) -> None:
    """Generate scm_stubs.gml from the bundled source.

    Extracts every top-level ``function name(params)`` and emits a
    trivial stub ``function name(params) { return 0; }`` so that
    Phase 1 of the installer can pre-register all symbols.
    """
    text = bundle_path.read_text(encoding="utf-8")
    sigs = _FUNC_SIG_RE.findall(text)

    lines = [
        "// Auto-generated stubs for scm_bundle functions",
        "// Purpose: pre-register function names so compiler uses direct call.i",
        "// Do not edit — regenerate with: python gml_scheme/bundle.py",
        "",
    ]
    seen: set[str] = set()
    for name, params in sigs:
        if name in seen:
            continue
        seen.add(name)
        params_str = params.strip()
        lines.append(f"function {name}({params_str}) {{ return 0; }}")

    stubs_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Generated {len(seen)} stubs → {stubs_path}")


def copy_build_assets(project_root: Path, build_dir: Path) -> None:
    """Copy installer script and font to build/ for a self-contained output."""
    assets = [
        project_root / "scripts" / "InstallScmReplStub.csx",
        project_root / "monof55.ttf",
    ]
    for src in assets:
        if src.exists():
            dst = build_dir / src.name
            shutil.copy2(src, dst)
            print(f"Copied {src.name} → {dst}")
        else:
            print(f"WARNING: {src} not found, skipping")


def main() -> None:
    here = Path(__file__).parent
    parser = argparse.ArgumentParser(description="Bundle GML Scheme source files")
    parser.add_argument(
        "-o", "--output",
        default=str(here / "build" / "scm_bundle.gml"),
        help="Output file path (default: gml_scheme/build/scm_bundle.gml)",
    )
    args = parser.parse_args()

    src_dir = here / "src"
    bundle(src_dir, Path(args.output))
    copy_build_assets(here, Path(args.output).parent)


if __name__ == "__main__":
    main()
