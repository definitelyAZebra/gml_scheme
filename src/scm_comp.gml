/// scm_comp.gml — Completion engine (source system + popup state machine)
///
/// Two completion surfaces:
///   INLINE POPUP (Tab-activated, bash-style):
///     Tab → prefix-filter → auto-complete to LCP (longest common prefix)
///     → if LCP == prefix (fork point), show popup
///     Ideal for exploring unknown asset names.
///
///   OVERLAY (F3-activated, fuzzy search):
///     F3 → full-screen overlay with fuzzy multi-token search
///     Searches env bindings and/or dict candidates (from registered completers)
///     Ideal for jumping to a known-but-inexact name.
///
/// Architecture:
///   Sources (env bindings, dicts)
///       ↓
///   detect_ctx() → { string | arg | none }
///       ↓
///   collect candidates → filter/score
///       ↓
///   ┌──────────────────────┐
///   │ matches[]             │
///   │ page / selected_idx   │
///   └──────────────────────┘
///       ↓
///   draw_popup() / overlay_draw() each frame
///       ↓
///   Tab/Enter → insert selected
///   Esc       → dismiss
///
/// Terminology:
///   dict       — flat name array loaded from JSON (via comp:make-dict)
///   index      — search index built from merged dicts: { names, trie, masks, count }
///   completer  — registered handler: { index, insert_fn, label }
///   source     — env bindings collector (scm_comp__prov_env_collect)
///   .sc        — fuzzy match score field (NOT ".score" — GML reserves `score`
///                as a built-in instance variable; using it on a struct triggers
///                "Variable <unknown_object>.score not set before reading it")
///
/// Depends on: scm_meta.gml (for namespace arrays)
/// Used by:    scm_repl_shell.gml

// ═══════════════════════════════════════════════════════════════════
//  Section 1: Fuzzy matching
// ═══════════════════════════════════════════════════════════════════

/// Compute 26-bit char presence bitmask for a string.
/// Bit i is set if letter chr(ord("a") + i) appears in the lowercased string.
/// Used for fast pre-filtering: (candidate_mask & query_mask) == query_mask
/// means the candidate contains all letters in the query.
function scm_comp__char_mask(_str) {
    var _mask = 0;
    var _len = string_length(_str);
    var _low = string_lower(_str);
    for (var _i = 1; _i <= _len; _i++) {
        var _c = ord(string_char_at(_low, _i));
        if (_c >= 97 && _c <= 122) { // 'a'=97, 'z'=122
            _mask |= (1 << (_c - 97));
        }
    }
    return _mask;
}

/// Split search string into space-separated tokens.
function scm_comp__split_tokens(_pattern) {
    var _tokens = [];
    var _plen = string_length(_pattern);
    var _start = 1;
    for (var _i = 1; _i <= _plen; _i++) {
        if (string_char_at(_pattern, _i) == " ") {
            if (_i > _start) {
                array_push(_tokens, string_copy(_pattern, _start, _i - _start));
            }
            _start = _i + 1;
        }
    }
    if (_start <= _plen) {
        array_push(_tokens, string_copy(_pattern, _start, _plen - _start + 1));
    }
    return _tokens;
}

/// Fuzzy score with pre-lowered text. Avoids repeated string_lower calls.
/// _tlow = string_lower(_text), _plow = string_lower(_pattern)
function scm_comp__fuzzy_score_pre(_text, _tlow, _pattern, _plow) {
    var _tlen = string_length(_text);
    var _plen = string_length(_pattern);
    if (_plen == 0) return 1;
    if (_plen > _tlen) return 0;

    if (string_copy(_text, 1, _plen) == _pattern) {
        return 1000 + (100 - min(_tlen, 100));
    }

    if (string_copy(_tlow, 1, _plen) == _plow) {
        return 900 + (100 - min(_tlen, 100));
    }

    var _pi = 1;
    var _score = 0;
    var _consecutive = 0;
    var _prev_match = -10;

    for (var _ti = 1; _ti <= _tlen; _ti++) {
        if (_pi > _plen) break;
        if (string_char_at(_tlow, _ti) == string_char_at(_plow, _pi)) {
            _pi++;
            if (_ti == _prev_match + 1) {
                _consecutive++;
                _score += 5 + _consecutive * 2;
            } else {
                _consecutive = 0;
                _score += 1;
            }
            _prev_match = _ti;
        }
    }

    if (_pi <= _plen) return 0;
    _score += max(0, 50 - _tlen);
    return max(1, _score);
}

/// Multi-token fuzzy AND score with pre-lowered candidate text.
/// _tokens, _tokens_lower: pre-split and pre-lowered search tokens.
function scm_comp__multi_fuzzy_score_pre(_text, _tlow, _tokens, _tokens_lower) {
    var _nt = array_length(_tokens);
    if (_nt == 0) return 1;
    if (_nt == 1) return scm_comp__fuzzy_score_pre(_text, _tlow, _tokens[0], _tokens_lower[0]);

    var _total = 0;
    for (var _j = 0; _j < _nt; _j++) {
        var _s = scm_comp__fuzzy_score_pre(_text, _tlow, _tokens[_j], _tokens_lower[_j]);
        if (_s == 0) return 0;
        _total += _s;
    }
    return _total;
}

// ═══════════════════════════════════════════════════════════════════
//  Section 1b: Shared helpers
// ═══════════════════════════════════════════════════════════════════

/// Compute LCP of two strings. Returns the longest common prefix.
function scm_comp__lcp_pair(_a, _b) {
    var _la = string_length(_a);
    var _lb = string_length(_b);
    var _mn = min(_la, _lb);
    var _k = 0;
    while (_k < _mn && string_char_at(_a, _k + 1) == string_char_at(_b, _k + 1)) {
        _k++;
    }
    return string_copy(_a, 1, _k);
}

/// Find the start of the word at cursor (scan backwards for word boundary).
/// Returns 0-based position (for use with string_copy(_buf, result + 1, ...)).
function scm_comp__word_start(_buf, _cursor) {
    var _start = _cursor;
    while (_start > 0) {
        var _c = string_char_at(_buf, _start);
        if (_c == " " || _c == "(" || _c == ")" || _c == "\t"
            || _c == "'" || _c == "`" || _c == chr(34)) break;
        _start--;
    }
    return _start;
}

/// Build a search index from a merged name list.
/// Returns { names, tags, trie, masks, count }.
function scm_comp__build_index(_all_names, _all_tags) {
    return {
        names: _all_names,
        tags:  _all_tags,
        trie:  scm_comp__build_trie(_all_names),
        masks: scm_comp__build_masks(_all_names),
        count: array_length(_all_names),
    };
}

