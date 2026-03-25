/// scm_print.gml — Scheme value printer
///
/// Converts Scheme values to GML strings for display/debug.

/// Convert a Scheme value to its display string (human-readable).
/// Strings are NOT quoted.
function scm_display_str(_v) {
    switch (_v.t) {
        case SCM_NIL:    return "()";
        case SCM_BOOL:   return _v.v ? "#t" : "#f";
        case SCM_NUM:
            // Display integers without decimal point
            if (_v.v == floor(_v.v) && abs(_v.v) < 1000000000000000) {
                return string(int64(_v.v));
            }
            return string(_v.v);
        case SCM_STR:    return _v.v;
        case SCM_SYM:    return _v.v;
        case SCM_PAIR:   return scm__print_list(_v, false);
        case SCM_FN:     return "#<procedure:" + _v.name + ">";
        case SCM_LAMBDA: return "#<procedure:" + _v.name + ">";
        case SCM_CASE_LAMBDA: return "#<procedure:" + _v.name + ">";
        case SCM_PORT:
            var _pdir = (_v.dir == SCM_PORT_IN) ? "input" : "output";
            var _pkind = "";
            switch (_v.kind) {
                case SCM_PORT_STRING:  _pkind = "string";  break;
                case SCM_PORT_FILE:    _pkind = "file";    break;
                case SCM_PORT_CONSOLE: _pkind = "console"; break;
                case SCM_PORT_DEBUG:   _pkind = "debug";   break;
            }
            return "#<" + _pdir + "-" + _pkind + "-port>";
        case SCM_EOF:    return "#<eof>";
        case SCM_VOID:   return "#<void>";
        case SCM_ERR:    return "#<error: " + _v.v + ">";
        case SCM_HANDLE:
            switch (_v.ht) {
                case SCM_HT_ARRAY:    return scm__print_array(_v.v, false);
                case SCM_HT_STRUCT:   return scm__print_struct(_v.v, false);
                case SCM_HT_METHOD:   return "#<method>";
                default:              return "#<handle:" + string(_v.v) + ">";
            }
        default:         return "#<unknown>";
    }
}

/// Convert a Scheme value to its write string (machine-readable).
/// Strings are quoted with escapes.
function scm_write_str(_v) {
    if (_v.t == SCM_STR) {
        var _raw = _v.v;
        var _len = string_length(_raw);
        // Fast path: scan for chars needing escape
        var _needs_escape = false;
        for (var _i = 1; _i <= _len; _i++) {
            var _ch = string_char_at(_raw, _i);
            if (_ch == "\"" || _ch == "\\" || _ch == "\n" || _ch == "\t") {
                _needs_escape = true;
                break;
            }
        }
        if (!_needs_escape) return "\"" + _raw + "\"";

        // Slow path: build with array buffer
        var _buf = ["\""];
        for (var _i = 1; _i <= _len; _i++) {
            var _ch = string_char_at(_raw, _i);
            if (_ch == "\"")      array_push(_buf, "\\\"");
            else if (_ch == "\\") array_push(_buf, "\\\\");
            else if (_ch == "\n") array_push(_buf, "\\n");
            else if (_ch == "\t") array_push(_buf, "\\t");
            else                  array_push(_buf, _ch);
        }
        array_push(_buf, "\"");
        var _s = "";
        for (var _j = 0; _j < array_length(_buf); _j++) _s += _buf[_j];
        return _s;
    }
    if (_v.t == SCM_PAIR) return scm__print_list(_v, true);
    return scm_display_str(_v);
}

/// Alias for scm_write_str — the default "to string" conversion.
function scm_to_string(_v) {
    return scm_write_str(_v);
}

// ── Helpers ─────────────────────────────────────────────────────────

/// Dispatch to the correct print mode for a sub-value.
/// _mode: false/0 = display, true/1 = write, 2 = inspect
function scm__print_val(_v, _mode) {
    if (_mode == 2) return scm_inspect_str(_v);
    if (_mode)      return scm_write_str(_v);
    return scm_display_str(_v);
}

