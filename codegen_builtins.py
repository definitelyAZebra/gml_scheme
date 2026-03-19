"""codegen_builtins.py — Generate mechanical GML builtin wrappers for Scheme.

Reads a spec table and emits scm_gml_builtins.gml with:
  - One thin wrapper function per GML builtin
  - A scm_register_gml_builtins(_env) registration function

Usage:
    python gml_scheme/codegen_builtins.py

Each spec entry is a tuple:
    (scheme_name, gml_call_expr, arg_types, return_type)

arg_types: list of type tags per positional argument:
           "raw"  — scm_unwrap (no type check)
           "num"  — type-check SCM_NUM, unwrap to .v
           "str"  — type-check SCM_STR, unwrap to .v
           "bool" — type-check SCM_BOOL, unwrap to .v
           None   — raw GML expression (no function call parens).
return_type: "wrap" | "num" | "str" | "bool" | "void"

Special: if gml_call_expr contains "{0}", "{1}", etc., those are
substituted with the unwrapped argument variables.  Otherwise the
arguments are passed positionally as a normal function call.
"""

from __future__ import annotations

from pathlib import Path

# ── Return-type wrappers ─────────────────────────────────────────────
RETURN_WRAPPERS = {
    "wrap": ("return scm_wrap({expr})", True),
    "num":  ("return scm_num({expr})", True),
    "str":  ("return scm_str({expr})", True),
    "bool": ("return scm_bool({expr})", True),
    "void": ("{expr};\n    return scm_void()", True),
}

# ── Type-checked arg unwrap ──────────────────────────────────────────
# Maps arg_type → (scm_type_tag, gml_type_name) for typed args.
TYPE_CHECKS: dict[str, tuple[str, str]] = {
    "num":  ("SCM_NUM",  "number"),
    "str":  ("SCM_STR",  "string"),
    "bool": ("SCM_BOOL", "boolean"),
}

# ── Arg accessor chain ──────────────────────────────────────────────
# For N args we generate: _a0 = _args.car; _a1 = _args.cdr.car; ...
def _arg_accessor(idx: int) -> str:
    if idx == 0:
        return "_args.car"
    # .cdr.cdr. ... .car
    return "_args" + ".cdr" * idx + ".car"

# ── Spec table ───────────────────────────────────────────────────────
# (scheme_name, gml_call_expr, arg_types, return_type)
#
# gml_call_expr patterns:
#   "func_name"              → func_name(_a0, _a1, ...)
#   "expr with {0} and {1}"  → template substitution (for expressions/operators)
#   "_a0[@ _a1]"             → raw template (array subscript, etc.)

