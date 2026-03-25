// ═══════════════════════════════════════════════════════════════════
//  scm_tty.gml — Virtual Terminal Layer
// ═══════════════════════════════════════════════════════════════════
//  Provides terminal data primitives for the Scheme REPL:
//    - Font metrics (cached, DPI-aware)
//    - Monospace text wrapping
//    - Output line buffer with per-entry visual-line accounting
//    - Scroll state (visual-line granularity)
//
//  Depends on: nothing (standalone)
//  Used by:    scm_ui.gml, scm_repl_shell.gml
// ═══════════════════════════════════════════════════════════════════

// ─── Initialization ─────────────────────────────────────────────

/// Initialize the TTY layer with a monospace font resource.
/// Must be called after font_add and before any other scm_tty_* call.
/// _font_cjk: fallback font for CJK characters, or -1 if unavailable.
function scm_tty_init(_font, _font_cjk) {
    global.__tty_font = _font;
    global.__tty_font_cjk = _font_cjk;

    // Cache font metrics (monospace assumption)
    draw_set_font(_font);
    global.__tty_char_w = string_width("M");
    global.__tty_line_h = string_height("Ay|");

    // Output buffer: array of entries, newest at index 0
    //   type 0 (plain):  [0, color, text]
    //   type 1 (spans):  [1, [[color,text], ...], ""]
    global.__tty_output     = [];
    global.__tty_output_max = 10000;

    // Scroll: offset in visual lines from bottom (0 = latest output visible)
    global.__tty_scroll = 0;

}

/// Cleanup TTY resources (reserved for future use).
function scm_tty_destroy() {
}

// ─── Metrics ────────────────────────────────────────────────────

/// Cached monospace character width (pixels).
function scm_tty_char_w() {
    return global.__tty_char_w;
}

/// Cached line height (pixels).
function scm_tty_line_h() {
    return global.__tty_line_h;
}

/// How many monospace characters fit in _max_w pixels?
function scm_tty_cols(_max_w) {
    var _cw = global.__tty_char_w;
    if (_cw <= 0) return 80;
    return floor(_max_w / _cw);
}

// ─── Text Wrapping (character-count based, monospace) ───────────

/// How many visual lines does _text occupy at _cols columns?
/// Returns at least 1 (empty string = 1 blank line).
function scm_tty_wrap_count(_text, _cols) {
    if (_cols <= 0) return 1;
    var _len = string_length(_text);
    if (_len <= _cols) return 1;
    return ceil(_len / _cols);
}

/// Like wrap_count but takes a raw character count instead of a string.
function scm_tty_wrap_count_n(_len, _cols) {
    if (_cols <= 0 || _len <= _cols) return 1;
    return ceil(_len / _cols);
}

/// Split _text into an array of wrapped line strings, each <= _cols chars.
function scm_tty_wrap_lines(_text, _cols) {
    var _len = string_length(_text);
    if (_len <= _cols) return [_text];

    var _result = [];
    var _pos = 1; // GML strings are 1-indexed
    while (_pos <= _len) {
        var _chunk = min(_cols, _len - _pos + 1);
        array_push(_result, string_copy(_text, _pos, _chunk));
        _pos += _chunk;
    }
    return _result;
}

/// Compute total text length from a spans array [[color,text], ...].
function scm_tty__spans_len(_spans) {
    var _total = 0;
    var _n = array_length(_spans);
    for (var _i = 0; _i < _n; _i++) {
        _total += string_length(_spans[_i][1]);
    }
    return _total;
}

// ─── Output Buffer ──────────────────────────────────────────────

/// Add a single-color text line to the output buffer (newest at end).
function scm_tty_emit(_text, _color) {
    array_push(global.__tty_output, [0, _color, _text]);
    scm_tty__trim();
}

/// Add a colored-spans line to the output buffer.
/// _spans = [[color_int, text_str], ...]
function scm_tty_emit_spans(_spans) {
    array_push(global.__tty_output, [1, _spans, ""]);
    scm_tty__trim();
}

/// Remove oldest entries (at the front) beyond the max buffer size.
function scm_tty__trim() {
    var _excess = array_length(global.__tty_output) - global.__tty_output_max;
    if (_excess > 0) {
        array_delete(global.__tty_output, 0, _excess);
    }
}

/// Clear all output and reset scroll.
function scm_tty_clear() {
    global.__tty_output = [];
    global.__tty_scroll = 0;
}

/// Return current output entry count.
function scm_tty_output_count() {
    return array_length(global.__tty_output);
}

// ─── Scroll ─────────────────────────────────────────────────────

/// Scroll by _delta visual lines. Positive = scroll up (see older).
function scm_tty_scroll(_delta) {
    global.__tty_scroll = max(0, global.__tty_scroll + _delta);
    // Upper bound is clamped during draw when total visual lines are known.
}

/// Snap scroll to bottom (show latest output).
function scm_tty_scroll_to_bottom() {
    global.__tty_scroll = 0;
}

/// Handle PgUp/PgDn input for scrolling.
/// Call this during step, BEFORE trap_keys.
/// _viewport_rows: how many visual lines fit in the output area.
function scm_tty_handle_scroll_keys(_viewport_rows) {
    if (keyboard_check_pressed(vk_pageup)) {
        scm_tty_scroll(_viewport_rows);
    }
    if (keyboard_check_pressed(vk_pagedown)) {
        scm_tty_scroll(-_viewport_rows);
    }
}