/// Scan backward from _scan to find the enclosing function call.
/// Traverses strings, nested parens, whitespace-separated atoms.
/// Returns { fn_name, arg_idx } or undefined.
///   fn_name: the first atom after the found '('
///   arg_idx: count of space-separated tokens between '(' and _scan
///            (includes the function name itself in the count)
/// _limit: upper bound (1-based) for fn_name extraction
function scm_comp__scan_call_ctx(_buf, _scan, _limit) {
    var _depth = 0;
    var _in_scan_str = false;
    var _arg_idx = 0;

    while (_scan > 0) {
        var _c = string_char_at(_buf, _scan);

        if (_in_scan_str) {
            if (_c == chr(34)) {
                var _bs = 0;
                var _k = _scan - 1;
                while (_k > 0 && string_char_at(_buf, _k) == "\\") {
                    _bs++; _k--;
                }
                if ((_bs mod 2) == 0) _in_scan_str = false;
            }
            _scan--;
            continue;
        }

        if (_c == chr(34)) {
            _in_scan_str = true;
            _arg_idx++;
            _scan--;
            continue;
        }

        if (_c == ")") { _depth++; _scan--; continue; }

        if (_c == "(") {
            if (_depth > 0) {
                _depth--;
                _arg_idx++;
                _scan--;
                continue;
            }
            // Found the enclosing '(' — extract function name
            var _fn_start = _scan + 1;
            while (_fn_start <= _limit && string_char_at(_buf, _fn_start) == " ")
                _fn_start++;
            var _fn_end = _fn_start;
            while (_fn_end <= _limit) {
                var _fc = string_char_at(_buf, _fn_end);
                if (_fc == " " || _fc == "(" || _fc == ")" || _fc == chr(34) || _fc == "\t") break;
                _fn_end++;
            }
            var _fn_name = string_copy(_buf, _fn_start, _fn_end - _fn_start);
            if (_fn_name == "") return undefined;

            return { fn_name: _fn_name, arg_idx: _arg_idx };
        }

        // Space/tab separates arguments at current nesting depth
        if (_c == " " || _c == "\t") {
            while (_scan > 0 && (string_char_at(_buf, _scan) == " " || string_char_at(_buf, _scan) == "\t"))
                _scan--;
            if (_scan > 0) {
                var _ac = string_char_at(_buf, _scan);
                if (_ac != "(" && _ac != ")" && _ac != chr(34) && _ac != " ") {
                    while (_scan > 0) {
                        _ac = string_char_at(_buf, _scan);
                        if (_ac == " " || _ac == "(" || _ac == ")" || _ac == chr(34) || _ac == "\t") break;
                        _scan--;
                    }
                    _arg_idx++;
                }
            }
            continue;
        }

        _scan--;
    }
    return undefined;
}

// ═══════════════════════════════════════════════════════════════════
//  Section 2: Completion providers
// ═══════════════════════════════════════════════════════════════════

/// Provider: environment bindings + keywords
/// Collects all env bindings (including gml:*), keywords, and macros.
function scm_comp__prov_env_match(_prefix) {
    return true;
}

function scm_comp__prov_env_collect(_prefix) {
    var _names = [];
    // Env bindings (all, including gml:*)
    if (variable_global_exists("scm_env")) {
        var _env = global.scm_env;
        var _seen = ds_map_create();
        while (_env != undefined) {
            var _keys = variable_struct_get_names(_env.bindings);
            for (var _i = 0; _i < array_length(_keys); _i++) {
                var _k = _keys[_i];
                if (!ds_map_exists(_seen, _k)) {
                    ds_map_set(_seen, _k, true);
                    array_push(_names, _k);
                }
            }
            _env = _env.parent;
        }
        ds_map_destroy(_seen);
    }
    // Keywords
    if (variable_global_exists("__repl_keywords")) {
        var _kw_key = ds_map_find_first(global.__repl_keywords);
        while (_kw_key != undefined) {
            array_push(_names, _kw_key);
            _kw_key = ds_map_find_next(global.__repl_keywords, _kw_key);
        }
    }
    // Macros (from define-macro)
    if (variable_global_exists("__scm_macros")) {
        var _macro_keys = variable_struct_get_names(global.__scm_macros);
        for (var _i = 0; _i < array_length(_macro_keys); _i++) {
            array_push(_names, _macro_keys[_i]);
        }
    }
    return _names;
}

// ═══════════════════════════════════════════════════════════════════
//  Section 3: Provider registry
// ═══════════════════════════════════════════════════════════════════

/// Initialize completion provider list.
function scm_comp_init() {
    global.__comp_providers = [
        { match_fn: scm_comp__prov_env_match,   collect_fn: scm_comp__prov_env_collect },
    ];

    // Popup state
    global.__comp_active = false;     // is popup showing?
    global.__comp_raw = [];           // raw candidate names (cached from provider)
    global.__comp_matches = [];       // filtered+scored [{name, score}]
    global.__comp_sel = 0;            // selected index in matches
    global.__comp_page = 0;           // current page (for display)
    global.__comp_prefix = "";        // current prefix being matched
    global.__comp_word_start = 0;     // 0-based position in buffer where word starts
    global.__comp_per_page = 10;      // max items visible per page
    global.__comp_segment_mode = false; // true = showing _-segments, not individual items

    // String-context completer registry (populated by comp:on from Scheme)
    // Key: "fn-name|arg-idx" → { index, insert_fn, label }
    global.__comp_completers = ds_map_create();

    // String-context state
    global.__comp_string_ctx = false;   // true when completing inside a string
    global.__comp_insert_fn = undefined; // Scheme lambda for transforming insertion
    global.__comp_completer = undefined; // cached completer struct for current activation
    global.__comp_raw_masks = [];       // parallel bitmask array for dict candidates
    global.__comp_lcp_cached = "";      // streaming LCP computed during filter

    // Argument-context hint (shown in footer when at a bare arg with completer)
    global.__comp_arg_hint = undefined; // undefined or { label, count }

    // ── Overlay (F3) state ──────────────────────────────────────
    global.__comp_ov_active = false;    // is overlay showing?
    global.__comp_ov_input = "";        // search input text
    global.__comp_ov_matches = [];      // filtered [{name, score}]
    global.__comp_ov_sel = 0;           // selected index
    global.__comp_ov_page = 0;          // current page
    global.__comp_ov_per_page = 12;     // items per page
    global.__comp_ov_mode = "all";      // "all" | "string" | "env"
    global.__comp_ov_has_completer = false;
    global.__comp_ov_raw_env = [];      // env candidate names
    global.__comp_ov_raw_dict = [];     // dict candidate names
    global.__comp_ov_raw_dict_masks = []; // dict candidate bitmasks
    global.__comp_ov_raw_dict_tags = [];  // per-name tag strings
    global.__comp_ov_in_string = false; // was cursor inside a string when opened?
    global.__comp_ov_completer = undefined; // the completer struct (for insert_fn)
    global.__comp_ov_word_start = 0;    // 0-based buffer position for insertion
    global.__comp_ov_raw_env_lower = [];    // pre-lowered env names
    global.__comp_ov_raw_dict_lower = [];   // pre-lowered dict names
    global.__comp_ov_all_matches = [];      // all matches (for incremental)
    global.__comp_ov_prev_search = "";      // previous search (for incremental)
    global.__comp_ov_prev_mode = "all";     // previous mode (for incremental)
    global.__comp_ov_dirty = false;         // deferred refilter flag
}

/// Load comp-init.scm (bundled as @@COMP_INIT@@).
/// Registers string-context completers for asset/global name arguments.
function scm_comp__load_init() {
    var _src = "@@COMP_INIT@@";
    try {
        scm_eval_program(_src, global.scm_env);
        scm_trace("[scm-comp] comp-init loaded (" +
            string(ds_map_size(global.__comp_completers)) + " completers)");
    } catch (_e) {
        scm_trace("[scm-comp] Failed to load comp-init: " + scm__exception_msg(_e));
    }
}

/// Register a string-context completer (called from comp:on builtin).
function scm_comp__register(_fn_name, _arg_idx, _insert_fn, _label, _index) {
    var _key = _fn_name + "|" + string(_arg_idx);
    ds_map_set(global.__comp_completers, _key, {
        index:     _index,
        insert_fn: _insert_fn,
        label:     _label,
    });
}