BUILTIN_SPEC: list[tuple[str, str, list[str] | None, str]] = [
    # ── Variable access: instance ────────────────────────────────
    ("gml:variable-instance-get",       "variable_instance_get",     ["raw", "raw"], "wrap"),
    ("gml:variable-instance-set",       "variable_instance_set",     ["raw", "raw", "raw"], "void"),
    ("gml:variable-instance-exists",    "variable_instance_exists",  ["raw", "raw"], "bool"),

    # ── Variable access: global ──────────────────────────────────
    ("gml:variable-global-get",         "variable_global_get",       ["raw"], "wrap"),
    ("gml:variable-global-set",         "variable_global_set",       ["raw", "raw"], "void"),
    ("gml:variable-global-exists",      "variable_global_exists",    ["raw"], "bool"),

    # ── Variable access: struct ──────────────────────────────────
    ("gml:variable-struct-get",         "variable_struct_get",       ["raw", "raw"], "wrap"),
    ("gml:variable-struct-set",         "variable_struct_set",       ["raw", "raw", "raw"], "void"),
    ("gml:variable-struct-exists",      "variable_struct_exists",    ["raw", "raw"], "bool"),
    ("gml:variable-struct-get-names",   "variable_struct_get_names", ["raw"], "wrap"),

    # ── ds_map ───────────────────────────────────────────────────
    ("gml:ds-map-find-value",   "ds_map_find_value",    ["raw", "raw"], "wrap"),
    ("gml:ds-map-set",          "ds_map_set",           ["raw", "raw", "raw"], "void"),
    ("gml:ds-map-exists",       "ds_map_exists",        ["raw", "raw"], "bool"),
    ("gml:ds-map-size",         "ds_map_size",          ["raw"], "num"),
    ("gml:ds-map-create",       "ds_map_create",        [], "num"),
    ("gml:ds-map-delete",       "ds_map_delete",        ["raw", "raw"], "void"),
    ("gml:ds-map-destroy",      "ds_map_destroy",       ["raw"], "void"),
    ("gml:ds-map-find-first",   "ds_map_find_first",    ["raw"], "wrap"),
    ("gml:ds-map-find-next",    "ds_map_find_next",     ["raw", "raw"], "wrap"),

    # ── ds_list ──────────────────────────────────────────────────
    ("gml:ds-list-find-value",  "ds_list_find_value",   ["raw", "raw"], "wrap"),
    ("gml:ds-list-set",         "ds_list_set",          ["raw", "raw", "raw"], "void"),
    ("gml:ds-list-size",        "ds_list_size",         ["raw"], "num"),
    ("gml:ds-list-create",      "ds_list_create",       [], "num"),
    ("gml:ds-list-add",         "ds_list_add",          ["raw", "raw"], "void"),
    ("gml:ds-list-delete",      "ds_list_delete",       ["raw", "raw"], "void"),
    ("gml:ds-list-destroy",     "ds_list_destroy",      ["raw"], "void"),

    # ── Instance / object ────────────────────────────────────────
    ("gml:instance-find",       "instance_find",        ["raw", "raw"], "wrap"),
    ("gml:instance-number",     "instance_number",      ["raw"], "num"),
    ("gml:instance-exists",     "instance_exists",      ["raw"], "bool"),
    ("gml:asset-get-index",     "asset_get_index",      ["raw"], "wrap"),

    # ── Array ────────────────────────────────────────────────────
    ("gml:array-length",        "array_length",         ["raw"], "num"),
    ("gml:array-get",           "{0}[{1}]",             ["raw", "raw"], "wrap"),
    ("gml:array-set",           "{0}[@ {1}] = {2}",    ["raw", "raw", "raw"], "void"),
    ("gml:array-push",          "array_push",           ["raw", "raw"], "void"),
    ("gml:array-create",        "array_create",         ["raw"], "wrap"),
    ("gml:array-copy",          "array_copy",           ["raw"], "wrap"),

    # ── String ───────────────────────────────────────────────────
    ("gml:string-length",       "string_length",        ["raw"], "num"),
    ("gml:string-char-at",      "string_char_at",       ["raw", "raw"], "str"),
    ("gml:string-copy",         "string_copy",          ["raw", "raw", "raw"], "str"),
    ("gml:string-pos",          "string_pos",           ["raw", "raw"], "num"),
    ("gml:string-upper",        "string_upper",         ["raw"], "str"),
    ("gml:string-lower",        "string_lower",         ["raw"], "str"),
    ("gml:string-replace-all",  "string_replace_all",   ["raw", "raw", "raw"], "str"),
    ("gml:real",                "real",                 ["raw"], "num"),
    ("gml:string",              "string",               ["raw"], "str"),

    # ── Math ─────────────────────────────────────────────────────
    ("gml:floor",               "floor",                ["num"], "num"),
    ("gml:ceil",                "ceil",                 ["num"], "num"),
    ("gml:round",               "round",                ["num"], "num"),
    ("gml:abs",                 "abs",                  ["num"], "num"),
    ("gml:sign",                "sign",                 ["num"], "num"),
    ("gml:min",                 "min",                  ["num", "num"], "num"),
    ("gml:max",                 "max",                  ["num", "num"], "num"),
    ("gml:clamp",               "clamp",                ["num", "num", "num"], "num"),
    ("gml:sqrt",                "sqrt",                 ["num"], "num"),
    ("gml:power",               "power",                ["num", "num"], "num"),
    ("gml:sin",                 "sin",                  ["num"], "num"),
    ("gml:cos",                 "cos",                  ["num"], "num"),
    ("gml:degtorad",            "degtorad",             ["num"], "num"),
    ("gml:radtodeg",            "radtodeg",             ["num"], "num"),
    ("gml:random-range",        "random_range",         ["num", "num"], "num"),
    ("gml:irandom-range",       "irandom_range",        ["num", "num"], "num"),
    ("gml:random",              "random",               ["num"], "num"),
    ("gml:irandom",             "irandom",              ["num"], "num"),

    # ── Expressions (0-arg, read-only GML state) ─────────────────
    ("gml:current-time",        "current_time",         None, "num"),
    ("gml:self",                "self.id",               None, "num"),
    ("gml:room",                "room",                 None, "num"),
    ("gml:room-get-name",       "room_get_name",        ["raw"], "str"),

    # ── Method binding ────────────────────────────────────────────
    ("gml:method",              "method",               ["raw", "raw"], "wrap"),

    # ── Debug / IO ───────────────────────────────────────────────
    ("gml:show-debug-message",  "show_debug_message",   ["raw"], "void"),

    # ── Keyboard ─────────────────────────────────────────────────
    ("gml:keyboard-string",         "keyboard_string",            None, "str"),
    ("gml:keyboard-string-clear!",  'keyboard_string = ""',       None, "void"),
    ("gml:keyboard-check",          "keyboard_check",             ["num"], "bool"),
    ("gml:keyboard-check-pressed",  "keyboard_check_pressed",     ["num"], "bool"),
    ("gml:keyboard-clear",          "keyboard_clear",             ["num"], "void"),
    ("gml:ord",                     "ord",                        ["str"], "num"),

    # ── Clipboard ────────────────────────────────────────────────
    ("gml:clipboard-has-text?",     "clipboard_has_text",         [], "bool"),
    ("gml:clipboard-get-text",      "clipboard_get_text",         [], "str"),

    # ── Draw ─────────────────────────────────────────────────────
    ("gml:draw-text-color",         "draw_text_color",            ["num", "num", "str", "num", "num", "num", "num", "num"], "void"),
    ("gml:draw-set-font",           "draw_set_font",              ["num"], "void"),
    ("gml:draw-get-font",           "draw_get_font",              [], "num"),
    ("gml:draw-set-alpha",          "draw_set_alpha",             ["num"], "void"),
    ("gml:draw-get-alpha",          "draw_get_alpha",             [], "num"),
    ("gml:draw-set-color",          "draw_set_color",             ["num"], "void"),
    ("gml:draw-get-color",          "draw_get_color",             [], "num"),
    ("gml:draw-rectangle-color",    "draw_rectangle_color",       ["num", "num", "num", "num", "num", "num", "num", "num", "num"], "void"),
    ("gml:make-color-rgb",          "make_color_rgb",             ["num", "num", "num"], "num"),

    # ── String measurement ───────────────────────────────────────
    ("gml:string-width",            "string_width",               ["str"], "num"),
    ("gml:string-height",           "string_height",              ["str"], "num"),

    # ── Display ──────────────────────────────────────────────────
    ("gml:display-get-gui-width",   "display_get_gui_width",      [], "num"),
    ("gml:display-get-gui-height",  "display_get_gui_height",     [], "num"),

    # ── VK constants (expression reads) ──────────────────────────
    ("gml:vk-left",       "vk_left",       None, "num"),
    ("gml:vk-right",      "vk_right",      None, "num"),
    ("gml:vk-up",         "vk_up",         None, "num"),
    ("gml:vk-down",       "vk_down",       None, "num"),
    ("gml:vk-enter",      "vk_enter",      None, "num"),
    ("gml:vk-backspace",  "vk_backspace",  None, "num"),
    ("gml:vk-delete",     "vk_delete",     None, "num"),
    ("gml:vk-home",       "vk_home",       None, "num"),
    ("gml:vk-end",        "vk_end",        None, "num"),
    ("gml:vk-tab",        "vk_tab",        None, "num"),
    ("gml:vk-escape",     "vk_escape",     None, "num"),
    ("gml:vk-shift",      "vk_shift",      None, "num"),
    ("gml:vk-control",    "vk_control",    None, "num"),
    ("gml:vk-f1",         "vk_f1",         None, "num"),
]


