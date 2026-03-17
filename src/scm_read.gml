/// scm_read.gml — Reader (tokenizer + parser)
///
/// Converts a source string into Scheme values (S-expressions).
/// Usage:
///   var _reader = new ScmReader("(+ 1 2)");
///   var _expr   = _reader.read();
///
/// Also provides a convenience wrapper:
///   var _expr = scm_read_string("(+ 1 2)");

// ── Number validation helper ────────────────────────────────────────

/// Check if a raw atom string represents a number.
/// Handles: 42, -3, +5, 3.14, -.5, .5, etc.
function scm__is_number_str(_s) {
    var _len = string_length(_s);
    if (_len == 0) return false;

    var _i  = 1;  // GML strings are 1-indexed
    var _ch = string_char_at(_s, 1);

    // Optional leading sign
    if (_ch == "+" || _ch == "-") {
        if (_len == 1) return false;  // bare "+" or "-" is a symbol
        _i = 2;
    }

    var _has_digit = false;
    var _has_dot   = false;

    while (_i <= _len) {
        _ch = string_char_at(_s, _i);
        if (_ch >= "0" && _ch <= "9") {
            _has_digit = true;
        } else if (_ch == "." && !_has_dot) {
            _has_dot = true;
        } else {
            return false;
        }
        _i++;
    }
    return _has_digit;
}

// ── Reader constructor ──────────────────────────────────────────────