// ═══════════════════════════════════════════════════════════════════
//  Section 3b: String-context detection
// ═══════════════════════════════════════════════════════════════════

/// Detect completion context at cursor position.
/// Performs a single forward scan to determine string/arg context.
/// Returns { kind: "string"|"arg"|"none", fn_name, arg_idx, str_start }.
///   kind = "string": cursor inside "...", str_start = 1-based pos after opening "
///   kind = "arg":    cursor at bare argument position
///   kind = "none":   no actionable context detected
function scm_comp__detect_ctx(_buf, _cursor) {
    var _in_str = false;
    var _quote_pos = 0;
    for (var _i = 1; _i <= _cursor; _i++) {
        var _ch = string_char_at(_buf, _i);
        if (_ch == "\\" && _i < _cursor) { _i++; continue; }
        if (_ch == chr(34)) {
            _in_str = !_in_str;
            if (_in_str) _quote_pos = _i;
        }
    }

    if (_in_str && _quote_pos > 0) {
        // ── String context ──────────────────────────────────────
        var _scan = _quote_pos - 1;
        while (_scan > 0 && string_char_at(_buf, _scan) == " ") _scan--;
        var _ctx = scm_comp__scan_call_ctx(_buf, _scan, _quote_pos);
        if (_ctx == undefined) return { kind: "none" };
        return {
            kind:      "string",
            fn_name:   _ctx.fn_name,
            arg_idx:   _ctx.arg_idx,
            str_start: _quote_pos + 1,
        };
    }

    // ── Bare argument context ───────────────────────────────────
    var _ctx = scm_comp__scan_call_ctx(_buf, _cursor, _cursor);
    if (_ctx == undefined) return { kind: "none" };
    var _idx = _ctx.arg_idx - 1;
    if (_idx < 0) return { kind: "none" };
    return { kind: "arg", fn_name: _ctx.fn_name, arg_idx: _idx };
}

/// Look up a registered completer for the given fn_name + arg_idx.
/// Returns the completer struct { index, insert_fn, label } or undefined.
function scm_comp__lookup_completer(_fn_name, _arg_idx) {
    var _key = _fn_name + "|" + string(_arg_idx);
    if (ds_map_exists(global.__comp_completers, _key)) {
        return ds_map_find_value(global.__comp_completers, _key);
    }
    return undefined;
}

// ═══════════════════════════════════════════════════════════════════
//  Section 4: Popup state machine
// ═══════════════════════════════════════════════════════════════════

/// Dismiss the completion popup.
function scm_comp_dismiss() {
    global.__comp_active = false;
    global.__comp_raw = [];
    global.__comp_matches = [];
    global.__comp_sel = 0;
    global.__comp_page = 0;
    global.__comp_prefix = "";
    global.__comp_segment_mode = false;
    global.__comp_string_ctx = false;
    global.__comp_insert_fn = undefined;
    global.__comp_completer = undefined;
    global.__comp_raw_masks = [];
    global.__comp_lcp_cached = "";
    global.__comp_arg_hint = undefined;
}

/// Activate completion: collect candidates, fuzzy-filter, sort.
/// _buf: current input buffer, _cursor: 0-based cursor position
function scm_comp_activate(_buf, _cursor) {
    // ── Context detection (single forward scan) ─────────────────
    var _ctx = scm_comp__detect_ctx(_buf, _cursor);

    // String-context: if a completer is registered, use dict-based completion.
    if (_ctx.kind == "string") {
        var _completer = scm_comp__lookup_completer(_ctx.fn_name, _ctx.arg_idx);
        if (_completer != undefined) {
            scm_comp__activate_string_ctx(_buf, _cursor, _ctx, _completer);
            return;
        }
    }

    // ── Argument-context hint detection ─────────────────────────
    // If cursor is at a bare argument position with a registered completer,
    // show a footer hint [" → N label] while doing normal env completion.
    global.__comp_arg_hint = undefined;
    if (_ctx.kind == "arg") {
        var _completer = scm_comp__lookup_completer(_ctx.fn_name, _ctx.arg_idx);
        if (_completer != undefined) {
            global.__comp_arg_hint = { label: _completer.label, count: _completer.index.count };
        }
    }

    // ── Normal (env) completion ─────────────────────────────────
    // Extract word at cursor (scan backwards for word boundary)
    var _start = scm_comp__word_start(_buf, _cursor);
    var _prefix = string_copy(_buf, _start + 1, _cursor - _start);

    global.__comp_word_start = _start;
    global.__comp_prefix = _prefix;
    global.__comp_string_ctx = false;
    global.__comp_insert_fn = undefined;
    global.__comp_raw_masks = [];

    // Find matching provider and collect raw names
    var _raw = [];
    var _pn = array_length(global.__comp_providers);
    for (var _i = 0; _i < _pn; _i++) {
        var _prov = global.__comp_providers[_i];
        if (_prov.match_fn(_prefix)) {
            _raw = _prov.collect_fn(_prefix);
            break;
        }
    }

    // Cache raw candidates for re-filtering on subsequent keystrokes
    global.__comp_raw = _raw;

    // Filter based on current mode
    scm_comp__apply_filter(_raw, _prefix);
}

/// Activate string-context completion using registered dicts.
function scm_comp__activate_string_ctx(_buf, _cursor, _sctx, _completer) {
    var _str_start = _sctx.str_start; // 1-based, right after opening "
    var _prefix = string_copy(_buf, _str_start, _cursor - _str_start + 1);

    global.__comp_word_start = _str_start - 1;
    global.__comp_prefix = _prefix;
    global.__comp_string_ctx = true;
    global.__comp_insert_fn = _completer.insert_fn;
    global.__comp_completer = _completer;

    var _index = _completer.index;
    global.__comp_raw = _index.names;
    global.__comp_raw_masks = _index.masks;
    scm_comp__apply_filter(_index.names, _prefix);
}

/// Re-filter cached candidates with updated prefix (as user types).
/// _buf, _cursor: current buffer state
function scm_comp_update(_buf, _cursor) {
    if (!global.__comp_active) return;

    // Re-extract prefix at cursor
    var _start = global.__comp_word_start;
    if (_cursor <= _start) { scm_comp_dismiss(); return; }
    var _prefix = string_copy(_buf, _start + 1, _cursor - _start);
    if (_prefix == "") { scm_comp_dismiss(); return; }

    global.__comp_prefix = _prefix;

    // Re-filter cached raw candidates (no re-collection needed)
    scm_comp__apply_filter(global.__comp_raw, _prefix);
}

/// Internal: filter candidates by prefix match.
function scm_comp__apply_filter(_raw, _prefix) {
    global.__comp_segment_mode = false;
    scm_comp__filter_prefix(_raw, _prefix);
}

