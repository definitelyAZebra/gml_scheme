// ═══════════════════════════════════════════════════════════════════
//  scm_tty.gml — Virtual Terminal Layer
// ═══════════════════════════════════════════════════════════════════
//  Provides terminal primitives for the Scheme REPL:
//    - Font metrics (cached, DPI-aware)
//    - Monospace text wrapping
//    - Output line buffer with per-entry visual-line accounting
//    - Scroll state (visual-line granularity)
//    - Time-based key repeat (frame-rate independent)
//    - Output rendering with wrapping + scroll
//
//  Depends on: nothing (standalone)
//  Used by:    scm_repl_shell.gml
// ═══════════════════════════════════════════════════════════════════

// ─── Initialization ─────────────────────────────────────────────

/// Initialize the TTY layer with a monospace font resource.
/// Must be called after font_add and before any other scm_tty_* call.
function scm_tty_init(_font) {
    global.__tty_font = _font;

    // Cache font metrics (monospace assumption)
    draw_set_font(_font);
    global.__tty_char_w = string_width("M");
    global.__tty_line_h = string_height("Ay|");

    // Output buffer: array of entries, newest at index 0
    //   type 0 (plain):  [0, color, text]
    //   type 1 (spans):  [1, [[color,text], ...], ""]
    global.__tty_output     = [];
    global.__tty_output_max = 500;

    // Scroll: offset in visual lines from bottom (0 = latest output visible)
    global.__tty_scroll = 0;

    // Key repeat: two ds_maps storing real values (ds_map can't store arrays)
    //   __tty_key_pressed: vk → timestamp of initial press (ms)
    //   __tty_key_fired:   vk → timestamp of last fire (ms)
    global.__tty_key_pressed = ds_map_create();
    global.__tty_key_fired   = ds_map_create();
}