def _sanitize_fn_name(scheme_name: str) -> str:
    """Turn 'gml:ds-map-find-value' into 'scm_bi_gml__ds_map_find_value'."""
    base = (scheme_name
            .replace("gml:", "gml__")
            .replace("-", "_")
            .replace("?", "_p")
            .replace("!", "_x"))
    return f"scm_bi_{base}"


def _is_template(gml_expr: str) -> bool:
    return "{0}" in gml_expr


def _generate_function(
    scheme_name: str,
    gml_expr: str,
    arg_types: list[str] | None,
    return_type: str,
) -> str:
    fn_name = _sanitize_fn_name(scheme_name)
    is_expr = arg_types is None
    nargs = 0 if is_expr else len(arg_types)

    lines: list[str] = []
    arg_hint = " ".join(f"a{i}" for i in range(nargs))
    ret_hint = return_type
    lines.append(f"/// ({scheme_name}{(' ' + arg_hint) if arg_hint else ''}) → {ret_hint}")
    lines.append(f"function {fn_name}(_args) {{")

    # Arity validation (prevent crash on nil .car access)
    if nargs > 0:
        arity_checks = []
        for i in range(nargs):
            arity_checks.append("_args" + ".cdr" * i + ".t != SCM_PAIR")
        lines.append(f'    if ({" || ".join(arity_checks)}) return scm_err("{scheme_name}: expected {nargs} argument(s)");')

    # Unwrap arguments (with optional type checks)
    arg_vars: list[str] = []
    for i in range(nargs):
        var = f"_a{i}"
        accessor = _arg_accessor(i)
        atype = arg_types[i] if arg_types else "raw"
        if atype in TYPE_CHECKS:
            tag, tname = TYPE_CHECKS[atype]
            lines.append(f"    if ({accessor}.t != {tag}) return scm_err(\"{scheme_name}: expected {tname}, got \" + scm__type_name({accessor}.t));")
            lines.append(f"    var {var} = {accessor}.v;")
        else:
            lines.append(f"    var {var} = scm_unwrap({accessor});")
        arg_vars.append(var)

    # Build call expression
    if _is_template(gml_expr):
        call_expr = gml_expr.format(*arg_vars)
    elif is_expr:
        call_expr = gml_expr              # raw expression, no parens
    elif nargs == 0:
        call_expr = f"{gml_expr}()"       # 0-arg function call
    else:
        call_expr = f"{gml_expr}({', '.join(arg_vars)})"

    # Wrap return
    ret_template, _ = RETURN_WRAPPERS[return_type]
    ret_line = ret_template.format(expr=call_expr)
    lines.append(f"    {ret_line};")
    lines.append("}")

    return "\n".join(lines)