/// Prefix-only filter: exact prefix match, alphabetical order.
/// Computes streaming LCP across ALL matches (not just displayed ones).
function scm_comp__filter_prefix(_raw, _prefix) {
    var _matches = [];
    var _n = array_length(_raw);
    var _plen = string_length(_prefix);
    var _plow = string_lower(_prefix);
    var _max_display = 200;
    var _lcp = "";
    var _lcp_init = false;
    for (var _i = 0; _i < _n; _i++) {
        if (string_copy(string_lower(_raw[_i]), 1, _plen) == _plow) {
            // Streaming LCP: covers ALL matching candidates
            if (!_lcp_init) {
                _lcp = _raw[_i];
                _lcp_init = true;
            } else {
                _lcp = scm_comp__lcp_pair(_lcp, _raw[_i]);
            }
            // Only store up to _max_display for popup rendering
            if (array_length(_matches) < _max_display) {
                var _entry = {};
                _entry.name = _raw[_i];
                _entry.sc = 0;
                array_push(_matches, _entry);
            }
        }
    }
    global.__comp_matches = _matches;
    global.__comp_lcp_cached = _lcp;
    global.__comp_sel = 0;
    global.__comp_page = 0;
    global.__comp_active = (array_length(_matches) > 0);
}

// ═══════════════════════════════════════════════════════════════════
//  Section 4b: Runtime trie / bitmask building
// ═══════════════════════════════════════════════════════════════════

/// Tokenize a name into word-boundary segments (GML port of Python _tokenize).
/// Splits at '_' boundaries (_ attached to following segment) and
/// camelCase boundaries (lower→Upper). Uses string_byte_at for speed.
///
/// Examples:
///   "obj_enemy_skeleton"         → ["obj", "_enemy", "_skeleton"]
///   "ConsoleAutoHint"            → ["Console", "Auto", "Hint"]
///   "scr_dungeonRoomsNumberInit" → ["scr", "_dungeon", "Rooms", "Number", "Init"]
///   "_internal_func"             → ["_internal", "_func"]
function scm_comp__tokenize(_name) {
    var _segments = [];
    var _len = string_length(_name);
    if (_len == 0) return _segments;
    var _seg_start = 1; // 1-based

    for (var _i = 2; _i <= _len; _i++) {
        var _b = string_byte_at(_name, _i);
        var _prev = string_byte_at(_name, _i - 1);

        // Split before '_' (underscore = 95): _ attached to following segment
        if (_b == 95) {
            array_push(_segments, string_copy(_name, _seg_start, _i - _seg_start));
            _seg_start = _i;
            continue;
        }
        // Split at camelCase boundary: prev is lowercase (97-122), cur is uppercase (65-90)
        if (_prev >= 97 && _prev <= 122 && _b >= 65 && _b <= 90) {
            array_push(_segments, string_copy(_name, _seg_start, _i - _seg_start));
            _seg_start = _i;
            continue;
        }
    }
    // Push final segment
    array_push(_segments, string_copy(_name, _seg_start, _len - _seg_start + 1));
    return _segments;
}

/// Build a word-boundary trie from an array of names.
/// Each edge = one word token (from scm_comp__tokenize).
/// No path compression — trie_walk handles uncompressed tries.
/// Returns the root trie node (a GML struct).
///
/// Node format:
///   { "#": count, "$": true (if leaf), edge1: child1, edge2: child2, ... }
function scm_comp__build_trie(_names) {
    var _root = {};
    var _nn = array_length(_names);
    variable_struct_set(_root, "#", _nn);

    for (var _i = 0; _i < _nn; _i++) {
        var _tokens = scm_comp__tokenize(_names[_i]);
        var _node = _root;
        var _nt = array_length(_tokens);
        for (var _j = 0; _j < _nt; _j++) {
            var _tok = _tokens[_j];
            if (variable_struct_exists(_node, _tok)) {
                _node = variable_struct_get(_node, _tok);
                variable_struct_set(_node, "#", variable_struct_get(_node, "#") + 1);
            } else {
                var _child = {};
                variable_struct_set(_child, "#", 1);
                variable_struct_set(_node, _tok, _child);
                _node = _child;
            }
        }
        variable_struct_set(_node, "$", true);
    }
    return _root;
}

/// Build parallel 26-bit char bitmask array for a list of names.
/// Bit i is set if letter chr(ord("a") + i) appears in the lowercase name.
/// Uses string_byte_at for speed.
function scm_comp__build_masks(_names) {
    var _nn = array_length(_names);
    var _masks = array_create(_nn);
    for (var _i = 0; _i < _nn; _i++) {
        var _name = _names[_i];
        var _mask = 0;
        var _len = string_length(_name);
        for (var _j = 1; _j <= _len; _j++) {
            var _b = string_byte_at(_name, _j);
            // Uppercase A-Z (65-90) → shift to lowercase range
            if (_b >= 65 && _b <= 90) _b += 32;
            // Lowercase a-z (97-122) → set bit
            if (_b >= 97 && _b <= 122) {
                _mask |= (1 << (_b - 97));
            }
        }
        _masks[_i] = _mask;
    }
    return _masks;
}

/// Navigate the word-boundary trie to the node matching _suffix.
/// Returns the trie node struct, or undefined if no match.
/// Handles multiple partial edge matches (common in word-boundary tries
/// where sibling edges share a prefix like "_").
function scm_comp__trie_walk(_node, _suffix) {
    var _pos = 1; // 1-based position in _suffix
    var _slen = string_length(_suffix);

    while (_pos <= _slen) {
        var _keys = variable_struct_get_names(_node);
        var _remaining = _slen - _pos + 1;

        // Try full edge match first
        var _found = false;
        for (var _i = 0; _i < array_length(_keys); _i++) {
            var _edge = _keys[_i];
            if (_edge == "$" || _edge == "#") continue;
            var _elen = string_length(_edge);
            if (_remaining >= _elen
                && string_copy(_suffix, _pos, _elen) == _edge) {
                _node = variable_struct_get(_node, _edge);
                _pos += _elen;
                _found = true;
                break;
            }
        }
        if (_found) continue;

        // No full match — collect ALL partial edge matches into a synthetic node.
        // This handles word-boundary tries where multiple edges share a prefix
        // (e.g. "_skeleton", "_mage", "_warrior" all start with "_").
        var _match_str = string_copy(_suffix, _pos, _remaining);
        var _synthetic = {};
        var _total = 0;
        var _any = false;
        for (var _i = 0; _i < array_length(_keys); _i++) {
            var _edge = _keys[_i];
            if (_edge == "$" || _edge == "#") continue;
            var _elen = string_length(_edge);
            if (_elen > _remaining
                && string_copy(_edge, 1, _remaining) == _match_str) {
                var _rest = string_copy(_edge, _remaining + 1, _elen - _remaining);
                var _child = variable_struct_get(_node, _edge);
                variable_struct_set(_synthetic, _rest, _child);
                _total += variable_struct_get(_child, "#");
                _any = true;
            }
        }
        if (_any) {
            variable_struct_set(_synthetic, "#", _total);
            return _synthetic;
        }

        return undefined;
    }

    return _node;
}

/// Get the children of a trie node as completion entries for the popup.
/// Returns array of { name, count, score, node, drillable, is_leaf }.
/// _node: trie node, _prefix: the typed prefix string.
function scm_comp__trie_children(_node, _prefix) {
    var _result = [];
    var _keys = variable_struct_get_names(_node);
    for (var _i = 0; _i < array_length(_keys); _i++) {
        var _edge = _keys[_i];
        if (_edge == "$" || _edge == "#") continue;
        var _child = variable_struct_get(_node, _edge);
        // Count real edges in child (drillable = has further children)
        var _ckeys = variable_struct_get_names(_child);
        var _n_edges = 0;
        for (var _j = 0; _j < array_length(_ckeys); _j++) {
            if (_ckeys[_j] != "$" && _ckeys[_j] != "#") _n_edges++;
        }
        var _entry = {};
        _entry.name = _prefix + _edge;
        _entry.count = variable_struct_get(_child, "#");
        _entry.sc = 0;
        _entry.node = _child;
        _entry.drillable = (_n_edges > 0);
        _entry.is_leaf = variable_struct_exists(_child, "$");
        array_push(_result, _entry);
    }
    return _result;
}

