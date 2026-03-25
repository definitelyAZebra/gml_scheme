// ═══════════════════════════════════════════════════════════════════
//  scm_lex.gml — Scheme Lexical Analysis
// ═══════════════════════════════════════════════════════════════════
//  Tokenizer and classification helpers for Scheme source text:
//    - Token type constants (RTOK_*)
//    - Character classification (delimiter, number)
//    - Environment queries for syntax coloring (procedure, macro)
//    - Full tokenizer producing [type, text] pairs
//
//  Depends on:  scm_types.gml (SCM_FN, SCM_LAMBDA, SCM_CASE_LAMBDA)
//               scm_env.gml  (scm_env_get)
//  Used by:     scm_repl_shell.gml
// ═══════════════════════════════════════════════════════════════════

// ─── Token Types ────────────────────────────────────────────────

/// Token type constants (used as array[0] in token pairs)
#macro RTOK_WHITESPACE  0
#macro RTOK_COMMENT     1
#macro RTOK_STRING      2
#macro RTOK_LPAREN      3
#macro RTOK_RPAREN      4
#macro RTOK_QUOTE       5
#macro RTOK_BOOLEAN     6
#macro RTOK_NUMBER      7
#macro RTOK_KEYWORD     8
#macro RTOK_BUILTIN     9
#macro RTOK_SYMBOL      10
#macro RTOK_MACRO       11

// ─── Character Classification ───────────────────────────────────

/// Check if a single character (string) is a delimiter.
function scm_lex_is_delimiter(_ch) {
    if (_ch == "") return true;
    if (_ch == " " || _ch == "\t" || _ch == "\n" || _ch == "\r") return true;
    if (_ch == "(" || _ch == ")") return true;
    if (_ch == "[" || _ch == "]" || _ch == "{" || _ch == "}") return true;
    if (_ch == "\"" || _ch == ";") return true;
    if (_ch == "'" || _ch == "`" || _ch == ",") return true;
    return false;
}

/// Check if a string represents a number (optional +/-, digits, at most one dot).
function scm_lex_is_number(_s) {
    var _len = string_length(_s);
    if (_len == 0) return false;

    var _ch0 = string_char_at(_s, 1);
    var _start = 0;
    if (_ch0 == "+" || _ch0 == "-") {
        _start = 1;
        if (_len == 1) return false;
    }

    var _has_digit = false;
    var _has_dot = false;
    for (var _i = _start; _i < _len; _i++) {
        var _ch = string_char_at(_s, _i + 1); // 1-based
        var _o = ord(_ch);
        if (_o >= 48 && _o <= 57) { // '0'-'9'
            _has_digit = true;
        } else if (_ch == "." && !_has_dot) {
            _has_dot = true;
        } else {
            return false;
        }
    }
    return _has_digit;
}

// ─── Environment Queries ────────────────────────────────────────

/// Check if a symbol name refers to a procedure (builtin or lambda) in the env.
function scm_lex_is_procedure(_name) {
    if (!variable_global_exists("scm_env")) return false;
    var _val = scm_env_get(global.scm_env, _name);
    if (_val == undefined) return false;
    return (_val.t == SCM_FN || _val.t == SCM_LAMBDA || _val.t == SCM_CASE_LAMBDA);
}

/// Check if a symbol name is a user-defined macro.
function scm_lex_is_macro(_name) {
    if (!variable_global_exists("__scm_macros")) return false;
    return variable_struct_exists(global.__scm_macros, _name);
}

// ─── Tokenizer ──────────────────────────────────────────────────