def _generate_registration(specs: list[tuple[str, str, list[str] | None, str]]) -> str:
    lines: list[str] = []
    lines.append("/// Register all auto-generated GML builtin wrappers.")
    lines.append("function scm_register_gml_builtins(_env) {")
    # Compute alignment width: longest name + 2 (quotes) + 1 (comma)
    col_w = max(len(name) for name, _, _, _ in specs) + 3
    for scheme_name, _, _, _ in specs:
        fn_name = _sanitize_fn_name(scheme_name)
        nc = f'"{scheme_name}",'
        lines.append(
            f'    scm_env_set(_env, {nc:<{col_w}s} scm_fn({nc:<{col_w}s} {fn_name}));'
        )
    lines.append("}")
    return "\n".join(lines)


def generate(specs: list[tuple[str, str, list[str] | None, str]]) -> str:
    parts: list[str] = []
    parts.append("/// scm_gml_builtins.gml — Auto-generated GML builtin wrappers")
    parts.append("/// DO NOT EDIT — regenerate with: python gml_scheme/codegen_builtins.py")
    parts.append(f"/// Generated {len(specs)} wrappers from codegen spec.")
    parts.append("")

    # Group by section (derive from scheme_name prefix after gml:)
    current_section = ""
    for spec in specs:
        scheme_name = spec[0]
        # Extract section from name: gml:ds-map-xxx → ds_map, gml:array-xxx → array
        prefix = scheme_name.replace("gml:", "").split("-")[0]
        if prefix != current_section:
            current_section = prefix
            section_title = prefix.replace("_", " ").title()
            parts.append(f"// ── {section_title} {'─' * (60 - len(section_title))}")
            parts.append("")

        parts.append(_generate_function(*spec))
        parts.append("")

    parts.append("// ── Registration " + "─" * 47)
    parts.append("")
    parts.append(_generate_registration(specs))
    parts.append("")

    return "\n".join(parts)


def main() -> None:
    here = Path(__file__).parent
    out_path = here / "src" / "scm_gml_builtins.gml"

    content = generate(BUILTIN_SPEC)
    out_path.write_text(content, encoding="utf-8")
    print(f"Generated {len(BUILTIN_SPEC)} wrappers → {out_path}")


if __name__ == "__main__":
    main()