/// Activate segment mode by walking the word-boundary trie.
/// In string-context: uses the dict's trie for segment drill-down.
/// In normal context: disabled (no trie available).
///
/// Inline expansion: if the trie node has fewer children than per_page,
/// greedily expands the smallest branch to fill one page. This avoids
/// showing a near-empty page that requires unnecessary drilling.
function scm_comp__maybe_trie_segment() {
    var _prefix = global.__comp_prefix;

    // String-context: use unified trie for segment drill-down
    if (global.__comp_string_ctx) {
        if (global.__comp_completer == undefined) {
            global.__comp_segment_mode = false;
            return;
        }
        var _trie_root = global.__comp_completer.index.trie;
        if (_trie_root == undefined) {
            global.__comp_segment_mode = false;
            return;
        }

        var _node;
        if (_prefix == "") {
            _node = _trie_root;
        } else {
            _node = scm_comp__trie_walk(_trie_root, _prefix);
        }

        if (_node == undefined) {
            global.__comp_segment_mode = false;
            return;
        }

        var _children = scm_comp__trie_children(_node, _prefix);
        if (array_length(_children) <= 1) {
            global.__comp_segment_mode = false;
            return;
        }

        // ── Inline expansion: fill to one page ──────────────────
        var _per_page = global.__comp_per_page;
        while (array_length(_children) < _per_page) {
            // Find the smallest drillable branch
            var _si = -1;
            var _sc = 999999999;
            for (var _i = 0; _i < array_length(_children); _i++) {
                if (_children[_i].drillable && _children[_i].count < _sc) {
                    _sc = _children[_i].count;
                    _si = _i;
                }
            }
            if (_si == -1) break; // no drillable branches left

            // Get sub-children of the smallest branch
            var _branch = _children[_si];
            var _sub = scm_comp__trie_children(_branch.node, _branch.name);
            var _n_sub = array_length(_sub);

            // Cost: remove 1 branch, add N_sub children (+ 1 if branch is also a leaf)
            var _new_total = array_length(_children) - 1 + _n_sub
                             + (_branch.is_leaf ? 1 : 0);
            if (_new_total > _per_page) break;

            // Replace branch with its expansion
            array_delete(_children, _si, 1);
            var _ins = _si;
            // If branch is itself a valid name, keep it as a non-drillable leaf
            if (_branch.is_leaf) {
                var _leaf = {};
                _leaf.name = _branch.name;
                _leaf.count = 1;
                _leaf.sc = 0;
                _leaf.node = _branch.node;
                _leaf.drillable = false;
                _leaf.is_leaf = true;
                array_insert(_children, _ins, _leaf);
                _ins++;
            }
            // Insert sub-children
            for (var _j = 0; _j < _n_sub; _j++) {
                array_insert(_children, _ins + _j, _sub[_j]);
            }
        }

        global.__comp_matches = _children;
        global.__comp_segment_mode = true;
        global.__comp_sel = 0;
        global.__comp_page = 0;
        return;
    }

    // Normal (env) context: no trie segment available
    global.__comp_segment_mode = false;
}

/// Is segment mode active?
function scm_comp_is_segment_mode() {
    return global.__comp_segment_mode;
}

/// Is the current completion in string-context mode?
function scm_comp_is_string_ctx() {
    return global.__comp_string_ctx;
}

/// Get the insert function for string-context mode (Scheme lambda or undefined).
function scm_comp_get_insert_fn() {
    return global.__comp_insert_fn;
}

/// Get the currently selected completion string (or "" if none).
function scm_comp_selected() {
    if (!global.__comp_active) return "";
    var _n = array_length(global.__comp_matches);
    if (_n == 0 || global.__comp_sel >= _n) return "";
    return global.__comp_matches[global.__comp_sel].name;
}

/// Move selection up by 1 (wraps around).
function scm_comp_prev() {
    if (!global.__comp_active) return;
    var _n = array_length(global.__comp_matches);
    if (_n == 0) return;
    global.__comp_sel = (global.__comp_sel - 1 + _n) mod _n;
    // Adjust page to keep selection visible
    global.__comp_page = global.__comp_sel div global.__comp_per_page;
}

/// Move selection down by 1 (wraps around).
function scm_comp_next() {
    if (!global.__comp_active) return;
    var _n = array_length(global.__comp_matches);
    if (_n == 0) return;
    global.__comp_sel = (global.__comp_sel + 1) mod _n;
    global.__comp_page = global.__comp_sel div global.__comp_per_page;
}

/// Accept the selected completion: returns the text to insert
/// (the part after the prefix). Dismisses popup.
function scm_comp_accept() {
    var _sel = scm_comp_selected();
    scm_comp_dismiss();
    return _sel;
}

/// Is the completion popup active?
function scm_comp_is_active() {
    return global.__comp_active;
}

/// Total number of matches.
function scm_comp_count() {
    return array_length(global.__comp_matches);
}

/// Return the longest common prefix (LCP) of all matching candidates.
/// Pre-computed during filter as a streaming operation over ALL matches
/// (not limited to the displayed subset).
function scm_comp_lcp() {
    return global.__comp_lcp_cached;
}

// ═══════════════════════════════════════════════════════════════════
//  Section 5: Popup rendering
// ═══════════════════════════════════════════════════════════════════

