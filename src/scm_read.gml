/// scm_read.gml — Reader (tokenizer + parser)
///
/// Converts a source string into Scheme values (S-expressions).
/// Usage:
///   var _r = scm_reader_new("(+ 1 2)");
///   var _expr = scm_reader_read(_r);
///
/// Also provides a convenience wrapper:
///   var _expr = scm_read_string("(+ 1 2)");

// ── Reader state ────────────────────────────────────────────────────

/// Create a new reader state struct from a source string.
function scm_reader_new(_src) {
    return {
        src:  _src,
        pos:  0,                        // 0-based read cursor
        len:  string_length(_src),
        line: 1,                        // 1-based line number
        col:  1                         // 1-based column number
    };
}

// ── Internal reader helpers ─────────────────────────────────────────

/// Return the next character without consuming it ("" at EOF).
function scm__reader_peek(_r) {
    if (_r.pos >= _r.len) return "";
    return string_char_at(_r.src, _r.pos + 1);
}

/// Consume and return one character, updating line/col.
function scm__reader_advance(_r) {
    var _ch = string_char_at(_r.src, _r.pos + 1);
    _r.pos++;
    if (_ch == "\n") { _r.line++; _r.col = 1; }
    else { _r.col++; }
    return _ch;
}

/// Skip whitespace and line comments (; ... \n).
function scm__reader_skip_ws(_r) {
    while (_r.pos < _r.len) {
        var _ch = string_char_at(_r.src, _r.pos + 1);
        if (_ch == " " || _ch == "\n" || _ch == "\r" || _ch == "\t") {
            _r.pos++;
            if (_ch == "\n") { _r.line++; _r.col = 1; }
            else { _r.col++; }
        } else if (_ch == ";") {
            while (_r.pos < _r.len && string_char_at(_r.src, _r.pos + 1) != "\n") { _r.pos++; _r.col++; }
        } else {
            break;
        }
    }
}

/// Format an error with source position.
function scm__reader_err(_r, _msg) {
    return scm_err(_msg + " at line " + string(_r.line) + " col " + string(_r.col));
}

// ── Sub-readers (defined before scm_reader_read so they can be called) ──

/// Read a string literal (opening " already peeked).
function scm__reader_read_string(_r) {
    scm__reader_advance(_r);  // skip opening "
    var _start = _r.pos;

    // Fast path: scan for closing " without escapes
    while (_r.pos < _r.len) {
        var _ch = string_char_at(_r.src, _r.pos + 1);
        if (_ch == "\"") {
            // No escapes — use substring slice
            var _s = string_copy(_r.src, _start + 1, _r.pos - _start);
            _r.pos++; _r.col++;  // skip closing "
            return scm_str(_s);
        }
        if (_ch == "\\") break;  // fall through to slow path
        _r.pos++;
        if (_ch == "\n") { _r.line++; _r.col = 1; } else { _r.col++; }
    }

    // Slow path: has escapes. Copy what we have so far, then char-by-char.
    var _s = string_copy(_r.src, _start + 1, _r.pos - _start);
    while (_r.pos < _r.len) {
        var _ch = scm__reader_advance(_r);
        if (_ch == "\"") return scm_str(_s);
        if (_ch == "\\") {
            if (_r.pos >= _r.len) break;
            var _esc = scm__reader_advance(_r);
            switch (_esc) {
                case "n":  _s += "\n"; break;
                case "t":  _s += "\t"; break;
                case "\\": _s += "\\"; break;
                case "\"": _s += "\""; break;
                default:   _s += _esc; break;
            }
        } else {
            _s += _ch;
        }
    }
    return scm__reader_err(_r, "unterminated string");
}

/// Read a # literal (#t, #f, #[...], #{...}).
function scm__reader_read_hash(_r) {
    scm__reader_advance(_r);  // skip '#'
    if (_r.pos >= _r.len) return scm__reader_err(_r, "unexpected end after #");
    var _ch = scm__reader_peek(_r);

    switch (_ch) {
        case "t": scm__reader_advance(_r); return scm_bool(true);
        case "f": scm__reader_advance(_r); return scm_bool(false);
        case "[": return scm__reader_read_vector(_r);
        case "{": return scm__reader_read_hash_table(_r);
        default:  return scm__reader_err(_r, "unknown # syntax: #" + _ch);
    }
}

