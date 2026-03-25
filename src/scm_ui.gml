// ═══════════════════════════════════════════════════════════════════
//  scm_ui.gml — Lightweight draw primitives for REPL UI
// ═══════════════════════════════════════════════════════════════════
//  Thin layer over GML draw functions to reduce boilerplate:
//    - Draw state save/restore (font, alpha, color)
//    - Solid-color rect helpers (fill, stroke, panel)
//    - CJK-aware text rendering with font fallback
//    - Output buffer rendering with wrapping + scroll
//    - Popup positioning with screen-edge clamping
//    - Selectable list rendering
//
//  Depends on:  scm_tty.gml (for metrics, wrapping, buffer globals)
//  Used by:     scm_comp.gml, scm_repl_shell.gml
// ═══════════════════════════════════════════════════════════════════

// ─── Draw State Stack ───────────────────────────────────────────
//
//  GML has no RAII or try-finally in UMT context.
//  scm_ui_begin / scm_ui_end bracket a draw session,
//  saving and restoring font + alpha + color + halign + valign.
//  Supports nesting (array-based stack).

/// Initialize the UI layer. Call once during create.
function scm_ui_init() {
    global.__ui_state_stack = [];
}

/// Push current draw state and set the working font.
/// Must be paired with scm_ui_end().
function scm_ui_begin(_font) {
    array_push(global.__ui_state_stack, {
        font:   draw_get_font(),
        alpha:  draw_get_alpha(),
        color:  draw_get_colour(),
        halign: draw_get_halign(),
        valign: draw_get_valign(),
    });
    draw_set_font(_font);
}

/// Restore draw state saved by the most recent scm_ui_begin().
function scm_ui_end() {
    var _n = array_length(global.__ui_state_stack);
    if (_n == 0) return;
    var _s = global.__ui_state_stack[_n - 1];
    array_pop(global.__ui_state_stack);
    draw_set_font(_s.font);
    draw_set_alpha(_s.alpha);
    draw_set_colour(_s.color);
    draw_set_halign(_s.halign);
    draw_set_valign(_s.valign);
}

// ─── Rect Primitives ────────────────────────────────────────────

/// Solid-color filled rectangle.
/// Saves and restores alpha around the call.
function scm_ui_fill(_x1, _y1, _x2, _y2, _color, _alpha) {
    var _prev = draw_get_alpha();
    draw_set_alpha(_alpha);
    draw_rectangle_colour(_x1, _y1, _x2, _y2,
        _color, _color, _color, _color, false);
    draw_set_alpha(_prev);
}

/// Solid-color outlined rectangle (1px border).
function scm_ui_stroke(_x1, _y1, _x2, _y2, _color) {
    draw_rectangle_colour(_x1, _y1, _x2, _y2,
        _color, _color, _color, _color, true);
}

/// Filled rect + outline border (the most common combo).
function scm_ui_panel(_x1, _y1, _x2, _y2, _bg, _border) {
    scm_ui_fill(_x1, _y1, _x2, _y2, _bg, 1.0);
    scm_ui_stroke(_x1, _y1, _x2, _y2, _border);
}

// ─── Text Rendering ─────────────────────────────────────────────
//
//  CJK-aware text rendering with font fallback.
//  Splits mixed ASCII/CJK runs and draws each with the appropriate font.