/// Draw the completion popup above the input line.
///
/// _x0:     left edge (pixel, at start of word being completed)
/// _y_base: baseline Y of the input line (popup draws ABOVE this)
/// _cw:     character width (monospace)
/// _lh:     line height
/// _colors: struct { bg, bg_sel, text, text_sel, text_dim, border }
function scm_comp_draw_popup(_x0, _y_base, _cw, _lh, _colors) {
    if (!global.__comp_active) return;

    var _matches = global.__comp_matches;
    var _n = array_length(_matches);
    if (_n == 0) return;

    var _per_page = global.__comp_per_page;
    var _page = global.__comp_page;
    var _page_start = _page * _per_page;
    var _page_end = min(_page_start + _per_page, _n);
    var _visible_count = _page_end - _page_start;
    var _total_pages = (_n + _per_page - 1) div _per_page;

    // Layout — in segment mode, compute display length (strip prefix)
    var _seg_mode = global.__comp_segment_mode;
    var _prefix_len = string_length(global.__comp_prefix);
    var _max_name_len = 0;
    for (var _i = _page_start; _i < _page_end; _i++) {
        var _len;
        if (_seg_mode) {
            _len = string_length(_matches[_i].name) - _prefix_len;
        } else {
            _len = string_length(_matches[_i].name);
        }
        if (_len > _max_name_len) _max_name_len = _len;
    }
    // In segment mode, add room for indicator + count column " ▸ ($, NNN)"
    var _count_cols = _seg_mode ? 12 : 0;
    // If arg hint is present, ensure popup is wide enough for footer hint text
    var _hint_cols = 0;
    if (global.__comp_arg_hint != undefined) {
        // '  [" → NNNNN label]' — estimate length
        _hint_cols = 8 + string_length(string(global.__comp_arg_hint.count))
                       + string_length(global.__comp_arg_hint.label);
    }
    var _pad_x = 4;
    var _pad_y = 2;
    var _min_cols = _max_name_len + 4 + _count_cols;
    if (_hint_cols > _min_cols) _min_cols = _hint_cols;
    var _popup_w = _min_cols * _cw; // text padding
    var _row_h = _lh;
    var _popup_h = _visible_count * _row_h + _row_h; // +1 row for footer
    var _outer_w = _popup_w + _pad_x * 2;
    var _outer_h = _popup_h + _pad_y * 2;

    // Position: above input, clamped to screen
    var _pos = scm_ui_popup_pos(_x0 - _pad_x, _y_base, _outer_w, _outer_h, 4);
    var _px = _pos.x + _pad_x; // inner content left edge
    var _py = _pos.y + _pad_y; // inner content top edge

    // Background + border
    scm_ui_panel(_pos.x, _pos.y, _pos.x + _outer_w, _pos.y + _outer_h,
                 _colors.bg, _colors.border);

    // List: background highlight for selected row
    var _ctx = scm_ui_list_begin(_px, _py, _popup_w, _row_h, _n,
                                  global.__comp_sel, _page, _per_page,
                                  { bg: _colors.bg, bg_sel: _colors.bg_sel,
                                    border: _colors.bg }); // no inner border

    // Items
    for (var _i = _ctx.page_start; _i < _ctx.page_end; _i++) {
        var _row = scm_ui_list_row(_ctx, _i);
        var _name = _matches[_i].name;
        var _text_color = _row.is_selected ? _colors.text_sel : _colors.text;
        var _xx = _row.x + _cw; // left padding

        if (_seg_mode) {
            // Segment mode: show segment text (strip prefix)
            var _seg_text = string_copy(_name, _prefix_len + 1,
                                        string_length(_name) - _prefix_len);
            var _is_drillable = variable_struct_exists(_matches[_i], "drillable")
                                && _matches[_i].drillable;
            var _is_leaf = variable_struct_exists(_matches[_i], "is_leaf")
                           && _matches[_i].is_leaf;

            scm_ui_text(_xx, _row.y, _seg_text, _text_color);

            if (_is_drillable) {
                // Drillable: show ▸ indicator + count
                var _ind_x = _xx + string_length(_seg_text) * _cw;
                scm_ui_text_dim(_ind_x, _row.y, " \u25B8", _colors.text_dim);
                var _count_str;
                if (_is_leaf) {
                    _count_str = " ($, " + string(_matches[_i].count) + ")";
                } else {
                    _count_str = " (" + string(_matches[_i].count) + ")";
                }
                var _cx = _row.x + (_max_name_len + 3) * _cw;
                scm_ui_text_dim(_cx, _row.y, _count_str, _colors.text_dim);
            }
        } else {
            // Item mode: prefix highlighted, rest dimmed
            var _plen = _prefix_len;
            if (_plen > 0 && string_copy(string_lower(_name), 1, _plen) == string_lower(global.__comp_prefix)) {
                var _pre = string_copy(_name, 1, _plen);
                var _rest = string_copy(_name, _plen + 1, string_length(_name) - _plen);
                scm_ui_text(_xx, _row.y, _pre, _text_color);
                _xx += string_length(_pre) * _cw;
                scm_ui_text_alpha(_xx, _row.y, _rest,
                    _row.is_selected ? _text_color : _colors.text_dim, 0.9);
            } else {
                scm_ui_text_alpha(_xx, _row.y, _name, _text_color, 0.9);
            }
        }
    }

    // Footer: mode indicator (+ pager if multi-page)
    var _mode;
    if (_seg_mode) {
        _mode = "segment";
    } else {
        _mode = "prefix";
    }
    var _footer_y = _py + _visible_count * _row_h;
    var _footer = scm_ui_list_footer(_page, _total_pages, _n, _mode);
    // Append argument-context hint if present
    if (global.__comp_arg_hint != undefined) {
        _footer += "  [" + chr(34) + " \u2192 "
                 + string(global.__comp_arg_hint.count) + " "
                 + global.__comp_arg_hint.label + "]";
    }
    scm_ui_text_dim(_px + _cw, _footer_y, _footer, _colors.text_dim);
}

// ═══════════════════════════════════════════════════════════════════
//  Section 6: F3 Overlay Mode
// ═══════════════════════════════════════════════════════════════════

/// Is the overlay active?
function scm_comp_overlay_is_active() {
    return global.__comp_ov_active;
}

/// Open the overlay. Detects context at cursor, collects candidates, pre-fills.
function scm_comp_overlay_open(_buf, _cursor) {
    // Dismiss inline popup if active
    if (global.__comp_active) scm_comp_dismiss();

    // ── Context detection (single forward scan) ──────────────────
    var _has_completer = false;
    var _in_string = false;
    var _completer = undefined;
    var _word_start = _cursor;
    var _prefill = "";

    var _ctx = scm_comp__detect_ctx(_buf, _cursor);

    // 1. Try string-context (cursor inside "...")
    if (_ctx.kind == "string") {
        _completer = scm_comp__lookup_completer(_ctx.fn_name, _ctx.arg_idx);
        if (_completer != undefined) {
            _has_completer = true;
            _in_string = true;
            _word_start = _ctx.str_start - 1;
            _prefill = string_copy(_buf, _ctx.str_start, _cursor - _ctx.str_start + 1);
        }
    }

    // 2. Try bare arg-context
    if (!_has_completer && _ctx.kind == "arg") {
        _completer = scm_comp__lookup_completer(_ctx.fn_name, _ctx.arg_idx);
        if (_completer != undefined) {
            _has_completer = true;
            _in_string = false;
        }
    }

    // 3. Extract word at cursor for pre-fill (if not already set from string ctx)
    if (_prefill == "" && !_in_string) {
        _word_start = scm_comp__word_start(_buf, _cursor);
        _prefill = string_copy(_buf, _word_start + 1, _cursor - _word_start);
    }

    // ── Collect candidates ──────────────────────────────────────
    var _raw_env = scm_comp__prov_env_collect("");
    var _raw_dict = [];
    var _raw_dict_masks = [];
    var _raw_dict_tags = [];

    if (_has_completer) {
        var _idx = _completer.index;
        _raw_dict = _idx.names;
        _raw_dict_masks = _idx.masks;
        _raw_dict_tags = _idx.tags;
    }

    // Pre-compute lowered names (avoids per-keystroke string_lower)
    var _raw_env_lower = [];
    var _en = array_length(_raw_env);
    for (var _i = 0; _i < _en; _i++) {
        array_push(_raw_env_lower, string_lower(_raw_env[_i]));
    }
    var _raw_dict_lower = [];
    var _pn = array_length(_raw_dict);
    for (var _i = 0; _i < _pn; _i++) {
        array_push(_raw_dict_lower, string_lower(_raw_dict[_i]));
    }

    // ── Set state ───────────────────────────────────────────────
    global.__comp_ov_active = true;
    global.__comp_ov_input = _prefill;
    global.__comp_ov_sel = 0;
    global.__comp_ov_page = 0;
    global.__comp_ov_has_completer = _has_completer;
    global.__comp_ov_raw_env = _raw_env;
    global.__comp_ov_raw_dict = _raw_dict;
    global.__comp_ov_raw_dict_masks = _raw_dict_masks;
    global.__comp_ov_raw_dict_tags = _raw_dict_tags;
    global.__comp_ov_raw_env_lower = _raw_env_lower;
    global.__comp_ov_raw_dict_lower = _raw_dict_lower;
    global.__comp_ov_in_string = _in_string;
    global.__comp_ov_completer = _completer;
    global.__comp_ov_word_start = _word_start;
    global.__comp_ov_all_matches = [];
    global.__comp_ov_prev_search = "";
    global.__comp_ov_prev_mode = "all";
    global.__comp_ov_dirty = false;

    // Initial filter
    scm_comp__overlay_refilter();
}