function ScmReader(_src) constructor {
    src = _src;
    pos = 0;                        // 0-based read cursor
    len = string_length(_src);
    line = 1;                       // 1-based line number
    col  = 1;                       // 1-based column number

    /// Return the next character without consuming it ("" at EOF).
    static peek = function() {
        if (pos >= len) return "";
        return string_char_at(src, pos + 1);
    };

    /// Consume and return one character, updating line/col.
    static advance = function() {
        var _ch = string_char_at(src, pos + 1);
        pos++;
        if (_ch == "\n") { line++; col = 1; }
        else { col++; }
        return _ch;
    };

    /// Skip whitespace and line comments (; ... \n).
    static skip_ws = function() {
        while (pos < len) {
            var _ch = string_char_at(src, pos + 1);
            if (_ch == " " || _ch == "\n" || _ch == "\r" || _ch == "\t") {
                pos++;
                if (_ch == "\n") { line++; col = 1; }
                else { col++; }
            } else if (_ch == ";") {
                while (pos < len && string_char_at(src, pos + 1) != "\n") { pos++; col++; }
            } else {
                break;
            }
        }
    };

    /// Format an error with source position.
    static read_err = function(_msg) {
        return scm_err(_msg + " at line " + string(line) + " col " + string(col));
    };

    /// Read one Scheme datum.  Returns an SCM_ERR on malformed input.
    static read = function() {
        skip_ws();
        if (pos >= len) return read_err("unexpected end of input");

        var _ch = peek();

        // List
        if (_ch == "(") return read_list();

        // Quote sugar
        if (_ch == "'") {
            advance();
            var _datum = read();
            if (scm_is_err(_datum)) return _datum;
            return scm_cons(scm_sym("quote"), scm_cons(_datum, scm_nil()));
        }

        // Quasiquote sugar
        if (_ch == "`") {
            advance();
            var _datum = read();
            if (scm_is_err(_datum)) return _datum;
            return scm_cons(scm_sym("quasiquote"), scm_cons(_datum, scm_nil()));
        }

        // Unquote / unquote-splicing sugar
        if (_ch == ",") {
            advance();
            if (peek() == "@") {
                advance();
                var _datum = read();
                if (scm_is_err(_datum)) return _datum;
                return scm_cons(scm_sym("unquote-splicing"), scm_cons(_datum, scm_nil()));
            }
            var _datum = read();
            if (scm_is_err(_datum)) return _datum;
            return scm_cons(scm_sym("unquote"), scm_cons(_datum, scm_nil()));
        }

        // String literal
        if (_ch == "\"") return read_string();

        // Hash literals (#t, #f)
        if (_ch == "#") return read_hash();

        // Atom (number or symbol)
        return read_atom();
    };

    // ── List reader ─────────────────────────────────────────────────

    static read_list = function() {
        advance();  // skip '('
        skip_ws();

        if (pos >= len) return read_err("unterminated list");
        if (peek() == ")") { advance(); return scm_nil(); }  // empty list

        // Accumulate items using a "last-pair" pointer for O(1) append
        var _first = read();
        if (scm_is_err(_first)) return _first;

        var _head = scm_cons(_first, scm_nil());
        var _tail = _head;

        while (true) {
            skip_ws();
            if (pos >= len) return read_err("unterminated list");

            if (peek() == ")") {
                advance();
                return _head;
            }

            var _item = read();
            if (scm_is_err(_item)) return _item;

            // Dot notation: (a b . c)
            if (scm_is_sym(_item) && _item.v == ".") {
                skip_ws();
                var _cdr_val = read();
                if (scm_is_err(_cdr_val)) return _cdr_val;
                scm_set_cdr(_tail, _cdr_val);
                skip_ws();
                if (pos >= len || peek() != ")")
                    return read_err("expected ) after dotted pair");
                advance();
                return _head;
            }

            var _new_pair = scm_cons(_item, scm_nil());
            scm_set_cdr(_tail, _new_pair);
            _tail = _new_pair;
        }
    };

    // ── String reader ───────────────────────────────────────────────

    static read_string = function() {
        advance();  // skip opening "
        var _start = pos;

        // Fast path: scan for closing " without escapes
        while (pos < len) {
            var _ch = string_char_at(src, pos + 1);
            if (_ch == "\"") {
                // No escapes — use substring slice
                var _s = string_copy(src, _start + 1, pos - _start);
                pos++; col++;  // skip closing "
                return scm_str(_s);
            }
            if (_ch == "\\") break;  // fall through to slow path
            pos++;
            if (_ch == "\n") { line++; col = 1; } else { col++; }
        }

        // Slow path: has escapes. Copy what we have so far, then char-by-char.
        var _s = string_copy(src, _start + 1, pos - _start);
        while (pos < len) {
            var _ch = advance();
            if (_ch == "\"") return scm_str(_s);
            if (_ch == "\\") {
                if (pos >= len) break;
                var _esc = advance();
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
        return read_err("unterminated string");
    };

    // ── Hash reader (#t, #f, #\\char) ───────────────────────────────

    static read_hash = function() {
        advance();  // skip '#'
        if (pos >= len) return read_err("unexpected end after #");
        var _ch = advance();
        switch (_ch) {
            case "t": return scm_bool(true);
            case "f": return scm_bool(false);
            default:  return read_err("unknown # syntax: #" + _ch);
        }
    };

    // ── Atom reader (numbers and symbols) ───────────────────────────

    static read_atom = function() {
        var _start = pos;

        // Scan until delimiter — no per-char string concat
        while (pos < len) {
            var _ch = string_char_at(src, pos + 1);
            if (_ch == " "  || _ch == "\n" || _ch == "\r" || _ch == "\t" ||
                _ch == "("  || _ch == ")"  || _ch == "\"" || _ch == ";" ||
                _ch == "'"  || _ch == "`"  || _ch == ",") {
                break;
            }
            pos++;
            if (_ch == "\n") { line++; col = 1; } else { col++; }
        }

        var _atom_len = pos - _start;
        if (_atom_len == 0) return read_err("unexpected character");

        // Substring slice — O(1) in GML
        var _s = string_copy(src, _start + 1, _atom_len);

        // Inline number detection (avoids second pass through scm__is_number_str)
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
        return scm_sym(_s);
    };

    /// Check whether there is more input after whitespace.
    static has_more = function() {
        skip_ws();
        return pos < len;
    };
}

// ── Convenience wrappers ────────────────────────────────────────────

/// Read the first S-expression from a string.
function scm_read_string(_src) {
    var _reader = new ScmReader(_src);
    return _reader.read();
}

/// Read ALL S-expressions from a string into a GML array.
function scm_read_all(_src) {
    var _reader = new ScmReader(_src);
    var _exprs  = [];
    while (_reader.has_more()) {
        var _e = _reader.read();
        if (scm_is_err(_e)) { array_push(_exprs, _e); break; }
        array_push(_exprs, _e);
    }
    return _exprs;
}