/// Draw colored text with font fallback for non-ASCII (CJK) characters.
/// Returns total pixel width drawn (for callers that need to advance X).
function scm_ui_draw_text(_x, _y, _text, _color, _alpha) {
    var _len = string_length(_text);
    if (_len == 0) return 0;

    // Fast path: no fallback font — draw everything with primary
    if (global.__tty_font_cjk == -1) {
        draw_text_colour(_x, _y, _text, _color, _color, _color, _color, _alpha);
        return string_width(_text);
    }

    // Quick scan: any non-ASCII?
    var _has_cjk = false;
    for (var _i = 1; _i <= _len; _i++) {
        if (ord(string_char_at(_text, _i)) > 127) {
            _has_cjk = true;
            break;
        }
    }

    // Fast path: pure ASCII
    if (!_has_cjk) {
        draw_text_colour(_x, _y, _text, _color, _color, _color, _color, _alpha);
        return string_width(_text);
    }

    // Mixed: split into ASCII vs non-ASCII runs, draw each with its font
    var _xx = _x;
    var _run_start = 1;
    var _in_cjk = (ord(string_char_at(_text, 1)) > 127);

    for (var _i = 2; _i <= _len; _i++) {
        var _ch_cjk = (ord(string_char_at(_text, _i)) > 127);
        if (_ch_cjk != _in_cjk) {
            var _run = string_copy(_text, _run_start, _i - _run_start);
            draw_set_font(_in_cjk ? global.__tty_font_cjk : global.__tty_font);
            draw_text_colour(_xx, _y, _run, _color, _color, _color, _color, _alpha);
            _xx += string_width(_run);
            _run_start = _i;
            _in_cjk = _ch_cjk;
        }
    }

    // Flush final run
    var _run = string_copy(_text, _run_start, _len - _run_start + 1);
    draw_set_font(_in_cjk ? global.__tty_font_cjk : global.__tty_font);
    draw_text_colour(_xx, _y, _run, _color, _color, _color, _color, _alpha);
    _xx += string_width(_run);

    // Restore primary font
    draw_set_font(global.__tty_font);
    return _xx - _x;
}

/// Draw text with CJK fallback (full alpha). Returns pixel width drawn.
function scm_ui_text(_x, _y, _text, _color) {
    return scm_ui_draw_text(_x, _y, _text, _color, 1.0);
}

/// Draw dimmed text (alpha=0.7). Returns pixel width drawn.
function scm_ui_text_dim(_x, _y, _text, _color) {
    return scm_ui_draw_text(_x, _y, _text, _color, 0.7);
}

/// Draw text at arbitrary alpha. Returns pixel width drawn.
function scm_ui_text_alpha(_x, _y, _text, _color, _alpha) {
    return scm_ui_draw_text(_x, _y, _text, _color, _alpha);
}

// ─── Output Rendering ───────────────────────────────────────────
//
//  Draw the TTY output buffer with text wrapping and scroll support.
//  Accesses scm_tty globals for buffer, metrics, and scroll state.

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
function scm_ui_draw_output(_x0, _y_bottom, _max_w, _max_h) {
    var _cols = scm_tty_cols(_max_w);
    var _lh   = global.__tty_line_h;
    var _n    = array_length(global.__tty_output);
    var _skip = global.__tty_scroll;
    var _y    = _y_bottom;
    var _y_top = _y_bottom - _max_h;

    for (var _i = _n - 1; _i >= 0; _i--) {
        var _entry = global.__tty_output[_i];
        var _etype = _entry[0];

        if (_etype == 0) {
            // ── Plain text line ──
            var _text  = _entry[2];
            var _color = _entry[1];
            var _wrapped = scm_tty_wrap_lines(_text, _cols);
            var _wn = array_length(_wrapped);

            for (var _k = _wn - 1; _k >= 0; _k--) {
                if (_skip > 0) { _skip--; continue; }
                scm_ui_draw_text(_x0, _y, _wrapped[_k], _color, 0.9);
                _y -= _lh;
                if (_y < _y_top) return;
            }
        } else {
            // ── Spans line ──
            var _spans = _entry[1];
            var _slen  = scm_tty__spans_len(_spans);
            var _vlines = scm_tty_wrap_count_n(_slen, _cols);

            if (_vlines <= 1) {
                if (_skip > 0) { _skip--; continue; }
                var _xx = _x0;
                var _sn = array_length(_spans);
                for (var _j = 0; _j < _sn; _j++) {
                    _xx += scm_ui_draw_text(_xx, _y, _spans[_j][1], _spans[_j][0], 0.9);
                }
                _y -= _lh;
                if (_y < _y_top) return;
            } else {
                // Long spans: flatten for wrapping (lose per-span color)
                var _flat = "";
                var _sn = array_length(_spans);
                var _fallback_color = _spans[0][0];
                for (var _j = 0; _j < _sn; _j++) {
                    _flat += _spans[_j][1];
                }
                var _wrapped = scm_tty_wrap_lines(_flat, _cols);
                var _wn = array_length(_wrapped);
                for (var _k = _wn - 1; _k >= 0; _k--) {
                    if (_skip > 0) { _skip--; continue; }
                    scm_ui_draw_text(_x0, _y, _wrapped[_k], _fallback_color, 0.9);
                    _y -= _lh;
                    if (_y < _y_top) return;
                }
            }
        }
    }

    // Clamp scroll: don't scroll past all content
    if (_skip > 0) {
        global.__tty_scroll -= _skip;
        if (global.__tty_scroll < 0) global.__tty_scroll = 0;
    }
}

