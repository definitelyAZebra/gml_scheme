/// scm_repl_shell.gml - Native GML REPL (v3)
///
/// All REPL UI logic (keyboard, draw, colors, tokenizer, history) in pure GML.
/// Scheme interpreter is used ONLY for evaluating user input.
///
/// Usage in a GML object:
///   Create:      scm_repl_create();
///   Step:        scm_repl_step();
///   Draw GUI:    scm_repl_draw();
///   KeyPress F1: scm_repl_toggle();
///   Destroy:     scm_repl_destroy();
///
/// NOTE: UMT-injected code has NO function hoisting.
///       Callees must be defined BEFORE callers in this file.

// ═══════════════════════════════════════════════════════════════════
//  Section 1: String helpers (must come first — no hoisting)
// ═══════════════════════════════════════════════════════════════════

/// Escape a GML string for embedding in Scheme source.
function scm_repl__quote(_s) {
    _s = string_replace_all(_s, chr(92), chr(92) + chr(92));
    _s = string_replace_all(_s, chr(34), chr(92) + chr(34));
    _s = string_replace_all(_s, chr(10), chr(92) + "n");
    _s = string_replace_all(_s, chr(13), "");
    _s = string_replace_all(_s, chr(9), chr(92) + "t");
    return chr(34) + _s + chr(34);
}

/// Insert text into a string at 0-based position.
function scm_repl__str_insert(_base, _pos, _text) {
    // GML string_insert is 1-based: string_insert(sub, str, index)
    return string_insert(_text, _base, _pos + 1);
}

/// Delete one character at 0-based position.
function scm_repl__str_delete_at(_base, _pos) {
    // GML string_delete is 1-based: string_delete(str, index, count)
    return string_delete(_base, _pos + 1, 1);
}

// ═══════════════════════════════════════════════════════════════════
//  Section 2: Delimiter / number detection
// ═══════════════════════════════════════════════════════════════════

/// Check if a single character (string) is a delimiter.
function scm_repl__is_delimiter(_ch) {
    if (_ch == "") return true;
    if (_ch == " " || _ch == "\t" || _ch == "\n" || _ch == "\r") return true;
    if (_ch == "(" || _ch == ")") return true;
    if (_ch == "\"" || _ch == ";") return true;
    if (_ch == "'" || _ch == "`" || _ch == ",") return true;
    return false;
}