/// Cleanup TTY resources.
function scm_tty_destroy() {
    if (ds_exists(global.__tty_key_pressed, ds_type_map)) {
        ds_map_destroy(global.__tty_key_pressed);
    }
    if (ds_exists(global.__tty_key_fired, ds_type_map)) {
        ds_map_destroy(global.__tty_key_fired);
    }
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

/// Add a single-color text line to the output buffer (newest first).
function scm_tty_emit(_text, _color) {
    array_insert(global.__tty_output, 0, [0, _color, _text]);
    scm_tty__trim();
}

/// Add a colored-spans line to the output buffer.
/// _spans = [[color_int, text_str], ...]
function scm_tty_emit_spans(_spans) {
    array_insert(global.__tty_output, 0, [1, _spans, ""]);
    scm_tty__trim();
}

/// Remove oldest entries beyond the max buffer size.
function scm_tty__trim() {
    while (array_length(global.__tty_output) > global.__tty_output_max) {
        array_pop(global.__tty_output);
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

// ─── Time-based Key Repeat ─────────────────────────────────────
//
//  Replaces frame-counting approach. Uses current_time (milliseconds).
//  Behavior: press → immediate fire. Hold 400ms → first repeat.
//  Then repeat every 35ms (~28 repeats/sec, frame-rate independent).

/// Check if key _vk should fire this frame.
/// Returns true on initial press and during repeat.
function scm_tty_key_tick(_vk) {
    if (!keyboard_check(_vk)) {
        // Key released: clean up state
        ds_map_delete(global.__tty_key_pressed, _vk);
        ds_map_delete(global.__tty_key_fired, _vk);
        return false;
    }

    var _now = current_time; // milliseconds since OS boot

    if (!ds_map_exists(global.__tty_key_pressed, _vk)) {
        // Initial press: fire immediately, record timestamps
        ds_map_set(global.__tty_key_pressed, _vk, _now);
        ds_map_set(global.__tty_key_fired, _vk, _now);
        return true;
    }

    var _pressed_at = ds_map_find_value(global.__tty_key_pressed, _vk);
    var _last_fire  = ds_map_find_value(global.__tty_key_fired, _vk);
    var _since_press = _now - _pressed_at;
    var _since_fire  = _now - _last_fire;

    // Initial delay: 400ms from first press before any repeat
    if (_since_press < 400) return false;

    // After initial delay: repeat every 35ms
    if (_since_fire >= 35) {
        ds_map_set(global.__tty_key_fired, _vk, _now);
        return true;
    }

    return false;
}

/// Reset all key repeat state (call on REPL toggle).
function scm_tty_reset_keys() {
    ds_map_clear(global.__tty_key_pressed);
    ds_map_clear(global.__tty_key_fired);
}

// ─── Rendering ──────────────────────────────────────────────────

/// Draw colored text (uniform color, 4 corners).
function scm_tty_draw_text(_x, _y, _text, _color, _alpha) {
    draw_text_colour(_x, _y, _text, _color, _color, _color, _color, _alpha);
}

/// Draw the output buffer with text wrapping and scroll support.
///
/// Draws bottom-up from (_x0, _y_bottom), wrapping long lines to _max_w.
/// Respects __tty_scroll (visual lines skipped from bottom).
/// Stops when drawing would exceed _max_h above _y_bottom.
///
/// _x0:       left edge pixel
/// _y_bottom: pixel Y of the bottommost output line baseline
/// _max_w:    available width in pixels (for wrapping)
/// _max_h:    available height in pixels (stop drawing beyond this)
function scm_tty_draw_output(_x0, _y_bottom, _max_w, _max_h) {
    var _cols = scm_tty_cols(_max_w);
    var _lh   = global.__tty_line_h;
    var _n    = array_length(global.__tty_output);
    var _skip = global.__tty_scroll; // visual lines to skip from bottom
    var _y    = _y_bottom;
    var _y_top = _y_bottom - _max_h; // don't draw above this

    for (var _i = 0; _i < _n; _i++) {
        var _entry = global.__tty_output[_i];
        var _etype = _entry[0];

        if (_etype == 0) {
            // ── Plain text line ──
            var _text  = _entry[2];
            var _color = _entry[1];
            var _wrapped = scm_tty_wrap_lines(_text, _cols);
            var _wn = array_length(_wrapped);

            // Draw wrapped sub-lines bottom-to-top
            // (last sub-line is logically bottommost)
            for (var _k = _wn - 1; _k >= 0; _k--) {
                if (_skip > 0) { _skip--; continue; }
                scm_tty_draw_text(_x0, _y, _wrapped[_k], _color, 0.9);
                _y -= _lh;
                if (_y < _y_top) return;
            }
        } else {
            // ── Spans line ──
            // Compute visual line count from total span text length
            var _spans = _entry[1];
            var _slen  = scm_tty__spans_len(_spans);
            var _vlines = scm_tty_wrap_count_n(_slen, _cols);

            if (_vlines <= 1) {
                // Short spans: fits in one visual line — draw inline
                if (_skip > 0) { _skip--; continue; }
                var _xx = _x0;
                var _sn = array_length(_spans);
                for (var _j = 0; _j < _sn; _j++) {
                    scm_tty_draw_text(_xx, _y, _spans[_j][1], _spans[_j][0], 0.9);
                    _xx += string_width(_spans[_j][1]);
                }
                _y -= _lh;
                if (_y < _y_top) return;
            } else {
                // Long spans: flatten to plain text for wrapping, lose per-span color.
                // (Acceptable trade-off: long input lines are rare.)
                var _flat = "";
                var _sn = array_length(_spans);
                var _fallback_color = _spans[0][0]; // use first span's color
                for (var _j = 0; _j < _sn; _j++) {
                    _flat += _spans[_j][1];
                }
                var _wrapped = scm_tty_wrap_lines(_flat, _cols);
                var _wn = array_length(_wrapped);
                for (var _k = _wn - 1; _k >= 0; _k--) {
                    if (_skip > 0) { _skip--; continue; }
                    scm_tty_draw_text(_x0, _y, _wrapped[_k], _fallback_color, 0.9);
                    _y -= _lh;
                    if (_y < _y_top) return;
                }
            }
        }
    }

    // Clamp scroll upper bound: don't scroll past all content
    // At this point we've iterated all entries. If there's still
    // _skip > 0, the user scrolled beyond content — clamp.
    if (_skip > 0) {
        global.__tty_scroll -= _skip;
        if (global.__tty_scroll < 0) global.__tty_scroll = 0;
    }
}
