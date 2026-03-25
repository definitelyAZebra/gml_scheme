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

/// Split a string by a one-character separator.  Returns an array of parts.
function scm_repl__string_split_char(_s, _sep) {
    var _res = [];
    var _cur = "";
    var _len = string_length(_s);
    for (var _i = 1; _i <= _len; _i++) {
        var _ch = string_char_at(_s, _i);
        if (_ch == _sep) {
            array_push(_res, _cur);
            _cur = "";
        } else {
            _cur += _ch;
        }
    }
    array_push(_res, _cur);
    return _res;
}

/// East-Asian display width: CJK ideographs count as 2 columns, rest as 1.
/// Used for cursor positioning on the monospace input line.
function scm_repl__display_width(_s) {
    var _w = 0;
    var _len = string_length(_s);
    for (var _i = 1; _i <= _len; _i++) {
        var _code = ord(string_char_at(_s, _i));
        // CJK Unified Ideographs (U+4E00..U+9FFF) → fullwidth
        if (_code >= 0x4E00 && _code <= 0x9FFF) {
            _w += 2;
        } else {
            _w += 1;
        }
    }
    return _w;
}

/// Display width of the first _n characters of a string.
function scm_repl__display_width_n(_s, _n) {
    var _w = 0;
    var _len = min(_n, string_length(_s));
    for (var _i = 1; _i <= _len; _i++) {
        var _code = ord(string_char_at(_s, _i));
        if (_code >= 0x4E00 && _code <= 0x9FFF) {
            _w += 2;
        } else {
            _w += 1;
        }
    }
    return _w;
}

// ═══════════════════════════════════════════════════════════════════
//  Section 4: Cursor position mapping
// ═══════════════════════════════════════════════════════════════════

/// Compute the global cursor position (0-based) in the joined lines text.
/// Must be called after scm_repl__sync_buf().
function scm_repl__global_cursor_pos() {
    var _pos = 0;
    for (var _i = 0; _i < global.__repl_line_idx; _i++) {
        _pos += string_length(global.__repl_lines[_i]) + 1; // +1 for \n
    }
    _pos += global.__repl_cursor;
    return _pos;
}