/// Read #[expr ...] → (array expr ...)
function scm__reader_read_vector(_r) {
    scm__reader_advance(_r);  // skip '['
    scm__reader_skip_ws(_r);

    // Build (array item1 item2 ...)
    var _head = scm_cons(scm_sym("array"), scm_nil());
    var _tail = _head;

    while (true) {
        scm__reader_skip_ws(_r);
        if (_r.pos >= _r.len) return scm__reader_err(_r, "unterminated #[");
        if (scm__reader_peek(_r) == "]") {
            scm__reader_advance(_r);
            return _head;
        }
        var _item = scm_reader_read(_r);
        if (scm_is_err(_item)) return _item;
        var _new = scm_cons(_item, scm_nil());
        scm_set_cdr(_tail, _new);
        _tail = _new;
    }
}

/// Read #{key val ...} → (struct key val ...)
function scm__reader_read_hash_table(_r) {
    scm__reader_advance(_r);  // skip '{'
    scm__reader_skip_ws(_r);

    // Build (struct k1 v1 k2 v2 ...)
    var _head = scm_cons(scm_sym("struct"), scm_nil());
    var _tail = _head;

    while (true) {
        scm__reader_skip_ws(_r);
        if (_r.pos >= _r.len) return scm__reader_err(_r, "unterminated #{");
        if (scm__reader_peek(_r) == "}") {
            scm__reader_advance(_r);
            return _head;
        }
        var _item = scm_reader_read(_r);
        if (scm_is_err(_item)) return _item;
        var _new = scm_cons(_item, scm_nil());
        scm_set_cdr(_tail, _new);
        _tail = _new;
    }
}

/// Read an atom (number or symbol).
function scm__reader_read_atom(_r) {
    var _start = _r.pos;

    // Scan until delimiter — no per-char string concat
    while (_r.pos < _r.len) {
        var _ch = string_char_at(_r.src, _r.pos + 1);
        if (_ch == " "  || _ch == "\n" || _ch == "\r" || _ch == "\t" ||
            _ch == "("  || _ch == ")"  || _ch == "\"" || _ch == ";" ||
            _ch == "'"  || _ch == "`"  || _ch == "," ||
            _ch == "["  || _ch == "]"  || _ch == "{"  || _ch == "}") {
            break;
        }
        _r.pos++;
        if (_ch == "\n") { _r.line++; _r.col = 1; } else { _r.col++; }
    }

    var _atom_len = _r.pos - _start;
    if (_atom_len == 0) return scm__reader_err(_r, "unexpected character");

    // Substring slice — O(1) in GML
    var _s = string_copy(_r.src, _start + 1, _atom_len);

    // Inline number detection (avoids second pass)
    var _i  = 1;
    var _ch = string_char_at(_s, 1);

    // Optional leading sign
    if (_ch == "+" || _ch == "-") {
        if (_atom_len == 1) return scm_sym(_s);  // bare +/-
        _i = 2;
    }

    var _has_digit = false;
    var _has_dot   = false;
    var _is_num    = true;

    while (_i <= _atom_len) {
        _ch = string_char_at(_s, _i);
        if (_ch >= "0" && _ch <= "9") {
            _has_digit = true;
        } else if (_ch == "." && !_has_dot) {
            _has_dot = true;
        } else {
            _is_num = false;
            break;
        }
        _i++;
    }

    if (_is_num && _has_digit) {
        return scm_num(real(_s));
    }

    // ── Namespace prefix desugar ────────────────────────────────
    // obj:name / spr:name / snd:name / rm:name / scr:name → (gml:asset-get-index "name")
    // fn:name  / g:name                                    → (gml:variable-global-get "name")
    var _colon = string_pos(":", _s);
    if (_colon > 1 && _colon < _atom_len) {
        var _ns = string_copy(_s, 1, _colon - 1);
        var _id = string_copy(_s, _colon + 1, _atom_len - _colon);
        switch (_ns) {
            case "obj":
            case "spr":
            case "snd":
            case "rm":
            case "scr":
                return scm_cons(scm_sym("gml:asset-get-index"),
                           scm_cons(scm_str(_id), scm_nil()));
            case "fn":
            case "g":
                return scm_cons(scm_sym("gml:variable-global-get"),
                           scm_cons(scm_str(_id), scm_nil()));
        }
    }

    return scm_sym(_s);
}