/// Check if a string represents a number (optional +/-, digits, at most one dot).
function scm_repl__is_number(_s) {
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

// ═══════════════════════════════════════════════════════════════════
//  Section 3: Tokenizer
// ═══════════════════════════════════════════════════════════════════

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

/// Tokenize a source string.
/// Returns array of [type, text] pairs.
function scm_repl__tokenize(_src) {
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

        // Hash literals (#t, #f)
        if (_ch == "#") {
            if (_pos + 1 < _len) {
                var _next = string_char_at(_src, _pos + 2);
                if (_next == "t" || _next == "f") {
                    array_push(_tokens, [RTOK_BOOLEAN, "#" + _next]);
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
        while (_end < _len && !scm_repl__is_delimiter(string_char_at(_src, _end + 1))) {
            _end++;
        }
        var _text = string_copy(_src, _pos + 1, _end - _pos);
        var _type;
        if (scm_repl__is_number(_text)) {
            _type = RTOK_NUMBER;
        } else if (ds_map_exists(global.__repl_keywords, _text)) {
            _type = RTOK_KEYWORD;
        } else if (ds_map_exists(global.__repl_builtins, _text)) {
            _type = RTOK_BUILTIN;
        } else {
            _type = RTOK_SYMBOL;
        }
        array_push(_tokens, [_type, _text]);
        _pos = _end;
    }

    return _tokens;
}

// ═══════════════════════════════════════════════════════════════════
//  Section 4: Paren depth / balance / completeness
// ═══════════════════════════════════════════════════════════════════

/// Count net paren depth, respecting strings and comments.
function scm_repl__paren_depth(_src) {
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
        if (_ch == "(") { _depth++; continue; }
        if (_ch == ")") { _depth--; continue; }
    }
    return _depth;
}

/// Check if source ends inside an unclosed string.
function scm_repl__in_string(_src) {
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
function scm_repl__has_content(_src) {
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
function scm_repl__complete(_src) {
    return (scm_repl__paren_depth(_src) == 0)
        && (!scm_repl__in_string(_src))
        && scm_repl__has_content(_src);
}

/// Compute auto-indent level (2 spaces per open paren depth).
function scm_repl__auto_indent(_src) {
    var _d = scm_repl__paren_depth(_src);
    if (_d <= 0) return 0;
    return _d * 2;
}

// ═══════════════════════════════════════════════════════════════════
//  Section 5: Matching paren finder
// ═══════════════════════════════════════════════════════════════════

/// Find matching paren position for cursor. Returns -1 if none.
function scm_repl__match_paren(_src, _cursor_pos) {
    var _len = string_length(_src);
    if (_cursor_pos < 0 || _cursor_pos >= _len) return -1;

    var _ch = string_char_at(_src, _cursor_pos + 1);
    if (_ch == "(") return scm_repl__find_close(_src, _cursor_pos + 1, 1);
    if (_ch == ")") return scm_repl__find_open(_src, _cursor_pos - 1, 1);
    return -1;
}

/// Find closing paren (scan forward). 0-based positions.
function scm_repl__find_close(_src, _pos, _depth) {
    var _len = string_length(_src);
    var _in_str = false;
    var _escaped = false;

    while (_pos < _len) {
        var _ch = string_char_at(_src, _pos + 1);
        if (_in_str) {
            if (_escaped) { _escaped = false; }
            else if (_ch == "\\") { _escaped = true; }
            else if (_ch == "\"") { _in_str = false; }
        } else {
            if (_ch == "\"") { _in_str = true; }
            else if (_ch == "(") { _depth++; }
            else if (_ch == ")") {
                _depth--;
                if (_depth == 0) return _pos;
            }
        }
        _pos++;
    }
    return -1;
}

/// Find opening paren (scan backward). 0-based positions.
function scm_repl__find_open(_src, _pos, _depth) {
    while (_pos >= 0) {
        var _ch = string_char_at(_src, _pos + 1);
        if (_ch == ")") { _depth++; }
        else if (_ch == "(") {
            _depth--;
            if (_depth == 0) return _pos;
        }
        _pos--;
    }
    return -1;
}

// ═══════════════════════════════════════════════════════════════════
//  Section 6: Highlight (tokenize + map to colors)
// ═══════════════════════════════════════════════════════════════════

/// Map token type to a color integer from the palette.
function scm_repl__token_color(_type) {
    switch (_type) {
        case RTOK_KEYWORD:    return global.__repl_c_keyword;
        case RTOK_BUILTIN:    return global.__repl_c_builtin;
        case RTOK_STRING:     return global.__repl_c_string;
        case RTOK_NUMBER:     return global.__repl_c_number;
        case RTOK_BOOLEAN:    return global.__repl_c_number; // same as number (orange)
        case RTOK_COMMENT:    return global.__repl_c_comment;
        case RTOK_LPAREN:     return global.__repl_c_paren;
        case RTOK_RPAREN:     return global.__repl_c_paren;
        case RTOK_QUOTE:      return global.__repl_c_keyword; // same as keyword (purple)
        case RTOK_SYMBOL:     return global.__repl_c_symbol;
        default:              return global.__repl_c_default;
    }
}

/// Highlight tokens: returns array of [color_int, text].
function scm_repl__highlight(_tokens) {
    var _n = array_length(_tokens);
    var _result = array_create(_n);
    for (var _i = 0; _i < _n; _i++) {
        var _tok = _tokens[_i];
        _result[_i] = [scm_repl__token_color(_tok[0]), _tok[1]];
    }
    return _result;
}

// ═══════════════════════════════════════════════════════════════════
//  Section 7: Split lines
// ═══════════════════════════════════════════════════════════════════

/// Split a string on newlines. Returns an array of strings.
function scm_repl__split_lines(_str) {
    var _len = string_length(_str);
    if (_len == 0) return [""];

    var _lines = [];
    var _start = 0;
    for (var _i = 0; _i < _len; _i++) {
        if (string_char_at(_str, _i + 1) == "\n") {
            array_push(_lines, string_copy(_str, _start + 1, _i - _start));
            _start = _i + 1;
        }
    }
    // last segment
    array_push(_lines, string_copy(_str, _start + 1, _len - _start));
    return _lines;
}

// ═══════════════════════════════════════════════════════════════════
//  Section 8: Output management
// ═══════════════════════════════════════════════════════════════════

/// Add a single-color line to output. Delegates to TTY layer.
function scm_repl__add_output(_text, _color) {
    scm_tty_emit(_text, _color);
}

/// Add a spans line to output. Delegates to TTY layer.
function scm_repl__add_output_spans(_spans) {
    scm_tty_emit_spans(_spans);
}

/// Clear all output. Delegates to TTY layer.
function scm_repl__clear_output() {
    scm_tty_clear();
}

// ═══════════════════════════════════════════════════════════════════
//  Section 9: Echo input to output (highlighted)
// ═══════════════════════════════════════════════════════════════════

/// Echo the submitted input to output with syntax highlighting.
function scm_repl__echo_input(_full) {
    var _lines = scm_repl__split_lines(_full);
    var _n = array_length(_lines);
    // Forward: first line inserted at 0, then pushed up by subsequent lines.
    // Result: first line at highest index (furthest from input) = correct reading order.
    for (var _i = 0; _i < _n; _i++) {
        var _line = _lines[_i];
        var _prefix = (_i == 0) ? "> " : "... ";
        var _tokens = scm_repl__tokenize(_line);
        var _highlighted = scm_repl__highlight(_tokens);

        // Build spans: prompt + highlighted tokens
        var _spans = [[global.__repl_c_prompt, _prefix]];
        var _hn = array_length(_highlighted);
        for (var _j = 0; _j < _hn; _j++) {
            array_push(_spans, _highlighted[_j]);
        }
        scm_repl__add_output_spans(_spans);
    }
}

// ═══════════════════════════════════════════════════════════════════
//  Section 10: History management
// ═══════════════════════════════════════════════════════════════════

/// Push input to history (deduplicated, max 100 entries).
function scm_repl__history_push(_input) {
    if (_input == "") return;
    var _n = array_length(global.__repl_history);
    if (_n > 0 && global.__repl_history[0] == _input) return;

    array_insert(global.__repl_history, 0, _input);
    if (array_length(global.__repl_history) > 100) {
        array_pop(global.__repl_history);
    }
}

/// Navigate history. dir > 0 = older, dir < 0 = newer.
function scm_repl__history_nav(_dir) {
    var _size = array_length(global.__repl_history);
    if (_size == 0) return;

    if (_dir > 0) {
        // Up → go back in history
        if (global.__repl_hist_idx < 0) {
            scm_repl__sync_buf();
            global.__repl_hist_saved_lines = [];
            array_copy(global.__repl_hist_saved_lines, 0, global.__repl_lines, 0, array_length(global.__repl_lines));
            global.__repl_hist_saved_line_idx = global.__repl_line_idx;
            global.__repl_hist_idx = 0;
        } else if (global.__repl_hist_idx < _size - 1) {
            global.__repl_hist_idx++;
        }
        scm_repl__recall(global.__repl_history[global.__repl_hist_idx]);
    } else if (_dir < 0) {
        // Down → go forward in history
        if (global.__repl_hist_idx > 0) {
            global.__repl_hist_idx--;
            scm_repl__recall(global.__repl_history[global.__repl_hist_idx]);
        } else if (global.__repl_hist_idx == 0) {
            global.__repl_hist_idx = -1;
            global.__repl_lines = [];
            array_copy(global.__repl_lines, 0, global.__repl_hist_saved_lines, 0, array_length(global.__repl_hist_saved_lines));
            scm_repl__load_line(global.__repl_hist_saved_line_idx);
        }
    }
}

/// Recall a history entry into the lines array.
function scm_repl__recall(_entry) {
    scm_repl__set_lines_from_string(_entry);
}

// ═══════════════════════════════════════════════════════════════════
//  Section 10b: Multi-line helpers
// ═══════════════════════════════════════════════════════════════════

/// Sync the current __repl_buf back into the __repl_lines array.
function scm_repl__sync_buf() {
    global.__repl_lines[global.__repl_line_idx] = global.__repl_buf;
}

/// Load a line from the lines array into __repl_buf for editing.
function scm_repl__load_line(_idx) {
    global.__repl_line_idx = _idx;
    global.__repl_buf = global.__repl_lines[_idx];
    global.__repl_cursor = string_length(global.__repl_buf);
}

/// Join all lines into a single string with "\n" separators.
function scm_repl__join_lines() {
    scm_repl__sync_buf();
    var _s = "";
    for (var _i = 0; _i < array_length(global.__repl_lines); _i++) {
        if (_i > 0) _s += "\n";
        _s += global.__repl_lines[_i];
    }
    return _s;
}

/// Reset input to a single empty line.
function scm_repl__reset_input() {
    global.__repl_lines = [""];
    global.__repl_line_idx = 0;
    global.__repl_buf = "";
    global.__repl_cursor = 0;
}

/// Check if currently in multi-line editing mode (more than 1 line).
function scm_repl__is_multiline() {
    return (array_length(global.__repl_lines) > 1);
}

/// Split a string by "\n" into the __repl_lines array and load the last line.
function scm_repl__set_lines_from_string(_str) {
    global.__repl_lines = scm_repl__split_lines(_str);
    // Trim trailing empty from trailing newline
    var _n = array_length(global.__repl_lines);
    if (_n > 1 && global.__repl_lines[_n - 1] == "") {
        array_delete(global.__repl_lines, _n - 1, 1);
    }
    if (array_length(global.__repl_lines) == 0) {
        global.__repl_lines = [""];
    }
    var _last = array_length(global.__repl_lines) - 1;
    scm_repl__load_line(_last);
}

// ═══════════════════════════════════════════════════════════════════
//  Section 11: Input operations
// ═══════════════════════════════════════════════════════════════════

/// Type characters into the buffer at cursor.
/// Filters out non-printable-ASCII characters (e.g. CJK from IME switching).
function scm_repl__type_chars(_str) {
    // Only allow printable ASCII (0x20 space .. 0x7E tilde)
    var _filtered = "";
    for (var _i = 1; _i <= string_length(_str); _i++) {
        var _code = ord(string_char_at(_str, _i));
        if (_code >= 0x20 && _code <= 0x7E) {
            _filtered += string_char_at(_str, _i);
        }
    }
    if (_filtered == "") return;
    global.__repl_buf = scm_repl__str_insert(global.__repl_buf, global.__repl_cursor, _filtered);
    global.__repl_cursor += string_length(_filtered);
    global.__repl_hist_idx = -1;
}

/// Paste from clipboard (strip \r).
function scm_repl__paste(_str) {
    var _clean = string_replace_all(_str, chr(13), "");
    scm_repl__type_chars(_clean);
}

/// Check if input string is empty (only whitespace/newlines).
function scm_repl__empty_input(_str) {
    var _stripped = string_replace_all(string_replace_all(_str, " ", ""), "\n", "");
    return (_stripped == "");
}

/// Submit or continue multi-line input.
function scm_repl__submit() {
    var _full = scm_repl__join_lines();
    if (scm_repl__empty_input(_full)) {
        // Empty → echo empty prompt and reset
        scm_repl__add_output("> ", global.__repl_c_prompt);
        scm_repl__reset_input();
        return;
    }

    // REPL commands (start with ":")
    var _trimmed = _full;
    while (string_char_at(_trimmed, 1) == " ") {
        _trimmed = string_copy(_trimmed, 2, string_length(_trimmed) - 1);
    }
    if (string_char_at(_trimmed, 1) == ":") {
        scm_repl__add_output("> " + _full, global.__repl_c_prompt);
        scm_repl__history_push(_full);
        scm_repl__exec_command(_trimmed);
        scm_repl__reset_input();
        return;
    }

    if (scm_repl__complete(_full)) {
        // Complete → request eval
        scm_repl__echo_input(_full);
        scm_repl__history_push(_full);
        global.__repl_eval_pending = _full;
        scm_repl__reset_input();
    } else {
        // Incomplete → continue multi-line
        scm_repl__newline();
    }
}

/// Insert a newline (Shift+Enter) with auto-indent.
function scm_repl__newline() {
    scm_repl__sync_buf();
    var _full = scm_repl__join_lines();
    var _indent_n = scm_repl__auto_indent(_full);
    var _indent_str = "";
    repeat (_indent_n) { _indent_str += " "; }
    // Split current line at cursor
    var _cur = global.__repl_lines[global.__repl_line_idx];
    var _before = string_copy(_cur, 1, global.__repl_cursor);
    var _after = string_copy(_cur, global.__repl_cursor + 1, string_length(_cur) - global.__repl_cursor);
    global.__repl_lines[global.__repl_line_idx] = _before;
    var _new_idx = global.__repl_line_idx + 1;
    array_insert(global.__repl_lines, _new_idx, _indent_str + _after);
    scm_repl__load_line(_new_idx);
    global.__repl_cursor = _indent_n;
}

/// Handle a key action.
function scm_repl__key(_which) {
    switch (_which) {
        case "left":
            if (global.__repl_cursor > 0) global.__repl_cursor--;
            break;
        case "right":
            if (global.__repl_cursor < string_length(global.__repl_buf)) global.__repl_cursor++;
            break;
        case "backspace":
            if (global.__repl_cursor > 0) {
                global.__repl_buf = scm_repl__str_delete_at(global.__repl_buf, global.__repl_cursor - 1);
                global.__repl_cursor--;
            } else if (global.__repl_line_idx > 0) {
                // Merge current line with previous
                scm_repl__sync_buf();
                var _prev = global.__repl_line_idx - 1;
                var _prev_text = global.__repl_lines[_prev];
                var _cur_text = global.__repl_lines[global.__repl_line_idx];
                global.__repl_lines[_prev] = _prev_text + _cur_text;
                array_delete(global.__repl_lines, global.__repl_line_idx, 1);
                scm_repl__load_line(_prev);
                global.__repl_cursor = string_length(_prev_text);
            }
            break;
        case "delete":
            if (global.__repl_cursor < string_length(global.__repl_buf)) {
                global.__repl_buf = scm_repl__str_delete_at(global.__repl_buf, global.__repl_cursor);
            }
            break;
        case "home":
            global.__repl_cursor = 0;
            break;
        case "end":
            global.__repl_cursor = string_length(global.__repl_buf);
            break;
        case "enter":
            scm_repl__submit();
            break;
        case "shift-enter":
            scm_repl__newline();
            break;
        case "up":
            if (scm_repl__is_multiline() && global.__repl_line_idx > 0) {
                scm_repl__sync_buf();
                scm_repl__load_line(global.__repl_line_idx - 1);
            } else {
                scm_repl__history_nav(1);
            }
            break;
        case "down":
            if (scm_repl__is_multiline() && global.__repl_line_idx < array_length(global.__repl_lines) - 1) {
                scm_repl__sync_buf();
                scm_repl__load_line(global.__repl_line_idx + 1);
            } else if (!scm_repl__is_multiline()) {
                scm_repl__history_nav(-1);
            }
            break;
    }
}

// ═══════════════════════════════════════════════════════════════════
//  Section 12: Key repeat
// ═══════════════════════════════════════════════════════════════════

/// Check if a repeating key should fire this frame.
/// Delegates to time-based TTY key repeat (frame-rate independent).
function scm_repl__check_key(_which) {
    var _vk;
    switch (_which) {
        case "left":  _vk = vk_left;      break;
        case "right": _vk = vk_right;     break;
        case "back":  _vk = vk_backspace; break;
        default: return false;
    }
    return scm_tty_key_tick(_vk);
}

/// Reset all key repeat state.
function scm_repl__reset_key_state() {
    scm_tty_reset_keys();
}

/// Map a base character to its Shift-modified equivalent (US/CN layout).
/// Returns the original character if no mapping exists.
function scm_repl__shift_char(_c) {
    switch (_c) {
        case "`": return "~";
        case "1": return "!";
        case "2": return "@";
        case "3": return "#";
        case "4": return "$";
        case "5": return "%";
        case "6": return "^";
        case "7": return "&";
        case "8": return "*";
        case "9": return "(";
        case "0": return ")";
        case "-": return "_";
        case "=": return "+";
        case "[": return "{";
        case "]": return "}";
        case "\\": return "|";
        case ";": return ":";
        case "'": return chr(34);
        case ",": return "<";
        case ".": return ">";
        case "/": return "?";
        default: return _c;
    }
}

/// Clear all keyboard state to prevent input leaking to the game.
function scm_repl__trap_keys() {
    keyboard_string = "";
    keyboard_lastkey = vk_nokey;
    keyboard_lastchar = "";
    io_clear();
}

// ═══════════════════════════════════════════════════════════════════
//  Section 12b: Tab completion
// ═══════════════════════════════════════════════════════════════════

/// Collect all binding names from an environment chain (includes parent scopes).
function scm_repl__env_names(_env) {
    var _names = [];
    var _seen = ds_map_create();
    while (_env != undefined) {
        var _keys = variable_struct_get_names(_env.bindings);
        for (var _i = 0; _i < array_length(_keys); _i++) {
            if (!ds_map_exists(_seen, _keys[_i])) {
                ds_map_set(_seen, _keys[_i], true);
                array_push(_names, _keys[_i]);
            }
        }
        _env = _env.parent;
    }
    ds_map_destroy(_seen);
    return _names;
}

/// Return the longest common prefix of two strings.
function scm_repl__common_prefix(_a, _b) {
    var _la = string_length(_a);
    var _lb = string_length(_b);
    var _n = min(_la, _lb);
    for (var _i = 1; _i <= _n; _i++) {
        if (string_char_at(_a, _i) != string_char_at(_b, _i)) {
            return string_copy(_a, 1, _i - 1);
        }
    }
    return string_copy(_a, 1, _n);
}

/// Tab-complete the symbol at cursor from environment bindings.
function scm_repl__tab_complete() {
    var _buf = global.__repl_buf;
    var _cur = global.__repl_cursor;
    if (_cur == 0) return;

    // Extract prefix: scan backwards from cursor to find word boundary
    var _start = _cur;
    while (_start > 0) {
        var _c = string_char_at(_buf, _start);
        if (_c == " " || _c == "(" || _c == ")" || _c == "\t"
            || _c == "'" || _c == "`" || _c == chr(34)) break;
        _start--;
    }
    var _prefix = string_copy(_buf, _start + 1, _cur - _start);
    if (_prefix == "") return;

    // Collect matching names from env
    if (!variable_global_exists("scm_env")) return;
    var _all_names = scm_repl__env_names(global.scm_env);
    var _matches = [];
    var _plen = string_length(_prefix);
    for (var _i = 0; _i < array_length(_all_names); _i++) {
        if (string_copy(_all_names[_i], 1, _plen) == _prefix) {
            array_push(_matches, _all_names[_i]);
        }
    }

    var _mn = array_length(_matches);
    if (_mn == 0) return;

    if (_mn == 1) {
        // Single match: complete in-place
        var _completion = string_copy(_matches[0], _plen + 1, string_length(_matches[0]) - _plen);
        global.__repl_buf = scm_repl__str_insert(_buf, _cur, _completion);
        global.__repl_cursor += string_length(_completion);
    } else {
        // Multiple matches: complete to longest common prefix
        var _common = _matches[0];
        for (var _i = 1; _i < _mn; _i++) {
            _common = scm_repl__common_prefix(_common, _matches[_i]);
        }
        if (string_length(_common) > _plen) {
            var _completion = string_copy(_common, _plen + 1, string_length(_common) - _plen);
            global.__repl_buf = scm_repl__str_insert(_buf, _cur, _completion);
            global.__repl_cursor += string_length(_completion);
        }
        // Show candidates with adaptive column layout
        // Find longest name to compute column width
        var _max_len = 0;
        for (var _i = 0; _i < _mn; _i++) {
            var _nl = string_length(_matches[_i]);
            if (_nl > _max_len) _max_len = _nl;
        }
        var _col_w = _max_len + 2; // 2-char gap between columns
        var _term_cols = scm_tty_cols(display_get_gui_width() - 32);
        var _cols = max(1, floor(_term_cols / _col_w));

        var _row = "";
        var _col = 0;
        var _shown = 0;
        for (var _i = 0; _i < _mn; _i++) {
            if (_shown >= 40) {
                if (_row != "") scm_repl__add_output(_row, global.__repl_c_comment);
                scm_repl__add_output("  ...(" + string(_mn) + " total)", global.__repl_c_comment);
                _row = "";
                _col = 0;
                break;
            }
            if (_col > 0) {
                // Pad previous entry to fixed column width
                var _pad_n = _col_w - string_length(_matches[_i - 1]);
                var _pad_s = "";
                for (var _p = 0; _p < _pad_n; _p++) _pad_s += " ";
                _row += _pad_s;
            }
            _row += _matches[_i];
            _col++;
            _shown++;
            if (_col >= _cols) {
                scm_repl__add_output(_row, global.__repl_c_comment);
                _row = "";
                _col = 0;
            }
        }
        if (_row != "") {
            scm_repl__add_output(_row, global.__repl_c_comment);
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
//  Section 12c: REPL commands (:help, :env, :clear)
// ═══════════════════════════════════════════════════════════════════

/// Execute a REPL meta-command (string starting with ":").
function scm_repl__exec_command(_cmd) {
    var _lower = string_lower(_cmd);

    if (_lower == ":help" || _lower == ":h" || _lower == ":?") {
        scm_repl__add_output("REPL Commands:", global.__repl_c_builtin);
        scm_repl__add_output("  :help           Show this help", global.__repl_c_comment);
        scm_repl__add_output("  :clear          Clear output", global.__repl_c_comment);
        scm_repl__add_output("  :env [prefix]   List env bindings (optionally filtered)", global.__repl_c_comment);
        scm_repl__add_output("  Ctrl+L          Clear output (shortcut)", global.__repl_c_comment);
        scm_repl__add_output("  Tab             Complete symbol at cursor", global.__repl_c_comment);
        scm_repl__add_output("", global.__repl_c_default);
        return;
    }

    if (_lower == ":clear" || _lower == ":cls") {
        scm_repl__clear_output();
        return;
    }

    if (_lower == ":env" || string_copy(_lower, 1, 5) == ":env ") {
        var _filter = "";
        if (string_length(_cmd) > 4) {
            _filter = string_copy(_cmd, 5, string_length(_cmd) - 4);
            // Trim leading spaces
            while (string_length(_filter) > 0 && string_char_at(_filter, 1) == " ") {
                _filter = string_copy(_filter, 2, string_length(_filter) - 1);
            }
        }
        if (!variable_global_exists("scm_env")) {
            scm_repl__add_output("(env not initialized)", global.__repl_c_error);
            return;
        }
        var _names = scm_repl__env_names(global.scm_env);
        var _filtered = [];
        var _flen = string_length(_filter);
        for (var _i = 0; _i < array_length(_names); _i++) {
            if (_flen == 0 || string_copy(_names[_i], 1, _flen) == _filter) {
                array_push(_filtered, _names[_i]);
            }
        }
        var _fn = array_length(_filtered);
        // Header (added first → highest index → visual top)
        var _hdr = string(_fn) + " binding(s)";
        if (_flen > 0) _hdr += " matching '" + _filter + "'";
        scm_repl__add_output(_hdr, global.__repl_c_comment);
        if (_fn == 0) return;
        // Display in wrapped lines, adaptive to terminal width
        var _term_cols = scm_tty_cols(display_get_gui_width() - 32);
        var _line = "";
        for (var _i = 0; _i < _fn; _i++) {
            if (_i > 0) _line += "  ";
            _line += _filtered[_i];
            if (string_length(_line) > _term_cols || _i == _fn - 1) {
                scm_repl__add_output(_line, global.__repl_c_default);
                _line = "";
            }
        }
        return;
    }

    scm_repl__add_output("Unknown command: " + _cmd + "  (try :help)", global.__repl_c_error);
}

// ═══════════════════════════════════════════════════════════════════
//  Section 13: Token cache for input display
// ═══════════════════════════════════════════════════════════════════

/// Get highlighted tokens for current input buffer (cached).
function scm_repl__get_input_tokens() {
    if (global.__repl_token_cache_buf == global.__repl_buf) {
        return global.__repl_token_cache_tok;
    }
    var _tokens = scm_repl__highlight(scm_repl__tokenize(global.__repl_buf));
    global.__repl_token_cache_buf = global.__repl_buf;
    global.__repl_token_cache_tok = _tokens;
    return _tokens;
}

// ═══════════════════════════════════════════════════════════════════
//  Section 14: Draw functions
// ═══════════════════════════════════════════════════════════════════

/// Draw colored text (uniform color, 4 corners). Delegates to TTY.
function scm_repl__draw_text(_x, _y, _text, _color, _alpha) {
    scm_tty_draw_text(_x, _y, _text, _color, _alpha);
}

/// Draw output entries with wrapping and scroll support. Delegates to TTY.
function scm_repl__draw_output(_x0, _start_y, _max_w, _max_h) {
    scm_tty_draw_output(_x0, _start_y, _max_w, _max_h);
}

/// Draw input line with syntax highlighting and matched paren.
function scm_repl__draw_input(_x0, _y) {
    var _prompt = (global.__repl_line_idx == 0) ? "> " : "... ";
    var _cw = scm_tty_char_w(); // monospace: exact char width

    // Draw prompt
    scm_repl__draw_text(_x0, _y, _prompt, global.__repl_c_prompt, 1.0);
    var _prompt_chars = string_length(_prompt);
    var _xx = _x0 + _prompt_chars * _cw;

    // Get highlighted tokens
    var _tokens = scm_repl__get_input_tokens();
    var _tn = array_length(_tokens);

    // Find matching paren
    var _match_pos = -1;
    if (global.__repl_cursor > 0) {
        _match_pos = scm_repl__match_paren(global.__repl_buf, global.__repl_cursor - 1);
    }

    // Draw tokens with optional match highlight
    var _char_pos = 0;
    for (var _i = 0; _i < _tn; _i++) {
        var _tok = _tokens[_i];
        var _color = _tok[0];
        var _text = _tok[1];
        var _tlen = string_length(_text);

        // Check if match_pos falls within this token
        if (_match_pos >= 0 && _match_pos >= _char_pos && _match_pos < _char_pos + _tlen) {
            // Split token around matched character
            var _offset = _match_pos - _char_pos;
            // Before part
            if (_offset > 0) {
                var _before = string_copy(_text, 1, _offset);
                scm_repl__draw_text(_xx, _y, _before, _color, 1.0);
                _xx += _offset * _cw;
            }
            // Matched character (gold)
            var _matched = string_char_at(_text, _offset + 1);
            scm_repl__draw_text(_xx, _y, _matched, global.__repl_c_match, 1.0);
            _xx += _cw;
            // After part
            var _after_start = _offset + 1;
            if (_after_start < _tlen) {
                var _after = string_copy(_text, _after_start + 1, _tlen - _after_start);
                scm_repl__draw_text(_xx, _y, _after, _color, 1.0);
                _xx += (_tlen - _after_start) * _cw;
            }
        } else {
            // Normal draw
            scm_repl__draw_text(_xx, _y, _text, _color, 1.0);
            _xx += _tlen * _cw;
        }

        _char_pos += _tlen;
    }
}

/// Draw blinking cursor.
function scm_repl__draw_cursor(_x0, _y) {
    var _prompt = (global.__repl_line_idx == 0) ? "> " : "... ";
    var _cw = scm_tty_char_w();
    var _cursor_x = _x0 + (string_length(_prompt) + global.__repl_cursor) * _cw;
    var _blink = abs(sin(current_time / 300));
    scm_repl__draw_text(_cursor_x - 1, _y, "|", global.__repl_c_white, _blink);
}

// ═══════════════════════════════════════════════════════════════════
//  Section 15: Step (keyboard handling)
// ═══════════════════════════════════════════════════════════════════

/// Process keyboard input. Called only when REPL is visible.
function scm_repl__step_input() {
    // Character input
    var _typed = keyboard_string;
    keyboard_string = "";
    if (string_length(_typed) > 0) {
        // When Shift is held, keyboard_string may return base chars
        // (e.g. "9" instead of "("). Remap through shift table.
        if (keyboard_check(vk_shift)) {
            var _remapped = "";
            for (var _k = 1; _k <= string_length(_typed); _k++) {
                var _c = string_char_at(_typed, _k);
                _remapped += scm_repl__shift_char(string_upper(_c));
            }
            _typed = _remapped;
        }
        scm_repl__type_chars(_typed);
        scm_tty_scroll_to_bottom();
    }

    // Key repeat keys (time-based via TTY layer)
    if (scm_repl__check_key("left"))  scm_repl__key("left");
    if (scm_repl__check_key("right")) scm_repl__key("right");
    if (scm_repl__check_key("back"))  scm_repl__key("backspace");

    // Non-repeat special keys
    if (keyboard_check_pressed(vk_delete)) scm_repl__key("delete");
    if (keyboard_check_pressed(vk_home))   scm_repl__key("home");
    if (keyboard_check_pressed(vk_end))    scm_repl__key("end");

    // Enter / Shift+Enter
    if (keyboard_check_pressed(vk_enter)) {
        if (keyboard_check(vk_shift)) {
            scm_repl__key("shift-enter");
        } else {
            scm_repl__key("enter");
            scm_tty_scroll_to_bottom();
        }
    }

    // History navigation
    if (keyboard_check_pressed(vk_up))   scm_repl__key("up");
    if (keyboard_check_pressed(vk_down)) scm_repl__key("down");

    // Ctrl+V paste
    if (keyboard_check(vk_control) && keyboard_check_pressed(ord("V"))) {
        if (clipboard_has_text()) {
            scm_repl__paste(clipboard_get_text());
        }
    }

    // Ctrl+L clear output
    if (keyboard_check(vk_control) && keyboard_check_pressed(ord("L"))) {
        scm_repl__clear_output();
    }

    // Tab completion
    if (keyboard_check_pressed(vk_tab)) {
        scm_repl__tab_complete();
    }

    // Scroll: PgUp / PgDn
    var _vp_rows = floor((display_get_gui_height() - 48) / scm_tty_line_h());
    scm_tty_handle_scroll_keys(_vp_rows);

    // Trap keys so game doesn't react
    scm_repl__trap_keys();
}

// ═══════════════════════════════════════════════════════════════════
//  Section 16: Eval dispatch (GML → Scheme → GML output)
// ═══════════════════════════════════════════════════════════════════

/// Evaluate user code and feed results back to the GML output array.
function scm_repl__do_eval(_code) {
    scm_output_clear();
    var _result;
    try {
        _result = scm_eval_program(_code, global.scm_env);
    } catch (_e) {
        _result = scm_err("GML exception: " + string(_e));
    }
    scm_output_flush();

    // Feed printed output lines
    var _out = scm_output_get();
    for (var _j = 0; _j < array_length(_out); _j++) {
        scm_repl__add_output(_out[_j], global.__repl_c_default);
    }

    // Feed eval result
    if (_result.t == SCM_ERR) {
        scm_repl__add_output(scm_display_str(_result), global.__repl_c_error);
    } else if (_result.t != SCM_VOID) {
        scm_repl__add_output(scm_write_str(_result), global.__repl_c_result);
    }
}

// ═══════════════════════════════════════════════════════════════════
//  Section 17: Initialization (keyword/builtin maps + state)
// ═══════════════════════════════════════════════════════════════════

/// Initialize keyword ds_map for O(1) lookup.
function scm_repl__init_keywords() {
    var _m = ds_map_create();
    var _kws = [
        "define", "lambda", "if", "cond", "case", "when", "unless",
        "let", "let*", "letrec", "begin", "do", "set!",
        "and", "or", "quote", "quasiquote", "unquote", "unquote-splicing",
        "define-syntax", "syntax-rules"
    ];
    for (var _i = 0; _i < array_length(_kws); _i++) {
        ds_map_set(_m, _kws[_i], true);
    }
    return _m;
}

/// Initialize builtin ds_map for O(1) lookup.
function scm_repl__init_builtins() {
    var _m = ds_map_create();
    var _bis = [
        "car", "cdr", "cons", "list", "null?", "pair?", "map", "filter",
        "foldl", "foldr", "for-each", "append", "reverse", "length",
        "apply", "not", "equal?", "eqv?", "eq?", "number?", "string?",
        "symbol?", "boolean?", "list?", "zero?", "positive?", "negative?",
        "display", "write", "print", "newline", "error",
        "+", "-", "*", "/", "=", "<", ">", "<=", ">=", "modulo",
        "abs", "min", "max", "floor", "ceiling", "round", "sqrt", "expt",
        "string-length", "string-ref", "string-append", "substring",
        "string-contains?", "string-split", "string-join",
        "string->number", "number->string",
        "assoc", "member", "find", "any", "every", "remove", "count",
        "take", "drop", "range", "iota", "make-list", "zip", "partition"
    ];
    for (var _i = 0; _i < array_length(_bis); _i++) {
        ds_map_set(_m, _bis[_i], true);
    }
    return _m;
}

// ═══════════════════════════════════════════════════════════════════
//  Section 18: Public API (callers — defined last)
// ═══════════════════════════════════════════════════════════════════

/// Create and initialize the REPL.
function scm_repl_create() {
    var _t0 = get_timer();

    // Lookup maps
    global.__repl_keywords = scm_repl__init_keywords();
    global.__repl_builtins = scm_repl__init_builtins();

    // Color palette (One Dark)
    global.__repl_c_keyword = make_colour_rgb(198, 120, 221);
    global.__repl_c_builtin = make_colour_rgb( 97, 175, 239);
    global.__repl_c_string  = make_colour_rgb(152, 195, 121);
    global.__repl_c_number  = make_colour_rgb(209, 154, 102);
    global.__repl_c_comment = make_colour_rgb( 92,  99, 112);
    global.__repl_c_paren   = make_colour_rgb(171, 178, 191);
    global.__repl_c_symbol  = make_colour_rgb(224, 108, 117);
    global.__repl_c_default = make_colour_rgb(171, 178, 191);
    global.__repl_c_error   = make_colour_rgb(224, 108, 117);
    global.__repl_c_prompt  = make_colour_rgb( 97, 175, 239);
    global.__repl_c_result  = make_colour_rgb(152, 195, 121);
    global.__repl_c_match   = make_colour_rgb(255, 215,   0);
    global.__repl_c_black   = c_black;
    global.__repl_c_white   = c_white;

    // State
    global.__repl_buf = "";
    global.__repl_cursor = 0;
    global.__repl_lines = [""];
    global.__repl_line_idx = 0;
    global.__repl_history = [];
    global.__repl_hist_idx = -1;
    global.__repl_hist_saved_lines = [""];
    global.__repl_hist_saved_line_idx = 0;
    global.__repl_eval_pending = "";
    global.__repl_token_cache_buf = "";
    global.__repl_token_cache_tok = [];
    // Load monospace font (monofur)
    var _font = font_add("monof55.ttf", 16, false, false, 32, 127);
    if (_font != -1) {
        global.__repl_font = _font;
        scm_trace("[scm-repl] font loaded: monof55.ttf");
    } else {
        global.__repl_font = -1;
        scm_trace("[scm-repl] font_add failed, using default font");
    }

    // Initialize TTY layer (metrics, output buffer, key repeat, scroll)
    scm_tty_init(global.__repl_font);

    // Visibility
    global.scm_repl_visible = false;

    // Welcome message
    scm_repl__add_output("", global.__repl_c_default);
    scm_repl__add_output("F1 toggle | Enter eval | Shift+Enter newline | Tab complete | :help commands", global.__repl_c_comment);
    scm_repl__add_output("Scheme REPL (gml_scheme) — native GML", global.__repl_c_comment);

    // Env readiness check
    if (variable_global_exists("scm_env")) {
        var _plus = scm_env_get(global.scm_env, "+");
        if (_plus != undefined) {
            scm_trace("[scm-repl] env check: OK (+ is bound)");
        } else {
            scm_trace("[scm-repl] env check: FAIL (+ is NOT bound!)");
            scm_repl__add_output("WARNING: scm_env not initialized — builtins missing", global.__repl_c_error);
        }
    } else {
        scm_trace("[scm-repl] env check: FAIL (global.scm_env missing!)");
        scm_repl__add_output("ERROR: global.scm_env missing — run scm_init()", global.__repl_c_error);
    }

    var _dt = (get_timer() - _t0) div 1000;
    scm_trace("[scm-repl] create: " + string(_dt) + "ms");
}

/// Destroy the REPL (cleanup ds_maps and TTY).
function scm_repl_destroy() {
    if (ds_exists(global.__repl_keywords, ds_type_map)) {
        ds_map_destroy(global.__repl_keywords);
    }
    if (ds_exists(global.__repl_builtins, ds_type_map)) {
        ds_map_destroy(global.__repl_builtins);
    }
    scm_tty_destroy();
}

/// Toggle REPL visibility. Called from KeyPress F1 event.
function scm_repl_toggle() {
    global.scm_repl_visible = !global.scm_repl_visible;
    if (global.scm_repl_visible) {
        scm_repl__reset_key_state();
    }
    // Tell the game's input systems (scr_keyboard_control, o_button_actionkey, etc.)
    // to skip processing while the REPL is open.
    global.consoleEnabled = global.scm_repl_visible;
    // Clear residual input so neither REPL nor game sees stale keys.
    io_clear();
    keyboard_string = "";
    scm_trace("[scm-repl] toggle: visible=" + string(global.scm_repl_visible));
}



/// Step: handle keyboard input when visible, dispatch eval if pending.
function scm_repl_step() {
    if (!global.scm_repl_visible) exit;

    scm_repl__step_input();

    // Check for pending eval
    if (global.__repl_eval_pending != "") {
        var _code = global.__repl_eval_pending;
        global.__repl_eval_pending = "";
        var _t0 = get_timer();
        scm_repl__do_eval(_code);
        var _dt = (get_timer() - _t0) div 1000;
        scm_trace("[scm-repl] eval: " + string(_dt) + "ms");
    }
}

/// Draw: render the REPL GUI when visible.
function scm_repl_draw() {
    if (!global.scm_repl_visible) exit;

    var _w = display_get_gui_width();
    var _h = display_get_gui_height();
    var _prev_font = draw_get_font();
    var _prev_alpha = draw_get_alpha();
    var _prev_color = draw_get_colour();

    draw_set_font(global.__repl_font);

    var _line_h = scm_tty_line_h();
    var _pad = 16;
    var _x0 = _pad;
    var _y_bottom = _h - _pad;
    var _max_w = _w - _pad * 2;

    // Background overlay
    draw_set_alpha(0.85);
    draw_rectangle_colour(0, 0, _w, _h,
        global.__repl_c_black, global.__repl_c_black,
        global.__repl_c_black, global.__repl_c_black, false);
    draw_set_alpha(1.0);

    // Draw all input lines bottom-up
    var _total_lines = array_length(global.__repl_lines);
    var _cur_idx = global.__repl_line_idx;
    for (var _li = _total_lines - 1; _li >= 0; _li--) {
        var _ly = _y_bottom - (_total_lines - 1 - _li) * _line_h;
        if (_li == _cur_idx) {
            // Current editing line: use draw_input (syntax + matched paren) + cursor
            scm_repl__draw_input(_x0, _ly);
            scm_repl__draw_cursor(_x0, _ly);
        } else {
            // Non-current line: syntax highlight only
            var _mprefix = (_li == 0) ? "> " : "... ";
            var _mtokens = scm_repl__highlight(scm_repl__tokenize(global.__repl_lines[_li]));
            var _cw = scm_tty_char_w();
            var _mxx = _x0;
            scm_repl__draw_text(_mxx, _ly, _mprefix, global.__repl_c_prompt, 1.0);
            _mxx += string_length(_mprefix) * _cw;
            for (var _mj = 0; _mj < array_length(_mtokens); _mj++) {
                var _mt = _mtokens[_mj];
                scm_repl__draw_text(_mxx, _ly, _mt[1], _mt[0], 1.0);
                _mxx += string_length(_mt[1]) * _cw;
            }
        }
    }

    // Output history: draw above input lines with wrapping + scroll
    var _output_y = _y_bottom - _total_lines * _line_h - 6;
    var _output_max_h = _output_y - _pad; // don't draw above top padding
    if (_output_max_h > 0) {
        scm_repl__draw_output(_x0, _output_y, _max_w, _output_max_h);
    }

    // Scroll indicator (when scrolled up)
    if (global.__tty_scroll > 0) {
        var _ind = "[scroll: +" + string(global.__tty_scroll) + " lines]";
        var _ind_w = string_width(_ind);
        scm_repl__draw_text(_w - _pad - _ind_w, _y_bottom, _ind, global.__repl_c_comment, 0.7);
    }

    // Restore draw state
    draw_set_font(_prev_font);
    draw_set_alpha(_prev_alpha);
    draw_set_colour(_prev_color);
}
