"""codegen_help.py — Generate scm_help.gml from help_db.py.

Usage:
    python gml_scheme/codegen_help.py [--locale zh|en]

Outputs gml_scheme/src/scm_help.gml with a function:
    scm_repl__init_help()  →  ds_map id

The ds_map maps function names to formatted help strings.
"""

from __future__ import annotations

import argparse
from pathlib import Path

from help_db import (
    ALIASES,
    BRIDGE,
    CORE_BUILTINS,
    GML_WRAPPERS,
    PRELUDE,
    REPL_STRINGS,
    SPECIAL_FORMS,
    HelpEntry,
    all_entries,
    get_locale_text,
)


def _escape_gml(s: str) -> str:
    """Escape a string for embedding in a GML string literal."""
    return (s
        .replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("\n", "\\n"))


def _format_entry(name: str, entry: HelpEntry, locale: str) -> str:
    """Format a single help entry as a multi-line display string.

    Output format (\\n-joined):
        (sig line)
        description
        example: code     (optional)
    """
    parts = [entry["sig"]]
    desc = get_locale_text(entry, locale)
    if desc:
        parts.append(desc)
    ex = entry.get("example")
    if ex:
        for line in ex.splitlines():
            parts.append("  " + line)
    return "\n".join(parts)


def generate(locale: str = "zh") -> str:
    entries = all_entries()

    lines: list[str] = []
    lines.append("/// scm_help.gml — Auto-generated help database")
    lines.append(f"/// Locale: {locale}  |  Entries: {len(entries)}")
    lines.append("/// DO NOT EDIT — regenerate with: python gml_scheme/codegen_help.py")
    lines.append("")
    lines.append("/// Create and populate the help ds_map.  Returns map id.")
    lines.append("function scm_repl__init_help() {")
    lines.append("    var _h = ds_map_create();")

    # Group entries by category for readability
    categories = [
        ("Special Forms", SPECIAL_FORMS),
        ("Core Builtins", CORE_BUILTINS),
        ("Prelude", PRELUDE),
        ("Bridge", BRIDGE),
        ("GML Wrappers", GML_WRAPPERS),
        ("Aliases", ALIASES),
    ]

    for cat_name, cat in categories:
        lines.append(f"    // ── {cat_name} ({len(cat)})")
        for name, entry in cat.items():
            formatted = _format_entry(name, entry, locale)
            escaped = _escape_gml(formatted)
            lines.append(f'    ds_map_set(_h, "{_escape_gml(name)}", "{escaped}");')

    lines.append("    return _h;")
    lines.append("}")

    # Also emit REPL chrome strings as a lookup function
    lines.append("")
    lines.append("/// Get a REPL UI string by key.")
    lines.append("function scm_repl__str(_key) {")
    lines.append("    switch (_key) {")
    for key, translations in REPL_STRINGS.items():
        text = translations.get(locale, translations.get("en", ""))
        lines.append(f'        case "{key}": return "{_escape_gml(text)}";')
    lines.append(f'        default: return _key;')
    lines.append("    }")
    lines.append("}")

    return "\n".join(lines) + "\n"


def main() -> None:
    here = Path(__file__).parent
    parser = argparse.ArgumentParser(description="Generate scm_help.gml")
    parser.add_argument(
        "--locale", default="zh", choices=["zh", "en"],
        help="Locale for help text (default: zh)",
    )
    args = parser.parse_args()

    content = generate(locale=args.locale)
    out_path = here / "src" / "scm_help.gml"
    out_path.write_text(content, encoding="utf-8")
    print(f"Generated {len(all_entries())} help entries → {out_path} (locale={args.locale})")


if __name__ == "__main__":
    main()