// ── List reader ─────────────────────────────────────────────────────

function scm__reader_read_list(_r) {
    scm__reader_advance(_r);  // skip '('
    scm__reader_skip_ws(_r);

    if (_r.pos >= _r.len) return scm__reader_err(_r, "unterminated list");
    if (scm__reader_peek(_r) == ")") { scm__reader_advance(_r); return scm_nil(); }

    // Accumulate items using a "last-pair" pointer for O(1) append
    var _first = scm_reader_read(_r);
    if (scm_is_err(_first)) return _first;

    var _head = scm_cons(_first, scm_nil());
    var _tail = _head;

    while (true) {
        scm__reader_skip_ws(_r);
        if (_r.pos >= _r.len) return scm__reader_err(_r, "unterminated list");

        if (scm__reader_peek(_r) == ")") {
            scm__reader_advance(_r);
            return _head;
        }

        var _item = scm_reader_read(_r);
        if (scm_is_err(_item)) return _item;

        // Dot notation: (a b . c)
        if (scm_is_sym(_item) && _item.v == ".") {
            scm__reader_skip_ws(_r);
            var _cdr_val = scm_reader_read(_r);
            if (scm_is_err(_cdr_val)) return _cdr_val;
            scm_set_cdr(_tail, _cdr_val);
            scm__reader_skip_ws(_r);
            if (_r.pos >= _r.len || scm__reader_peek(_r) != ")")
                return scm__reader_err(_r, "expected ) after dotted pair");
            scm__reader_advance(_r);
            return _head;
        }

        var _new_pair = scm_cons(_item, scm_nil());
        scm_set_cdr(_tail, _new_pair);
        _tail = _new_pair;
    }
}

// ── Main read function ──────────────────────────────────────────────

/// Read one Scheme datum.  Returns an SCM_ERR on malformed input.
function scm_reader_read(_r) {
    scm__reader_skip_ws(_r);
    if (_r.pos >= _r.len) return scm__reader_err(_r, "unexpected end of input");

    var _ch = scm__reader_peek(_r);

    // List
    if (_ch == "(") return scm__reader_read_list(_r);

    // Quote sugar
    if (_ch == "'") {
        scm__reader_advance(_r);
        var _datum = scm_reader_read(_r);
        if (scm_is_err(_datum)) return _datum;
        return scm_cons(scm_sym("quote"), scm_cons(_datum, scm_nil()));
    }

    // Quasiquote sugar
    if (_ch == "`") {
        scm__reader_advance(_r);
        var _datum = scm_reader_read(_r);
        if (scm_is_err(_datum)) return _datum;
        return scm_cons(scm_sym("quasiquote"), scm_cons(_datum, scm_nil()));
    }

    // Unquote / unquote-splicing sugar
    if (_ch == ",") {
        scm__reader_advance(_r);
        if (scm__reader_peek(_r) == "@") {
            scm__reader_advance(_r);
            var _datum = scm_reader_read(_r);
            if (scm_is_err(_datum)) return _datum;
            return scm_cons(scm_sym("unquote-splicing"), scm_cons(_datum, scm_nil()));
        }
        var _datum = scm_reader_read(_r);
        if (scm_is_err(_datum)) return _datum;
        return scm_cons(scm_sym("unquote"), scm_cons(_datum, scm_nil()));
    }

    // String literal
    if (_ch == "\"") return scm__reader_read_string(_r);

    // Hash literals (#t, #f)
    if (_ch == "#") return scm__reader_read_hash(_r);

    // Atom (number or symbol)
    return scm__reader_read_atom(_r);
}

/// Check whether there is more input after whitespace.
function scm_reader_has_more(_r) {
    scm__reader_skip_ws(_r);
    return _r.pos < _r.len;
}

// ── Convenience wrappers ────────────────────────────────────────────

/// Read the first S-expression from a string.
function scm_read_string(_src) {
    var _r = scm_reader_new(_src);
    return scm_reader_read(_r);
}

/// Read ALL S-expressions from a string into a GML array.
function scm_read_all(_src) {
    var _r = scm_reader_new(_src);
    var _exprs  = [];
    while (scm_reader_has_more(_r)) {
        var _e = scm_reader_read(_r);
        if (scm_is_err(_e)) { array_push(_exprs, _e); break; }
        array_push(_exprs, _e);
    }
    return _exprs;
}