/// Print a list/dotted-pair. Uses array buffer to avoid O(n²) concat.
function scm__print_list(_v, _write_mode) {
    var _buf = ["("];
    var _first = true;
    var _p = _v;

    while (_p.t == SCM_PAIR) {
        if (!_first) array_push(_buf, " ");
        _first = false;
        array_push(_buf, scm__print_val(_p.car, _write_mode));
        _p = _p.cdr;
    }

    // Improper list (dotted pair)
    if (_p.t != SCM_NIL) {
        array_push(_buf, " . ");
        array_push(_buf, scm__print_val(_p, _write_mode));
    }

    array_push(_buf, ")");
    var _s = "";
    for (var _i = 0; _i < array_length(_buf); _i++) _s += _buf[_i];
    return _s;
}

/// Print a GML array as #[elem1 elem2 ...].
/// Elements are wrapped via scm_wrap before printing.
/// Truncates after 20 elements.
function scm__print_array(_arr, _write_mode) {
    var _len = array_length(_arr);
    var _max = 20;
    var _buf = ["#["];
    var _limit = min(_len, _max);
    for (var _i = 0; _i < _limit; _i++) {
        if (_i > 0) array_push(_buf, " ");
        var _elem = scm_wrap(_arr[_i]);
        array_push(_buf, scm__print_val(_elem, _write_mode));
    }
    if (_len > _max) {
        array_push(_buf, " ..." + string(_len - _max) + " more");
    }
    array_push(_buf, "]");
    var _s = "";
    for (var _j = 0; _j < array_length(_buf); _j++) _s += _buf[_j];
    return _s;
}

/// Print a GML struct as #{key1 val1 key2 val2 ...}.
/// Values are wrapped via scm_wrap before printing.
/// Truncates after 10 fields.
function scm__print_struct(_st, _write_mode) {
    var _names = variable_struct_get_names(_st);
    var _len = array_length(_names);
    var _max = 10;
    var _buf = ["#{"];
    var _limit = min(_len, _max);
    for (var _i = 0; _i < _limit; _i++) {
        var _k = _names[_i];
        var _raw = variable_struct_get(_st, _k);
        var _val = scm__is_tagged(_raw) ? _raw : scm_wrap(_raw);
        array_push(_buf, " " + _k + " ");
        array_push(_buf, scm__print_val(_val, _write_mode));
    }
    if (_len > _max) {
        array_push(_buf, " ..." + string(_len - _max) + " more");
    }
    array_push(_buf, "}");
    var _s = "";
    for (var _j = 0; _j < array_length(_buf); _j++) _s += _buf[_j];
    return _s;
}

// ── Speculative inspect mode ────────────────────────────────────────

/// Generate speculative suffix for a numeric value.
/// Probes ds_map, ds_list, and instance_exists at runtime.
/// Returns "" if nothing matches, or "~map(5)" / "~list(3),map(2)" etc.
/// ⚠ DUPLICATION: probe logic is shared with scm_bi_inspect in
///   scm_bridge.gml.  Keep them in sync.
function scm__inspect_num_suffix(_n) {
    // Only probe non-negative integers
    if (_n != floor(_n) || _n < 0) return "";

    // ds_map/ds_list probes removed — too noisy (small integers
    // almost always coincide with a valid ds handle ID).
    // Use (inspect n) or (ds-map? n) / (ds-list? n) for explicit probing.

    // Instance IDs in GMS2 start at 100000+; lower values are object indices
    // and instance_exists() on an object index returns true if ANY instance
    // of that object exists — that would be a false positive.
    if (_n >= 100000 && instance_exists(_n)) {
        return "~inst(" + object_get_name(_n.object_index) + ")";
    }

    return "";
}

/// Convert a Scheme value to its inspect string (REPL result display).
/// Like write_str, but plain numbers get speculative annotations:
///   42~map(5)   42~map(5),list(3)   100042~inst(o_player)
/// Recursively inspects elements inside arrays, structs, and lists.
function scm_inspect_str(_v) {
    switch (_v.t) {
        case SCM_NUM:
            return scm_display_str(_v) + scm__inspect_num_suffix(_v.v);
        case SCM_STR:
            return scm_write_str(_v);
        case SCM_PAIR:
            return scm__print_list(_v, 2);
        case SCM_HANDLE:
            switch (_v.ht) {
                case SCM_HT_ARRAY:  return scm__print_array(_v.v, 2);
                case SCM_HT_STRUCT: return scm__print_struct(_v.v, 2);
                default:            return scm_display_str(_v);
            }
        default:
            return scm_display_str(_v);
    }
}