// ─── Cursor ─────────────────────────────────────────────────────

/// Draw a blinking vertical bar cursor.
/// _blink_speed: lower = faster. 300 is a good default.
function scm_ui_cursor(_x, _y, _h, _color, _blink_speed) {
    var _blink = abs(sin(current_time / _blink_speed));
    var _prev = draw_get_alpha();
    draw_set_alpha(_blink);
    draw_set_colour(_color);
    draw_line_width(_x, _y + 1, _x, _y + _h - 2, 1);
    draw_set_alpha(_prev);
}

// ─── Popup Positioning ──────────────────────────────────────────

/// Compute popup position above an anchor point, clamped to screen.
/// Returns struct { x, y }.
///
/// _anchor_x, _anchor_y: where to anchor (typically start of word)
/// _w, _h: popup dimensions
/// _gap: vertical gap between anchor and popup bottom edge
function scm_ui_popup_pos(_anchor_x, _anchor_y, _w, _h, _gap) {
    var _px = _anchor_x;
    var _py = _anchor_y - _h - _gap;
    var _gw = display_get_gui_width();
    if (_px + _w > _gw - 8) _px = _gw - 8 - _w;
    if (_px < 8) _px = 8;
    if (_py < 8) _py = 8;
    return { x: _px, y: _py };
}

// ─── Selectable List ────────────────────────────────────────────
//
//  Generic paginated list with selection highlight.
//  The caller iterates rows and draws content using scm_ui_list_row().

/// Prepare a selectable list and draw its background + selection highlight.
/// Returns a context struct for use with scm_ui_list_row().
///
/// _x, _y:     top-left corner of the list area
/// _w:         width (pixels)
/// _row_h:     height per row (pixels)
/// _count:     total number of items
/// _sel:       selected index (0-based)
/// _page:      current page (0-based)
/// _per_page:  items per page
/// _colors:    struct { bg, bg_sel, border }
function scm_ui_list_begin(_x, _y, _w, _row_h, _count, _sel, _page, _per_page, _colors) {
    var _ps = _page * _per_page;
    var _pe = min(_ps + _per_page, _count);
    var _vis = _pe - _ps;

    // Panel background + border
    var _h = _vis * _row_h;
    scm_ui_panel(_x, _y, _x + _w, _y + _h, _colors.bg, _colors.border);

    // Selection highlight row
    if (_sel >= _ps && _sel < _pe) {
        var _sy = _y + (_sel - _ps) * _row_h;
        scm_ui_fill(_x + 2, _sy, _x + _w - 2, _sy + _row_h,
                    _colors.bg_sel, 0.9);
    }

    return {
        page_start: _ps,
        page_end:   _pe,
        lx: _x,
        ly: _y,
        lw: _w,
        row_h: _row_h,
        sel: _sel,
    };
}

/// Get the Y coordinate and selection state for row _i.
/// Returns struct { x, y, is_selected }.
function scm_ui_list_row(_ctx, _i) {
    return {
        x: _ctx.lx,
        y: _ctx.ly + (_i - _ctx.page_start) * _ctx.row_h,
        is_selected: (_i == _ctx.sel),
    };
}

/// Pager footer text: "[page/total (count) mode]".
/// Returns the formatted string. Caller draws it where they want.
function scm_ui_list_footer(_page, _total_pages, _count, _mode) {
    if (_total_pages > 1) {
        return "[" + string(_page + 1) + "/" + string(_total_pages)
             + " (" + string(_count) + ") " + _mode + "]";
    }
    return "[" + _mode + "]";
}