/// Close the overlay without accepting.
function scm_comp_overlay_close() {
    global.__comp_ov_active = false;
    global.__comp_ov_input = "";
    global.__comp_ov_matches = [];
    global.__comp_ov_raw_env = [];
    global.__comp_ov_raw_dict = [];
    global.__comp_ov_raw_dict_masks = [];
    global.__comp_ov_raw_dict_tags = [];
    global.__comp_ov_raw_env_lower = [];
    global.__comp_ov_raw_dict_lower = [];
    global.__comp_ov_all_matches = [];
    global.__comp_ov_prev_search = "";
    global.__comp_ov_dirty = false;
    global.__comp_ov_completer = undefined;
}

/// Accept the selected overlay result.
/// Returns a struct { text, word_start, needs_quote_wrap } or undefined if nothing selected.
function scm_comp_overlay_accept() {
    if (!global.__comp_ov_active) return undefined;
    scm_comp__overlay_flush();
    var _matches = global.__comp_ov_matches;
    if (array_length(_matches) == 0) return undefined;

    var _sel = global.__comp_ov_sel;
    if (_sel < 0 || _sel >= array_length(_matches)) return undefined;

    var _name = _matches[_sel].name;
    var _needs_wrap = false;

    // Determine insertion mode:
    //   - in_string → identity (bare name, already inside quotes)
    //   - bare arg with completer → auto-wrap "name"
    //   - env/no completer → identity
    if (!global.__comp_ov_in_string && global.__comp_ov_has_completer) {
        // Check if mode was "string" (user typed " prefix) — these are dict results
        // that should be wrapped in quotes for bare arg insertion
        if (global.__comp_ov_mode == "string" || global.__comp_ov_mode == "all") {
            // If the selected name came from dict collection, wrap it.
            // For env candidates, no wrap needed.
            _needs_wrap = (_matches[_sel].dict_tag != "");
        }
    }

    var _result = {
        text: _name,
        word_start: global.__comp_ov_word_start,
        needs_quote_wrap: _needs_wrap,
        in_string: global.__comp_ov_in_string,
    };

    scm_comp_overlay_close();
    return _result;
}

/// Update overlay input. Defers refilter to next flush (lazy evaluation).
function scm_comp_overlay_set_input(_text) {
    if (_text == global.__comp_ov_input) return;
    global.__comp_ov_input = _text;
    global.__comp_ov_sel = 0;
    global.__comp_ov_page = 0;
    global.__comp_ov_dirty = true;
}

/// Flush deferred refilter if dirty. Call before reading matches.
function scm_comp__overlay_flush() {
    if (global.__comp_ov_dirty) {
        global.__comp_ov_dirty = false;
        scm_comp__overlay_refilter();
    }
}

/// Internal: re-filter overlay candidates based on current input + mode.
/// Supports incremental narrowing when search extends previous query.
function scm_comp__overlay_refilter() {
    var _input = global.__comp_ov_input;

    // ── Mode prefix detection ───────────────────────────────────
    var _search = _input;
    var _mode = "all";
    if (string_length(_input) > 0 && string_char_at(_input, 1) == chr(34)) {
        if (global.__comp_ov_has_completer) {
            _mode = "string";
            _search = string_copy(_input, 2, string_length(_input) - 1);
        }
    }
    if (!global.__comp_ov_has_completer) {
        _mode = "env";
    }
    global.__comp_ov_mode = _mode;

    // ── Empty search → clear ────────────────────────────────────
    if (string_length(_search) == 0) {
        global.__comp_ov_matches = [];
        global.__comp_ov_all_matches = [];
        global.__comp_ov_prev_search = "";
        return;
    }

    // ── Pre-split and pre-lower search tokens ───────────────────
    var _tokens = scm_comp__split_tokens(_search);
    var _tokens_lower = [];
    var _nt = array_length(_tokens);
    for (var _i = 0; _i < _nt; _i++) {
        array_push(_tokens_lower, string_lower(_tokens[_i]));
    }

    // ── Incremental check ───────────────────────────────────────
    var _prev = global.__comp_ov_prev_search;
    var _incremental = (
        string_length(_prev) > 0
        && string_length(_search) > string_length(_prev)
        && string_copy(_search, 1, string_length(_prev)) == _prev
        && _mode == global.__comp_ov_prev_mode
        && array_length(global.__comp_ov_all_matches) > 0
    );

    var _matches = [];
    var _max_results = 200;

    if (_incremental) {
        // ── Incremental: re-score within previous survivors ─────
        var _prev_all = global.__comp_ov_all_matches;
        var _pa = array_length(_prev_all);
        for (var _i = 0; _i < _pa; _i++) {
            var _m = _prev_all[_i];
            var _score = scm_comp__multi_fuzzy_score_pre(
                _m.name, _m.name_lower, _tokens, _tokens_lower);
            if (_score > 0) {
                array_push(_matches, {
                    name: _m.name,
                    name_lower: _m.name_lower,
                    sc: _score,
                    dict_tag: _m.dict_tag
                });
            }
        }
    } else {
        // ── Full scan with pre-lowered arrays ───────────────────
        if (_mode == "env" || _mode == "all") {
            var _env = global.__comp_ov_raw_env;
            var _env_low = global.__comp_ov_raw_env_lower;
            var _en = array_length(_env);
            for (var _i = 0; _i < _en; _i++) {
                var _score = scm_comp__multi_fuzzy_score_pre(
                    _env[_i], _env_low[_i], _tokens, _tokens_lower);
                if (_score > 0) {
                    array_push(_matches, {
                        name: _env[_i],
                        name_lower: _env_low[_i],
                        sc: _score,
                        dict_tag: ""
                    });
                }
            }
        }

        if (_mode == "string" || _mode == "all") {
            var _dict = global.__comp_ov_raw_dict;
            var _dict_low = global.__comp_ov_raw_dict_lower;
            var _masks = global.__comp_ov_raw_dict_masks;
            var _tags = global.__comp_ov_raw_dict_tags;
            var _pn = array_length(_dict);
            var _has_masks = (array_length(_masks) == _pn && _pn > 0);

            var _qmask = 0;
            if (_has_masks) {
                _qmask = scm_comp__char_mask(_search);
            }

            for (var _i = 0; _i < _pn; _i++) {
                if (_has_masks && ((_masks[_i] & _qmask) != _qmask)) continue;
                var _score = scm_comp__multi_fuzzy_score_pre(
                    _dict[_i], _dict_low[_i], _tokens, _tokens_lower);
                if (_score > 0) {
                    array_push(_matches, {
                        name: _dict[_i],
                        name_lower: _dict_low[_i],
                        sc: _score,
                        dict_tag: _tags[_i]
                    });
                }
            }
        }
    }

    // ── Sort ────────────────────────────────────────────────────
    var _mn = array_length(_matches);
    if (_mn > 500) {
        // Partial selection sort: find top _max_results only (O(n*k))
        var _top = min(_mn, _max_results);
        for (var _i = 0; _i < _top; _i++) {
            var _best = _i;
            for (var _j = _i + 1; _j < _mn; _j++) {
                if (_matches[_j].sc > _matches[_best].sc) _best = _j;
            }
            if (_best != _i) {
                var _tmp = _matches[_i];
                _matches[_i] = _matches[_best];
                _matches[_best] = _tmp;
            }
        }
    } else {
        // Insertion sort for small sets (O(n²) but n≤500)
        for (var _i = 1; _i < _mn; _i++) {
            var _tmp = _matches[_i];
            var _j = _i - 1;
            while (_j >= 0 && _matches[_j].sc < _tmp.sc) {
                _matches[_j + 1] = _matches[_j];
                _j--;
            }
            _matches[_j + 1] = _tmp;
        }
    }

    // ── Save all for incremental, truncate for display ──────────
    global.__comp_ov_all_matches = _matches;
    global.__comp_ov_prev_search = _search;
    global.__comp_ov_prev_mode = _mode;

    if (_mn > _max_results) {
        var _display = array_create(_max_results);
        array_copy(_display, 0, _matches, 0, _max_results);
        global.__comp_ov_matches = _display;
    } else {
        global.__comp_ov_matches = _matches;
    }
}

