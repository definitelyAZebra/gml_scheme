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
        case SCM_FN:     return "#<builtin:" + _v.name + ">";
        case SCM_LAMBDA: return "#<lambda:" + _v.name + ">";
        case SCM_VOID:   return "#<void>";
        case SCM_ERR:    return "#<error: " + _v.v + ">";
        case SCM_HANDLE:
            switch (_v.ht) {
                case SCM_HT_ARRAY:    return "#<array:" + string(array_length(_v.v)) + ">";
                case SCM_HT_STRUCT:   return "#<struct>";
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

/// Print a list/dotted-pair. Uses array buffer to avoid O(n²) concat.
function scm__print_list(_v, _write_mode) {
    var _buf = ["("];
    var _first = true;
    var _p = _v;

    while (_p.t == SCM_PAIR) {
        if (!_first) array_push(_buf, " ");
        _first = false;
        array_push(_buf, _write_mode ? scm_write_str(_p.car) : scm_display_str(_p.car));
        _p = _p.cdr;
    }

    // Improper list (dotted pair)
    if (_p.t != SCM_NIL) {
        array_push(_buf, " . ");
        array_push(_buf, _write_mode ? scm_write_str(_p) : scm_display_str(_p));
    }

    array_push(_buf, ")");
    var _s = "";
    for (var _i = 0; _i < array_length(_buf); _i++) _s += _buf[_i];
    return _s;
}