/// Tokenize a Scheme source string.
/// Returns array of [type, text] pairs.
///
/// Accesses global.__repl_keywords for keyword classification.
function scm_lex_tokenize(_src) {
    var _len = string_length(_src);
    var _tokens = [];
    var _pos = 0;

    while (_pos < _len) {
        var _ch = string_char_at(_src, _pos + 1); // GML is 1-based

        // Whitespace run
        if (_ch == " " || _ch == "\t" || _ch == "\n" || _ch == "\r") {
            var _end = _pos + 1;
            while (_end < _len) {
                var _wc = string_char_at(_src, _end + 1);
                if (_wc != " " && _wc != "\t" && _wc != "\n" && _wc != "\r") break;
                _end++;
            }
            array_push(_tokens, [RTOK_WHITESPACE, string_copy(_src, _pos + 1, _end - _pos)]);
            _pos = _end;
            continue;
        }

        // Comment: ; to end of line
        if (_ch == ";") {
            var _end = _pos + 1;
            while (_end < _len && string_char_at(_src, _end + 1) != "\n") {
                _end++;
            }
            array_push(_tokens, [RTOK_COMMENT, string_copy(_src, _pos + 1, _end - _pos)]);
            _pos = _end;
            continue;
        }

        // String literal
        if (_ch == "\"") {
            var _end = _pos + 1;
            var _escaped = false;
            while (_end < _len) {
                var _sc = string_char_at(_src, _end + 1);
                if (_escaped) {
                    _escaped = false;
                    _end++;
                    continue;
                }
                if (_sc == "\\") {
                    _escaped = true;
                    _end++;
                    continue;
                }
                if (_sc == "\"") {
                    _end++;
                    break;
                }
                _end++;
            }
            array_push(_tokens, [RTOK_STRING, string_copy(_src, _pos + 1, _end - _pos)]);
            _pos = _end;
            continue;
        }

        // Parens
        if (_ch == "(") {
            array_push(_tokens, [RTOK_LPAREN, "("]);
            _pos++;
            continue;
        }
        if (_ch == ")") {
            array_push(_tokens, [RTOK_RPAREN, ")"]);
            _pos++;
            continue;
        }
        // Brackets (close only — #[ and #{ open via # handler)
        if (_ch == "]") {
            array_push(_tokens, [RTOK_RPAREN, "]"]);
            _pos++;
            continue;
        }
        if (_ch == "}") {
            array_push(_tokens, [RTOK_RPAREN, "}"]);
            _pos++;
            continue;
        }

        // Quote sugar
        if (_ch == "'") {
            array_push(_tokens, [RTOK_QUOTE, "'"]);
            _pos++;
            continue;
        }
        if (_ch == "`") {
            array_push(_tokens, [RTOK_QUOTE, "`"]);
            _pos++;
            continue;
        }
        if (_ch == ",") {
            if (_pos + 1 < _len && string_char_at(_src, _pos + 2) == "@") {
                array_push(_tokens, [RTOK_QUOTE, ",@"]);
                _pos += 2;
            } else {
                array_push(_tokens, [RTOK_QUOTE, ","]);
                _pos++;
            }
            continue;
        }

        // Hash literals (#t, #f, #[, #{)
        if (_ch == "#") {
            if (_pos + 1 < _len) {
                var _next = string_char_at(_src, _pos + 2);
                if (_next == "t" || _next == "f") {
                    array_push(_tokens, [RTOK_BOOLEAN, "#" + _next]);
                    _pos += 2;
                    continue;
                }
                if (_next == "[") {
                    array_push(_tokens, [RTOK_LPAREN, "#["]);
                    _pos += 2;
                    continue;
                }
                if (_next == "{") {
                    array_push(_tokens, [RTOK_LPAREN, "#{"]);
                    _pos += 2;
                    continue;
                }
            }
            array_push(_tokens, [RTOK_SYMBOL, "#"]);
            _pos++;
            continue;
        }

        // Atom: consume until delimiter, then classify
        var _end = _pos + 1;
        while (_end < _len && !scm_lex_is_delimiter(string_char_at(_src, _end + 1))) {
            _end++;
        }
        var _text = string_copy(_src, _pos + 1, _end - _pos);
        var _type;
        if (scm_lex_is_number(_text)) {
            _type = RTOK_NUMBER;
        } else if (ds_map_exists(global.__repl_keywords, _text)) {
            _type = RTOK_KEYWORD;
        } else if (scm_lex_is_macro(_text)) {
            _type = RTOK_MACRO;
        } else if (scm_lex_is_procedure(_text)) {
            _type = RTOK_BUILTIN;
        } else {
            _type = RTOK_SYMBOL;
        }
        array_push(_tokens, [_type, _text]);
        _pos = _end;
    }

    return _tokens;
}
