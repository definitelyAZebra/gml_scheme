# -*- coding: utf-8 -*-
"""
运行 ExportMeta.csx 导出游戏资源元数据。

用法:
    python gml_scheme/run_export_meta.py                     # 使用 local.json 配置
    python gml_scheme/run_export_meta.py <path_to_data.win>  # 覆盖 data.win 路径

配置:
    gml_scheme/local.json (gitignored, 从 local.json.example 复制):
        {
            "utmt_cli": "C:/path/to/UndertaleModCli.exe",
            "data_win": "C:/path/to/data.win"
        }

    环境变量可覆盖 local.json:
        UTMT_CLI, DATA_WIN

    优先级: 命令行参数 > 环境变量 > local.json

输出:
    gml_scheme/data/meta/{objects,obj_tree,sprites,sounds,rooms,functions}.json
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import time
from pathlib import Path

# ── paths ──────────────────────────────────────────────────────────
GML_SCHEME_DIR = Path(__file__).resolve().parent
EXPORT_META_CSX = GML_SCHEME_DIR / "scripts" / "ExportMeta.csx"
META_OUTPUT_DIR = GML_SCHEME_DIR / "data" / "meta"
LOCAL_CONFIG = GML_SCHEME_DIR / "local.json"

EXPECTED_FILES = [
    "objects.json",
    "obj_tree.json",
    "sprites.json",
    "sounds.json",
    "rooms.json",
    "scripts.json",
    "functions.json",
]


def _load_local_config() -> dict[str, str]:
    """Load local.json if it exists."""
    if LOCAL_CONFIG.exists():
        raw: dict[str, str] = json.loads(LOCAL_CONFIG.read_text(encoding="utf-8"))
        return raw
    return {}


def _resolve_path(key: str, *, cli_arg: str | None = None) -> Path:
    """Resolve a path: cli_arg > $ENV > local.json[key]. Exits on missing."""
    if cli_arg:
        p = Path(cli_arg).resolve()
    elif os.environ.get(key.upper()):
        p = Path(os.environ[key.upper()]).resolve()
    else:
        cfg = _load_local_config()
        val = cfg.get(key)
        if not val:
            print(f"✗ '{key}' not configured.")
            print(f"  Set it in gml_scheme/local.json (copy from local.json.example)")
            print(f"  Or set ${key.upper()} environment variable")
            sys.exit(1)
        p = Path(val)
        if not p.is_absolute():
            p = (GML_SCHEME_DIR / p).resolve()
    if not p.exists():
        print(f"✗ {key} not found: {p}")
        sys.exit(1)
    return p


def _get_cli() -> Path:
    """Resolve CLI path: $UTMT_CLI > local.json."""
    return _resolve_path("utmt_cli")


def _get_data_win() -> Path:
    """Resolve data.win: argv[1] > $DATA_WIN > local.json."""
    cli_arg = sys.argv[1] if len(sys.argv) > 1 else None
    return _resolve_path("data_win", cli_arg=cli_arg)


def _run_export(cli: Path, data_win: Path) -> None:
    """Execute ExportMeta.csx via UTMT CLI."""
    args = [str(cli), "load", str(data_win), "-s", str(EXPORT_META_CSX)]
    print(f"CMD: {' '.join(args)}")
    print()

    t0 = time.perf_counter()
    result = subprocess.run(args, capture_output=False, text=True)
    elapsed = time.perf_counter() - t0

    if result.returncode != 0:
        print(f"\n✗ ExportMeta FAILED (exit code {result.returncode}, {elapsed:.1f}s)")
        sys.exit(result.returncode)
    print(f"\n✓ ExportMeta completed in {elapsed:.1f}s")


def _verify_output() -> None:
    """Check that all expected JSON files were created and non-empty."""
    ok = True
    for name in EXPECTED_FILES:
        p = META_OUTPUT_DIR / name
        if not p.exists():
            print(f"  ✗ missing: {p.relative_to(GML_SCHEME_DIR)}")
            ok = False
            continue
        data = json.loads(p.read_text(encoding="utf-8"))
        count = len(data) if isinstance(data, (list, dict)) else 0
        print(f"  ✓ {name}: {count} entries")
    if not ok:
        print("\n✗ Some files missing!")
        sys.exit(1)
    print("\nAll meta files OK.")


def main() -> None:
    cli = _get_cli()
    data_win = _get_data_win()
    print(f"CLI:      {cli}")
    print(f"data.win: {data_win}")
    print(f"output:   {META_OUTPUT_DIR}")
    print()

    _run_export(cli, data_win)
    print()
    _verify_output()


if __name__ == "__main__":
    main()
