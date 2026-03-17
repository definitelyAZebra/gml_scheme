"""bundle.py — Concatenate all GML source files into a single script.

Usage:
    python gml_scheme/bundle.py [-o OUTPUT_PATH]

Produces a single .gml file that can be injected as one code entry.
"""

import argparse
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


def bundle(src_dir: Path, out_path: Path) -> None:
    prelude_str = _load_prelude_as_gml_string(src_dir)

    parts: list[str] = []
    parts.append("/// ═══════════════════════════════════════════════════════════")
    parts.append("/// GML Scheme — Bundled interpreter (auto-generated)")
    parts.append("/// Do not edit — regenerate with: python gml_scheme/bundle.py")
    parts.append("/// ═══════════════════════════════════════════════════════════")
    parts.append("")

    for filename in SRC_ORDER:
        filepath = src_dir / filename
        if not filepath.exists():
            print(f"WARNING: {filepath} not found, skipping")
            continue
        text = filepath.read_text(encoding="utf-8")
        if filename == "scm_init.gml":
            text = text.replace('"@@PRELUDE@@"', prelude_str)
        parts.append(f"// ── {filename} {'─' * (55 - len(filename))}")
        parts.append(text)
        parts.append("")

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text("\n".join(parts), encoding="utf-8")
    print(f"Bundled {len(SRC_ORDER)} files → {out_path}")


def main() -> None:
    here = Path(__file__).parent
    parser = argparse.ArgumentParser(description="Bundle GML Scheme source files")
    parser.add_argument(
        "-o", "--output",
        default=str(here / "build" / "scm_bundle.gml"),
        help="Output file path (default: gml_scheme/build/scm_bundle.gml)",
    )
    args = parser.parse_args()

    bundle(here / "src", Path(args.output))


if __name__ == "__main__":
    main()