/// Navigate overlay selection.
function scm_comp_overlay_nav(_dir) {
    scm_comp__overlay_flush();
    var _n = array_length(global.__comp_ov_matches);
    if (_n == 0) return;
    global.__comp_ov_sel = (global.__comp_ov_sel + _dir + _n) mod _n;
    // Update page to keep selection visible
    global.__comp_ov_page = global.__comp_ov_sel div global.__comp_ov_per_page;
}

/// Draw the overlay popup (centered on screen).
///
/// _cw:     character width
/// _lh:     line height
/// _colors: struct { bg, bg_sel, text, text_sel, text_dim, border }
function scm_comp_overlay_draw(_cw, _lh, _colors) {
    if (!global.__comp_ov_active) return;
    scm_comp__overlay_flush();

    var _input = global.__comp_ov_input;
    var _matches = global.__comp_ov_matches;
    var _n = array_length(_matches);
    var _per_page = global.__comp_ov_per_page;
    var _sel = global.__comp_ov_sel;
    var _page = global.__comp_ov_page;

    // Layout constants
    var _pad_x = 8;
    var _pad_y = 4;
    var _input_h = _lh + _pad_y * 2;   // input row height
    var _sep_h = 1;                      // separator line
    var _row_h = _lh;
    var _visible_count = min(_n, _per_page);
    var _has_results = (_visible_count > 0);
    var _footer_h = _has_results ? _row_h : 0;
    // "No matches" text needs space when input is non-empty but no results
    var _no_results_h = (!_has_results && string_length(_input) > 0) ? (_row_h + _pad_y) : 0;

    // Popup width: fixed at 60 columns or max name length
    var _max_name_len = 0;
    var _page_start = _page * _per_page;
    var _page_end = min(_page_start + _per_page, _n);
    for (var _i = _page_start; _i < _page_end; _i++) {
        var _len = string_length(_matches[_i].name);
        if (_len > _max_name_len) _max_name_len = _len;
    }
    var _min_cols = 50;
    var _cols = max(_min_cols, _max_name_len + 10); // +10 for [tag] column
    var _popup_w = _cols * _cw;
    var _list_h = _visible_count * _row_h;
    var _popup_h = _input_h + _sep_h + _list_h + _footer_h + _no_results_h + _pad_y;

    // Center on screen
    var _gw = display_get_gui_width();
    var _gh = display_get_gui_height();
    var _ox = floor((_gw - _popup_w - _pad_x * 2) / 2);
    var _oy = floor(_gh * 0.2); // 20% from top
    var _outer_w = _popup_w + _pad_x * 2;
    var _outer_h = _popup_h + _pad_y;
    if (_ox < 8) _ox = 8;
    if (_oy < 8) _oy = 8;

    // Background + border
    scm_ui_panel(_ox, _oy, _ox + _outer_w, _oy + _outer_h, _colors.bg, _colors.border);

    // ── Input row ───────────────────────────────────────────────
    var _ix = _ox + _pad_x;
    var _iy = _oy + _pad_y;
    // Prompt: "> "
    scm_ui_text_dim(_ix, _iy, "> ", _colors.text_dim);
    var _prompt_w = 2 * _cw;
    // Input text
    if (string_length(_input) > 0) {
        scm_ui_text(_ix + _prompt_w, _iy, _input, _colors.text);
    } else {
        // Placeholder
        var _ph;
        if (global.__comp_ov_has_completer) {
            _ph = "Search env + dict...";
        } else {
            _ph = "Search env...";
        }
        scm_ui_text_dim(_ix + _prompt_w, _iy, _ph, _colors.text_dim);
    }
    // Cursor
    var _cursor_x = _ix + _prompt_w + string_length(_input) * _cw;
    scm_ui_cursor(_cursor_x, _iy, _lh, _colors.text, 400);

    // ── Separator ───────────────────────────────────────────────
    var _sep_y = _iy + _input_h;
    scm_ui_fill(_ox, _sep_y, _ox + _outer_w, _sep_y + _sep_h, _colors.border, 0.5);

    // ── Results list ────────────────────────────────────────────
    if (_has_results) {
        var _ly = _sep_y + _sep_h;
        var _total_pages = (_n + _per_page - 1) div _per_page;

        for (var _i = _page_start; _i < _page_end; _i++) {
            var _row_y = _ly + (_i - _page_start) * _row_h;
            var _is_sel = (_i == _sel);

            // Selection highlight
            if (_is_sel) {
                scm_ui_fill(_ox + 1, _row_y, _ox + _outer_w - 1,
                            _row_y + _row_h, _colors.bg_sel, 1.0);
            }

            var _text_color = _is_sel ? _colors.text_sel : _colors.text;
            var _name = _matches[_i].name;
            scm_ui_text(_ix + _cw, _row_y, _name, _text_color);

            // [tag] column — show dict tag for dict results
            var _dtag = _matches[_i].dict_tag;
            if (_dtag != "") {
                var _tag = "[" + _dtag + "]";
                var _tag_x = _ix + _popup_w - (string_length(_tag) + 1) * _cw;
                scm_ui_text_dim(_tag_x, _row_y, _tag, _colors.text_dim);
            }
        }

        // Footer
        var _footer_y = _ly + _list_h;
        var _mode_label;
        if (global.__comp_ov_mode == "all") {
            _mode_label = "ALL";
        } else if (global.__comp_ov_mode == "string") {
            _mode_label = "STRING";
        } else {
            _mode_label = "ENV";
        }
        var _shown = min(_n, 200);
        var _footer;
        if (_total_pages > 1) {
            _footer = "[" + _mode_label + "] "
                    + string(_page + 1) + "/" + string(_total_pages)
                    + " (" + string(_shown) + " matches)";
        } else {
            _footer = "[" + _mode_label + "] " + string(_shown) + " matches";
        }
        scm_ui_text_dim(_ix + _cw, _footer_y, _footer, _colors.text_dim);
    } else if (string_length(_input) > 0) {
        // No results message
        var _nr_y = _sep_y + _sep_h + _pad_y;
        scm_ui_text_dim(_ix + _cw, _nr_y, "No matches", _colors.text_dim);
    }
}