/// Convert a 0-based position in joined text (with \n separators)
/// to [line_idx, char_offset_within_line]. Returns [-1, -1] if out of range.
function scm_repl__pos_to_line_offset(_pos) {
    var _n = array_length(global.__repl_lines);
    var _run = 0;
    for (var _i = 0; _i < _n; _i++) {
        var _len = string_length(global.__repl_lines[_i]);
        if (_pos >= _run && _pos < _run + _len) {
            return [_i, _pos - _run];
        }
        _run += _len + 1; // +1 for \n separator
    }
    return [-1, -1];
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
        case RTOK_MACRO:      return global.__repl_c_keyword; // macros highlighted like keywords (purple)
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
        var _tokens = scm_lex_tokenize(_line);
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
    global.__repl_hist_idx = -1;
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
    // Allow printable characters: ASCII (0x20..0x7E) + non-ASCII (>= 0x80)
    var _filtered = "";
    for (var _i = 1; _i <= string_length(_str); _i++) {
        var _code = ord(string_char_at(_str, _i));
        if ((_code >= 0x20 && _code <= 0x7E) || _code >= 0x80) {
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

    if (scm_sexpr_complete(_full)) {
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
    var _indent_n = scm_sexpr_auto_indent(_full);
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
/// Delegates to time-based input layer (frame-rate independent).
function scm_repl__check_key(_which) {
    var _vk;
    switch (_which) {
        case "left":   _vk = vk_left;      break;
        case "right":  _vk = vk_right;     break;
        case "up":     _vk = vk_up;        break;
        case "down":   _vk = vk_down;      break;
        case "back":   _vk = vk_backspace; break;
        case "delete": _vk = vk_delete;    break;
        default: return false;
    }
    return scm_input_key_tick(_vk);
}

/// Reset all key repeat state.
function scm_repl__reset_key_state() {
    scm_input_reset_keys();
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

/// Handle keyboard input when overlay is active.
/// All input goes to the overlay, not the REPL buffer.
function scm_repl__step_overlay_input() {
    // Consume keyboard_string
    var _typed = keyboard_string;
    keyboard_string = "";

    // Character input → append to overlay input
    if (string_length(_typed) > 0 && !keyboard_check(vk_control)) {
        if (keyboard_check(vk_shift)) {
            var _remapped = "";
            for (var _k = 1; _k <= string_length(_typed); _k++) {
                var _c = string_char_at(_typed, _k);
                if (ord(_c) <= 0x7E) {
                    _remapped += scm_repl__shift_char(string_upper(_c));
                } else {
                    _remapped += _c;
                }
            }
            _typed = _remapped;
        }
        // Filter to printable chars
        var _clean = "";
        for (var _k = 1; _k <= string_length(_typed); _k++) {
            var _o = ord(string_char_at(_typed, _k));
            if ((_o >= 0x20 && _o <= 0x7E) || _o >= 0x80) {
                _clean += string_char_at(_typed, _k);
            }
        }
        if (string_length(_clean) > 0) {
            scm_comp_overlay_set_input(global.__comp_ov_input + _clean);
        }
    }

    // Backspace → remove last char
    if (scm_repl__check_key("back")) {
        var _inp = global.__comp_ov_input;
        if (string_length(_inp) > 0) {
            scm_comp_overlay_set_input(string_copy(_inp, 1, string_length(_inp) - 1));
        }
    }

    // Navigation
    if (keyboard_check_pressed(vk_up))   scm_comp_overlay_nav(-1);
    if (keyboard_check_pressed(vk_down)) scm_comp_overlay_nav(1);
    if (keyboard_check_pressed(vk_pageup))   scm_comp_overlay_nav(-global.__comp_ov_per_page);
    if (keyboard_check_pressed(vk_pagedown)) scm_comp_overlay_nav(global.__comp_ov_per_page);

    // Enter → accept
    if (keyboard_check_pressed(vk_enter)) {
        var _result = scm_comp_overlay_accept();
        if (_result != undefined) {
            scm_repl__overlay_insert(_result);
        } else {
            scm_comp_overlay_close();
        }
    }

    // Escape → close
    if (keyboard_check_pressed(vk_escape)) {
        scm_comp_overlay_close();
    }

    // Tab → accept (same as Enter)
    if (keyboard_check_pressed(vk_tab)) {
        var _result = scm_comp_overlay_accept();
        if (_result != undefined) {
            scm_repl__overlay_insert(_result);
        } else {
            scm_comp_overlay_close();
        }
    }
}

/// Insert overlay result into the REPL buffer.
function scm_repl__overlay_insert(_result) {
    var _text = _result.text;

    // Auto-wrap in quotes if needed (bare arg with completer → pool result)
    if (_result.needs_quote_wrap) {
        _text = chr(34) + _text + chr(34);
    }

    // Replace from word_start to cursor
    var _ws = _result.word_start;
    var _buf = global.__repl_buf;
    var _before = string_copy(_buf, 1, _ws);
    var _after = string_copy(_buf, global.__repl_cursor + 1,
                             string_length(_buf) - global.__repl_cursor);

    // If we're inside a string context, replace from str_start to cursor
    // (word_start is already set correctly by overlay_open)
    global.__repl_buf = _before + _text + _after;
    global.__repl_cursor = _ws + string_length(_text);
}

/// Clear keyboard state to prevent input leaking to the game.
/// NOTE: io_clear() is NOT used here — it resets keyboard_check() hold state,
/// which breaks modifier keys (Ctrl, Shift) held across frames.
/// Game input is suppressed via global.consoleEnabled instead.
function scm_repl__trap_keys() {
    keyboard_string = "";
    keyboard_lastkey = vk_nokey;
    keyboard_lastchar = "";
}

// ═══════════════════════════════════════════════════════════════════
//  Section 12b: Tab completion (delegates to scm_comp.gml)
// ═══════════════════════════════════════════════════════════════════

/// Handle Tab press.
///
/// PREFIX mode (default, bash-style):
///   1. Collect prefix-matched candidates
///   2. Compute LCP (longest common prefix) of all matches
///   3. If LCP extends beyond current input → auto-complete to LCP, no popup
///   4. If LCP == prefix (fork point reached) → show popup
///   5. Tab again with popup open → accept selected
///
/// FUZZY mode:
///   1. Fuzzy-score all candidates, show popup
///   2. Tab again → accept selected
function scm_repl__tab_complete() {
    if (scm_comp_is_active()) {
        if (scm_comp_is_segment_mode()) {
            // Segment mode: drill if drillable, accept if leaf
            var _sel = global.__comp_sel;
            var _m = global.__comp_matches;
            if (_sel < array_length(_m)
                && variable_struct_exists(_m[_sel], "drillable")
                && _m[_sel].drillable) {
                scm_repl__drill_segment();
            } else {
                scm_repl__accept_completion();
            }
            return;
        }
        // Item mode: accept current selection
        scm_repl__accept_completion();
        return;
    }

    // Activate completion
    scm_comp_activate(global.__repl_buf, global.__repl_cursor);
    if (!scm_comp_is_active()) return;

    // Single match → auto-accept immediately
    if (scm_comp_count() == 1) {
        scm_repl__accept_completion();
        return;
    }

    // Try LCP extension, then maybe trie segment
    scm_repl__try_lcp_extend();
    // Popup stays open (item or segment mode)
}

/// Drill into a selected segment: extend prefix, re-activate completion.
function scm_repl__drill_segment() {
    var _seg_name = scm_comp_selected();
    if (_seg_name == "") { scm_comp_dismiss(); return; }

    // Replace current prefix with segment name in buffer
    var _buf = global.__repl_buf;
    var _cur = global.__repl_cursor;
    var _start = global.__comp_word_start;
    var _before = string_copy(_buf, 1, _start);
    var _after = string_copy(_buf, _cur + 1, string_length(_buf) - _cur);
    global.__repl_buf = _before + _seg_name + _after;
    global.__repl_cursor = _start + string_length(_seg_name);

    // Dismiss and re-activate with extended prefix
    scm_comp_dismiss();
    scm_comp_activate(global.__repl_buf, global.__repl_cursor);
    if (!scm_comp_is_active()) return;

    // Single match after drill → auto-accept
    if (scm_comp_count() == 1) {
        scm_repl__accept_completion();
        return;
    }

    // Try LCP extension, then maybe trie segment
    scm_repl__try_lcp_extend();
}

/// Try LCP extension: if LCP exceeds prefix, apply it and re-activate.
/// Then attempt trie segment drill-down if still at a fork point.
function scm_repl__try_lcp_extend() {
    var _lcp = scm_comp_lcp();
    var _prefix = global.__comp_prefix;
    if (string_length(_lcp) > string_length(_prefix)) {
        scm_repl__apply_partial(_lcp);
        scm_comp_activate(global.__repl_buf, global.__repl_cursor);
        if (!scm_comp_is_active()) return;
        if (scm_comp_count() == 1) {
            scm_repl__accept_completion();
            return;
        }
    }
    scm_comp__maybe_trie_segment();
}

/// Apply a partial completion (LCP) to the input buffer without dismissing.
function scm_repl__apply_partial(_text) {
    var _buf = global.__repl_buf;
    var _cur = global.__repl_cursor;
    var _start = global.__comp_word_start;

    var _before = string_copy(_buf, 1, _start);
    var _after = string_copy(_buf, _cur + 1, string_length(_buf) - _cur);
    global.__repl_buf = _before + _text + _after;
    global.__repl_cursor = _start + string_length(_text);

    // Update prefix and re-filter (narrow the candidate list)
    global.__comp_prefix = _text;
    scm_comp_update(global.__repl_buf, global.__repl_cursor);
    // Dismiss popup — user can Tab again to see the fork
    scm_comp_dismiss();
}

/// Accept the currently selected completion into the input buffer.
function scm_repl__accept_completion() {
    var _sel = scm_comp_selected();
    if (_sel == "") { scm_comp_dismiss(); return; }

    var _buf = global.__repl_buf;
    var _cur = global.__repl_cursor;
    var _start = global.__comp_word_start;

    // Replace prefix with full selected name
    var _before = string_copy(_buf, 1, _start);
    var _after = string_copy(_buf, _cur + 1, string_length(_buf) - _cur);
    global.__repl_buf = _before + _sel + _after;
    global.__repl_cursor = _start + string_length(_sel);

    scm_comp_dismiss();
}

// ═══════════════════════════════════════════════════════════════════
//  Section 12c: REPL commands (:help, :env, :clear)
// ═══════════════════════════════════════════════════════════════════

/// Execute a REPL meta-command (string starting with ":").
function scm_repl__exec_command(_cmd) {
    var _lower = string_lower(_cmd);

    if (_lower == ":help" || _lower == ":h" || _lower == ":?") {
        scm_repl__add_output(scm_repl__str("help_header"), global.__repl_c_builtin);
        scm_repl__add_output(scm_repl__str("help_cmd_help"), global.__repl_c_comment);
        scm_repl__add_output(scm_repl__str("help_cmd_help_fn"), global.__repl_c_comment);
        scm_repl__add_output(scm_repl__str("help_cmd_clear"), global.__repl_c_comment);
        scm_repl__add_output(scm_repl__str("help_cmd_env"), global.__repl_c_comment);
        scm_repl__add_output(scm_repl__str("help_cmd_load"), global.__repl_c_comment);
        scm_repl__add_output(scm_repl__str("help_cmd_ctrl_l"), global.__repl_c_comment);
        scm_repl__add_output(scm_repl__str("help_cmd_ctrl_c"), global.__repl_c_comment);
        scm_repl__add_output(scm_repl__str("help_cmd_ctrl_ae"), global.__repl_c_comment);
        scm_repl__add_output(scm_repl__str("help_cmd_tab"), global.__repl_c_comment);
        scm_repl__add_output("", global.__repl_c_default);
        return;
    }

    // :help <name> — look up function help
    if (string_copy(_lower, 1, 6) == ":help " || string_copy(_lower, 1, 3) == ":h ") {
        var _prefix_len = (string_copy(_lower, 1, 6) == ":help ") ? 6 : 3;
        var _topic = string_copy(_cmd, _prefix_len + 1, string_length(_cmd) - _prefix_len);
        // Trim leading spaces
        while (string_length(_topic) > 0 && string_char_at(_topic, 1) == " ") {
            _topic = string_copy(_topic, 2, string_length(_topic) - 1);
        }
        // Trim trailing spaces
        while (string_length(_topic) > 0 && string_char_at(_topic, string_length(_topic)) == " ") {
            _topic = string_copy(_topic, 1, string_length(_topic) - 1);
        }
        if (_topic == "") {
            // Empty topic — show general help instead
            scm_repl__exec_command(":help");
            return;
        }
        if (ds_map_exists(global.__repl_help, _topic)) {
            var _text = ds_map_find_value(global.__repl_help, _topic);
            // Split by \n and output each line
            var _lines = scm_repl__string_split_char(_text, "\n");
            // First line = signature (highlighted as builtin)
            if (array_length(_lines) > 0) {
                scm_repl__add_output(_lines[0], global.__repl_c_builtin);
            }
            // Remaining lines = description + example
            for (var _i = 1; _i < array_length(_lines); _i++) {
                var _c = (string_copy(_lines[_i], 1, 2) == "  ")
                    ? global.__repl_c_string   // indented = example → green
                    : global.__repl_c_default;  // description → default color
                scm_repl__add_output(_lines[_i], _c);
            }
        } else {
            scm_repl__add_output(
                string_replace(scm_repl__str("help_not_found"), "{0}", _topic),
                global.__repl_c_error
            );
        }
        return;
    }

    if (_lower == ":clear" || _lower == ":cls") {
        scm_repl__clear_output();
        return;
    }

    // :load path — evaluate a Scheme file
    if (string_copy(_lower, 1, 6) == ":load ") {
        var _path = string_copy(_cmd, 7, string_length(_cmd) - 6);
        // Trim whitespace
        while (string_length(_path) > 0 && string_char_at(_path, 1) == " ") {
            _path = string_copy(_path, 2, string_length(_path) - 1);
        }
        while (string_length(_path) > 0 && string_char_at(_path, string_length(_path)) == " ") {
            _path = string_copy(_path, 1, string_length(_path) - 1);
        }
        // Strip surrounding quotes if present (handles paths with spaces)
        if (string_length(_path) >= 2
            && string_char_at(_path, 1) == chr(34)
            && string_char_at(_path, string_length(_path)) == chr(34)) {
            _path = string_copy(_path, 2, string_length(_path) - 2);
        }
        if (_path == "") {
            scm_repl__add_output(scm_repl__str("load_usage"), global.__repl_c_error);
            return;
        }
        scm_repl__add_output(
            string_replace(scm_repl__str("load_loading"), "{0}", _path),
            global.__repl_c_comment
        );
        scm_output_clear();
        var _result;
        try {
            _result = scm_eval_file(_path);
        } catch (_e) {
            _result = scm_err("GML exception: " + scm__exception_msg(_e));
        }
        scm_output_flush();
        var _out = scm_output_get();
        for (var _j = 0; _j < array_length(_out); _j++) {
            scm_repl__add_output(_out[_j], global.__repl_c_default);
        }
        if (_result.t == SCM_ERR) {
            var _err_str = scm_display_str(_result);
            var _err_lines = scm_repl__string_split_char(_err_str, "\n");
            for (var _j = 0; _j < array_length(_err_lines); _j++) {
                scm_repl__add_output(_err_lines[_j], global.__repl_c_error);
            }
        } else if (_result.t != SCM_VOID) {
            scm_repl__add_output(scm_inspect_str(_result), global.__repl_c_result);
        }
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
        var _filter_lower = string_lower(_filter);
        for (var _i = 0; _i < array_length(_names); _i++) {
            if (_flen == 0) {
                // No filter: skip gml:* to reduce noise
                if (string_copy(_names[_i], 1, 4) != "gml:")
                    array_push(_filtered, _names[_i]);
            } else {
                // Substring match (case-insensitive)
                if (string_pos(_filter_lower, string_lower(_names[_i])) > 0)
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

    scm_repl__add_output(
        string_replace(scm_repl__str("unknown_cmd"), "{0}", _cmd),
        global.__repl_c_error
    );
}

// ═══════════════════════════════════════════════════════════════════
//  Section 13: Token cache for input display
// ═══════════════════════════════════════════════════════════════════

/// Get highlighted tokens for current input buffer (cached).
function scm_repl__get_input_tokens() {
    if (global.__repl_token_cache_buf == global.__repl_buf) {
        return global.__repl_token_cache_tok;
    }
    var _tokens = scm_repl__highlight(scm_lex_tokenize(global.__repl_buf));
    global.__repl_token_cache_buf = global.__repl_buf;
    global.__repl_token_cache_tok = _tokens;
    return _tokens;
}

// ═══════════════════════════════════════════════════════════════════
//  Section 14: Draw functions
// ═══════════════════════════════════════════════════════════════════

/// Draw colored text (uniform color). Delegates to UI layer.
function scm_repl__draw_text(_x, _y, _text, _color, _alpha) {
    scm_ui_text_alpha(_x, _y, _text, _color, _alpha);
}

/// Draw output entries with wrapping and scroll support. Delegates to UI layer.
function scm_repl__draw_output(_x0, _start_y, _max_w, _max_h) {
    scm_ui_draw_output(_x0, _start_y, _max_w, _max_h);
}

/// Draw a single line with syntax highlighting and optional matched paren.
/// _line_text: the line content (without prompt)
/// _line_idx: 0-based line index (for prompt selection)
/// _match_pos: char offset within this line to highlight, or -1
/// _x0, _y: draw position
function scm_repl__draw_line_highlighted(_x0, _y, _line_text, _line_idx, _match_pos) {
    var _prompt = (_line_idx == 0) ? "> " : "... ";
    var _cw = scm_tty_char_w();

    // Draw prompt
    scm_repl__draw_text(_x0, _y, _prompt, global.__repl_c_prompt, 1.0);
    var _xx = _x0 + string_length(_prompt) * _cw;

    // Tokenize and highlight
    var _tokens;
    if (_line_idx == global.__repl_line_idx) {
        _tokens = scm_repl__get_input_tokens();
    } else {
        _tokens = scm_repl__highlight(scm_lex_tokenize(_line_text));
    }
    var _tn = array_length(_tokens);

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
                _xx += scm_repl__display_width(_before) * _cw;
            }
            // Matched character (gold)
            var _matched = string_char_at(_text, _offset + 1);
            scm_repl__draw_text(_xx, _y, _matched, global.__repl_c_match, 1.0);
            _xx += scm_repl__display_width(_matched) * _cw;
            // After part
            var _after_start = _offset + 1;
            if (_after_start < _tlen) {
                var _after = string_copy(_text, _after_start + 1, _tlen - _after_start);
                scm_repl__draw_text(_xx, _y, _after, _color, 1.0);
                _xx += scm_repl__display_width(_after) * _cw;
            }
        } else {
            // Normal draw
            scm_repl__draw_text(_xx, _y, _text, _color, 1.0);
            _xx += scm_repl__display_width(_text) * _cw;
        }

        _char_pos += _tlen;
    }
}

/// Draw blinking cursor as a thin vertical line.
function scm_repl__draw_cursor(_x0, _y) {
    var _prompt = (global.__repl_line_idx == 0) ? "> " : "... ";
    var _cw = scm_tty_char_w();
    var _line_h = scm_tty_line_h();
    var _buf_before = string_copy(global.__repl_buf, 1, global.__repl_cursor);
    var _cursor_x = _x0 + (string_length(_prompt) + scm_repl__display_width(_buf_before)) * _cw;
    scm_ui_cursor(_cursor_x, _y, _line_h, global.__repl_c_white, 300);
}

// ═══════════════════════════════════════════════════════════════════
//  Section 15: Step (keyboard handling)
// ═══════════════════════════════════════════════════════════════════

/// Process keyboard input. Called only when REPL is visible.
function scm_repl__step_input() {
    // ── Overlay mode: intercept all input ───────────────────────
    if (scm_comp_overlay_is_active()) {
        scm_repl__step_overlay_input();
        scm_repl__trap_keys();
        return;
    }

    var _ctrl = keyboard_check(vk_control);
    var _popup = scm_comp_is_active();

    // Character input.
    // Consume keyboard_string every frame to prevent accumulation.
    // Only insert characters when Ctrl is NOT held (Ctrl+key = shortcut).
    var _typed = keyboard_string;
    keyboard_string = "";
    if (!_ctrl && string_length(_typed) > 0) {
        // When Shift is held, keyboard_string may return base chars
        // (e.g. "9" instead of "("). Remap through shift table.
        // Skip remap for non-ASCII chars (IME input arrives with shift state).
        if (keyboard_check(vk_shift)) {
            var _remapped = "";
            for (var _k = 1; _k <= string_length(_typed); _k++) {
                var _c = string_char_at(_typed, _k);
                if (ord(_c) <= 0x7E) {
                    _remapped += scm_repl__shift_char(string_upper(_c));
                } else {
                    _remapped += _c;
                }
            }
            _typed = _remapped;
        }
        scm_repl__type_chars(_typed);
        scm_tty_scroll_to_bottom();
        // Update popup filter as user types
        if (_popup) {
            if (global.__comp_segment_mode) {
                scm_comp_dismiss();
            } else {
                scm_comp_update(global.__repl_buf, global.__repl_cursor);
            }
        }
    }

    // Key repeat keys (time-based via TTY layer)
    if (scm_repl__check_key("left"))  { scm_repl__key("left");  if (_popup) scm_comp_dismiss(); }
    if (scm_repl__check_key("right")) { scm_repl__key("right"); if (_popup) scm_comp_dismiss(); }
    if (scm_repl__check_key("back")) {
        scm_repl__key("backspace");
        if (_popup) {
            if (global.__comp_segment_mode) {
                scm_comp_dismiss();
            } else {
                scm_comp_update(global.__repl_buf, global.__repl_cursor);
            }
        }
    }
    if (scm_repl__check_key("delete")) {
        scm_repl__key("delete");
        if (_popup) {
            if (global.__comp_segment_mode) {
                scm_comp_dismiss();
            } else {
                scm_comp_update(global.__repl_buf, global.__repl_cursor);
            }
        }
    }

    // Non-repeat special keys
    if (keyboard_check_pressed(vk_home)) { scm_repl__key("home"); if (_popup) scm_comp_dismiss(); }
    if (keyboard_check_pressed(vk_end))  { scm_repl__key("end");  if (_popup) scm_comp_dismiss(); }

    // Escape — dismiss popup (or could be used for other things later)
    if (keyboard_check_pressed(vk_escape)) {
        if (_popup) scm_comp_dismiss();
    }

    // Enter / Shift+Enter
    if (keyboard_check_pressed(vk_enter)) {
        if (_popup) {
            if (global.__comp_segment_mode) {
                // Segment mode: drill (same as Tab)
                scm_repl__drill_segment();
            } else {
                // Item mode: accept selected completion
                scm_repl__accept_completion();
            }
        } else if (keyboard_check(vk_shift)) {
            scm_repl__key("shift-enter");
        } else {
            scm_repl__key("enter");
            scm_tty_scroll_to_bottom();
        }
    }

    // Up / Down — popup navigation or history (with key repeat)
    if (scm_repl__check_key("up")) {
        if (_popup) scm_comp_prev();
        else scm_repl__key("up");
    }
    if (scm_repl__check_key("down")) {
        if (_popup) scm_comp_next();
        else scm_repl__key("down");
    }

    // ── Ctrl shortcuts ──
    if (_ctrl) {
        if (keyboard_check_pressed(ord("V"))) {
            if (clipboard_has_text()) {
                scm_repl__paste(clipboard_get_text());
                scm_tty_scroll_to_bottom();
                if (_popup) scm_comp_dismiss();
            }
        }
        if (keyboard_check_pressed(ord("L"))) {
            scm_repl__clear_output();
            if (_popup) scm_comp_dismiss();
        }
        if (keyboard_check_pressed(ord("C"))) {
            var _cur = scm_repl__join_lines();
            if (_cur != "") {
                scm_repl__add_output("> " + _cur + "^C", global.__repl_c_comment);
            }
            scm_repl__reset_input();
            if (_popup) scm_comp_dismiss();
        }
        if (keyboard_check_pressed(ord("A"))) {
            global.__repl_cursor = 0;
            if (_popup) scm_comp_dismiss();
        }
        if (keyboard_check_pressed(ord("E"))) {
            global.__repl_cursor = string_length(global.__repl_buf);
            if (_popup) scm_comp_dismiss();
        }
    }

    // Tab completion
    if (keyboard_check_pressed(vk_tab) && !_ctrl) {
        scm_repl__tab_complete();
    }
    // F3: open overlay search
    if (keyboard_check_pressed(vk_f3)) {
        scm_comp_overlay_open(global.__repl_buf, global.__repl_cursor);
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
        _result = scm_err("GML exception: " + scm__exception_msg(_e));
    }
    scm_output_flush();

    // Feed printed output lines
    var _out = scm_output_get();
    for (var _j = 0; _j < array_length(_out); _j++) {
        scm_repl__add_output(_out[_j], global.__repl_c_default);
    }

    // Feed eval result
    if (_result.t == SCM_ERR) {
        // Error message may contain newlines (e.g. multi-line GML exception info).
        // Split and display each line separately for readability.
        var _err_str = scm_display_str(_result);
        var _err_lines = scm_repl__string_split_char(_err_str, "\n");
        for (var _j = 0; _j < array_length(_err_lines); _j++) {
            scm_repl__add_output(_err_lines[_j], global.__repl_c_error);
        }
    } else if (_result.t != SCM_VOID) {
        scm_repl__add_output(scm_inspect_str(_result), global.__repl_c_result);
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
        "define-syntax", "syntax-rules", "define-macro"
    ];
    for (var _i = 0; _i < array_length(_kws); _i++) {
        ds_map_set(_m, _kws[_i], true);
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
    global.__repl_help     = scm_repl__init_help();

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

    // Load CJK fallback font (Chinese: U+4E00..U+9FFF, ~21K glyphs)
    var _cjk = font_add("HanyiSentyYongleEncyclopedia-2020.ttf", 16, false, false, 0x4E00, 0x9FFF);
    if (_cjk != -1) {
        global.__repl_font_cjk = _cjk;
        scm_trace("[scm-repl] CJK fallback font loaded");
    } else {
        global.__repl_font_cjk = -1;
        scm_trace("[scm-repl] CJK font not found, Chinese text will not render");
    }

    // Initialize input layer (key repeat)
    scm_input_init();

    // Initialize TTY layer (metrics, output buffer, scroll)
    scm_tty_init(global.__repl_font, global.__repl_font_cjk);

    // Initialize UI draw primitives (state stack, text rendering)
    scm_ui_init();

    // Initialize completion engine (provider registry + popup state)
    scm_comp_init();

    // Load string-context completion configuration (asset pools, completers)
    scm_comp__load_init();

    // Visibility
    global.scm_repl_visible = false;

    // Welcome message — crystal shard ASCII art
    //   Visual (top to bottom):
    //       /\
    //      /  \    gml_scheme
    //      \  /    Stoneshard Scheme REPL
    //       \/
    //              :help | F1 toggle | Tab complete
    scm_repl__add_output("",                                                      global.__repl_c_default);
    scm_repl__add_output("       /\\",                                            global.__repl_c_keyword);
    scm_repl__add_output_spans([[global.__repl_c_keyword, "      /  \\    "],
                                [global.__repl_c_builtin, "gml_scheme"]]);
    scm_repl__add_output_spans([[global.__repl_c_keyword, "      \\  /    "],
                                [global.__repl_c_default, "Stoneshard Scheme REPL"]]);
    scm_repl__add_output("       \\/",                                            global.__repl_c_keyword);
    scm_repl__add_output("",                                                      global.__repl_c_default);
    scm_repl__add_output("  :help commands | F1 toggle | Tab complete | Ctrl+L clear", global.__repl_c_comment);

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
    scm_input_destroy();
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

    scm_ui_begin(global.__repl_font);

    var _line_h = scm_tty_line_h();
    var _pad = 16;
    var _x0 = _pad;
    var _y_bottom = _h - _pad - _line_h;
    var _max_w = _w - _pad * 2;

    // Background overlay
    scm_ui_fill(0, 0, _w, _h, global.__repl_c_black, 0.85);

    // Cross-line bracket matching: compute match once for all lines
    scm_repl__sync_buf();
    var _full = scm_repl__join_lines();
    var _gpos = scm_repl__global_cursor_pos();
    var _match_line = -1;
    var _match_char = -1;
    if (_gpos > 0) {
        var _mpos = scm_sexpr_match_paren(_full, _gpos - 1);
        if (_mpos >= 0) {
            var _ml = scm_repl__pos_to_line_offset(_mpos);
            _match_line = _ml[0];
            _match_char = _ml[1];
        }
    }

    // Draw all input lines bottom-up
    var _total_lines = array_length(global.__repl_lines);
    var _cur_idx = global.__repl_line_idx;
    for (var _li = _total_lines - 1; _li >= 0; _li--) {
        var _ly = _y_bottom - (_total_lines - 1 - _li) * _line_h;
        var _li_match = (_li == _match_line) ? _match_char : -1;
        scm_repl__draw_line_highlighted(_x0, _ly, global.__repl_lines[_li], _li, _li_match);
        if (_li == _cur_idx) {
            scm_repl__draw_cursor(_x0, _ly);
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

    // Completion popup — drawn last so it renders on top of everything
    if (scm_comp_is_active()) {
        var _cur_ly = _y_bottom - (_total_lines - 1 - _cur_idx) * _line_h;
        var _prompt_w = (global.__repl_line_idx == 0) ? 2 : 4;
        var _cw = scm_tty_char_w();
        var _word_x = _x0 + (_prompt_w + scm_repl__display_width(
            string_copy(global.__repl_buf, 1, global.__comp_word_start))) * _cw;
        scm_comp_draw_popup(_word_x, _cur_ly, _cw, _line_h, {
            bg:       global.__repl_c_black,
            bg_sel:   make_colour_rgb(40, 55, 90),
            text:     global.__repl_c_default,
            text_sel: global.__repl_c_white,
            text_dim: global.__repl_c_comment,
            border:   global.__repl_c_comment
        });
    }

    // Overlay (F3) — drawn on top of everything
    if (scm_comp_overlay_is_active()) {
        var _cw = scm_tty_char_w();
        scm_comp_overlay_draw(_cw, _line_h, {
            bg:       global.__repl_c_black,
            bg_sel:   make_colour_rgb(40, 55, 90),
            text:     global.__repl_c_default,
            text_sel: global.__repl_c_white,
            text_dim: global.__repl_c_comment,
            border:   global.__repl_c_comment
        });
    }

    // Restore draw state
    scm_ui_end();
}
