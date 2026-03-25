// ═══════════════════════════════════════════════════════════════════
//  scm_sexpr.gml — S-Expression Structural Analysis
// ═══════════════════════════════════════════════════════════════════
//  Pure-function analysis of Scheme source structure:
//    - Paren depth counting (respects strings and comments)
//    - Expression completeness checking
//    - Auto-indent computation
//    - Forward/backward bracket matching
//
//  Depends on:  nothing (standalone — operates on raw strings)
//  Used by:     scm_repl_shell.gml
// ═══════════════════════════════════════════════════════════════════

// ─── Paren Depth & Balance ──────────────────────────────────────

/// Count net paren depth, respecting strings and comments.
function scm_sexpr_depth(_src) {
    var _len = string_length(_src);
    var _depth = 0;
    var _in_string = false;
    var _in_comment = false;
    var _escaped = false;

    for (var _i = 0; _i < _len; _i++) {
        var _ch = string_char_at(_src, _i + 1);

        if (_in_comment) {
            if (_ch == "\n") { _in_comment = false; }
            continue;
        }

        if (_in_string) {
            if (_escaped) { _escaped = false; continue; }
            if (_ch == "\\") { _escaped = true; continue; }
            if (_ch == "\"") { _in_string = false; }
            continue;
        }

        if (_ch == ";") { _in_comment = true; continue; }
        if (_ch == "\"") { _in_string = true; continue; }
        if (_ch == "(" || _ch == "[" || _ch == "{") { _depth++; continue; }
        if (_ch == ")" || _ch == "]" || _ch == "}") { _depth--; continue; }
    }
    return _depth;
}

/// Check if source ends inside an unclosed string.
function scm_sexpr_in_string(_src) {
    var _len = string_length(_src);
    var _in_str = false;
    var _escaped = false;

    for (var _i = 0; _i < _len; _i++) {
        var _ch = string_char_at(_src, _i + 1);

        if (_in_str) {
            if (_escaped) { _escaped = false; continue; }
            if (_ch == "\\") { _escaped = true; continue; }
            if (_ch == "\"") { _in_str = false; continue; }
            continue;
        }

        if (_ch == "\"") { _in_str = true; continue; }
        if (_ch == ";") {
            // Skip to end of line
            while (_i + 1 < _len && string_char_at(_src, _i + 2) != "\n") {
                _i++;
            }
            _i++; // skip past the \n
            continue;
        }
    }
    return _in_str;
}

/// Check if source has any non-whitespace non-comment content.
function scm_sexpr_has_content(_src) {
    var _len = string_length(_src);
    var _in_comment = false;

    for (var _i = 0; _i < _len; _i++) {
        var _ch = string_char_at(_src, _i + 1);
        if (_in_comment) {
            if (_ch == "\n") _in_comment = false;
            continue;
        }
        if (_ch == ";") { _in_comment = true; continue; }
        if (_ch != " " && _ch != "\t" && _ch != "\n" && _ch != "\r") return true;
    }
    return false;
}

/// Check if source is a complete expression (balanced, not in string, has content).
function scm_sexpr_complete(_src) {
    return (scm_sexpr_depth(_src) == 0)
        && (!scm_sexpr_in_string(_src))
        && scm_sexpr_has_content(_src);
}

/// Compute auto-indent level (2 spaces per open paren depth).
function scm_sexpr_auto_indent(_src) {
    var _d = scm_sexpr_depth(_src);
    if (_d <= 0) return 0;
    return _d * 2;
}

// ─── Bracket Matching ───────────────────────────────────────────

/// Find matching paren position for cursor. Returns -1 if none.
/// _cursor_pos: 0-based character position.
function scm_sexpr_match_paren(_src, _cursor_pos) {
    var _len = string_length(_src);
    if (_cursor_pos < 0 || _cursor_pos >= _len) return -1;

    var _ch = string_char_at(_src, _cursor_pos + 1);
    if (_ch == "(" || _ch == "[" || _ch == "{") return scm_sexpr_find_close(_src, _cursor_pos + 1, 1, _ch);
    if (_ch == ")" || _ch == "]" || _ch == "}") return scm_sexpr_find_open(_src, _cursor_pos - 1, 1, _ch);
    return -1;
}

/// Find closing bracket (scan forward). 0-based positions.
/// _open_ch is the opening bracket char to determine the matching close.
function scm_sexpr_find_close(_src, _pos, _depth, _open_ch) {
    var _len = string_length(_src);
    var _in_str = false;
    var _escaped = false;
    var _close_ch = (_open_ch == "(") ? ")" : ((_open_ch == "[") ? "]" : "}");

    while (_pos < _len) {
        var _ch = string_char_at(_src, _pos + 1);
        if (_in_str) {
            if (_escaped) { _escaped = false; }
            else if (_ch == "\\") { _escaped = true; }
            else if (_ch == "\"") { _in_str = false; }
        } else {
            if (_ch == "\"") { _in_str = true; }
            else if (_ch == _open_ch) { _depth++; }
            else if (_ch == _close_ch) {
                _depth--;
                if (_depth == 0) return _pos;
            }
        }
        _pos++;
    }
    return -1;
}

/// Find opening bracket (scan backward). 0-based positions.
/// Skips strings and comments correctly.
/// _close_ch is the closing bracket char to determine the matching open.
function scm_sexpr_find_open(_src, _pos, _depth, _close_ch) {
    var _open_ch = (_close_ch == ")") ? "(" : ((_close_ch == "]") ? "[" : "{");
    while (_pos >= 0) {
        var _ch = string_char_at(_src, _pos + 1);

        if (_ch == _close_ch || _ch == _open_ch) {
            if (!scm_sexpr_pos_in_string(_src, _pos)) {
                if (_ch == _close_ch) { _depth++; }
                else {
                    _depth--;
                    if (_depth == 0) return _pos;
                }
            }
        }
        _pos--;
    }
    return -1;
}

/// Check if position _pos (0-based) in _src is inside a string literal.
/// Scans from the start, tracking string/comment/escape state.
function scm_sexpr_pos_in_string(_src, _pos) {
    var _in_str = false;
    var _in_comment = false;
    var _escaped = false;
    for (var _i = 0; _i < _pos; _i++) {
        var _ch = string_char_at(_src, _i + 1);
        if (_in_comment) {
            if (_ch == "\n") _in_comment = false;
            continue;
        }
        if (_in_str) {
            if (_escaped) { _escaped = false; continue; }
            if (_ch == "\\") { _escaped = true; continue; }
            if (_ch == "\"") { _in_str = false; }
            continue;
        }
        if (_ch == ";") { _in_comment = true; continue; }
        if (_ch == "\"") { _in_str = true; }
    }
    return _in_str;
}
