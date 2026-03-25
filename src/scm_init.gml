/// scm_init.gml — Initialization, output buffer, and entry points
///
/// Call scm_init() once at game start to set up the interpreter.
/// Then use scm_eval_string("(+ 1 2)") to evaluate expressions.

// ═══════════════════════════════════════════════════════════════════
//  Trace logging (file + debug console)
// ═══════════════════════════════════════════════════════════════════

/// Write a trace message to scm_trace.log (auto-flushed) and debug console.
/// The log file is created in the game's working directory.
/// Each call opens, appends, and closes the file — safe even if process is killed.
function scm_trace(_msg) {
    show_debug_message(_msg);
}

// ═══════════════════════════════════════════════════════════════════
//  Output buffer
// ═══════════════════════════════════════════════════════════════════

/// Write a string to the Scheme output buffer + debug log.
function scm_output_write(_str) {
    // Accumulate into current line
    global.__scm_line_buf += _str;

    // Flush complete lines
    var _nl = string_pos("\n", global.__scm_line_buf);
    while (_nl > 0) {
        var _line = string_copy(global.__scm_line_buf, 1, _nl - 1);
        array_push(global.__scm_output, _line);
        scm_trace("[scm] " + _line);

        // Trim buffer
        global.__scm_line_buf = string_copy(
            global.__scm_line_buf,
            _nl + 1,
            string_length(global.__scm_line_buf) - _nl
        );
        _nl = string_pos("\n", global.__scm_line_buf);
    }

    // Cap output history
    while (array_length(global.__scm_output) > global.__scm_output_max) {
        array_delete(global.__scm_output, 0, 1);
    }
}

/// Flush any remaining text in the line buffer (no trailing newline).
function scm_output_flush() {
    if (global.__scm_line_buf != "") {
        array_push(global.__scm_output, global.__scm_line_buf);
        scm_trace("[scm] " + global.__scm_line_buf);
        global.__scm_line_buf = "";
    }
}

/// Clear all output.
function scm_output_clear() {
    global.__scm_output  = [];
    global.__scm_line_buf = "";
}

/// Get the output buffer as a GML array of strings.
function scm_output_get() {
    return global.__scm_output;
}

// ═══════════════════════════════════════════════════════════════════
//  Prelude (standard library in Scheme)
// ═══════════════════════════════════════════════════════════════════

function scm__load_prelude(_env) {
    var _prelude = "@@PRELUDE@@";

    scm_eval_program(_prelude, _env);
}

function scm__load_stdlib(_env) {
    var _stdlib = "@@STDLIB@@";

    scm_eval_program(_stdlib, _env);
}

// ═══════════════════════════════════════════════════════════════════
//  Initialization
// ═══════════════════════════════════════════════════════════════════

/// Initialize the Scheme interpreter. Call once at startup.
function scm_init() {
    // Output buffer
    global.__scm_output     = [];
    global.__scm_output_max = 10000;
    global.__scm_line_buf   = "";

    // Eval fuel (step limit to prevent infinite loops)
    global.__scm_fuel       = 0;
    global.__scm_fuel_limit = 1000000;  // 1M steps per top-level eval

    // Global environment
    global.scm_env = scm_env_new(undefined);

    // Register builtins
    scm_register_core(global.scm_env);
    scm_register_gml_builtins(global.scm_env);
    scm_register_bridge(global.scm_env);

    // Load prelude (R5RS standard library)
    scm__load_prelude(global.scm_env);

    // Load stdlib (GML interop & game domain)
    scm__load_stdlib(global.scm_env);

    scm_trace("[scm] Scheme interpreter initialized.");
}

// ═══════════════════════════════════════════════════════════════════
//  Public API
// ═══════════════════════════════════════════════════════════════════

/// Evaluate a single Scheme expression string. Returns the Scheme result value.
function scm_eval_string(_src) {
    global.__scm_fuel = global.__scm_fuel_limit;
    var _t0 = get_timer();
    var _expr = scm_read_string(_src);
    if (scm_is_err(_expr)) return _expr;
    var _result = scm_eval(_expr, global.scm_env);
    var _dt = (get_timer() - _t0) div 1000;
    var _used = global.__scm_fuel_limit - global.__scm_fuel;
    // Only trace if took >1ms (avoid flooding on trivial evals)
    if (_dt > 1) {
        var _preview = _src;
        if (string_length(_preview) > 60)
            _preview = string_copy(_preview, 1, 60) + "...";
        scm_trace("[scm-eval] " + string(_dt) + "ms fuel=" + string(_used) + " | " + _preview);
    }
    return _result;
}

/// Evaluate a program (multiple top-level expressions). Returns the last result.
function scm_eval_program(_src, _env) {
    if (is_undefined(_env)) _env = global.scm_env;
    global.__scm_fuel = global.__scm_fuel_limit;
    var _t0 = get_timer();
    var _exprs = scm_read_all(_src);
    var _result = scm_void();
    for (var _i = 0; _i < array_length(_exprs); _i++) {
        if (scm_is_err(_exprs[_i])) return _exprs[_i];
        _result = scm_eval(_exprs[_i], _env);
        if (scm_is_err(_result)) return _result;
    }
    var _dt = (get_timer() - _t0) div 1000;
    var _used = global.__scm_fuel_limit - global.__scm_fuel;
    scm_trace("[scm-prog] " + string(_dt) + "ms fuel=" + string(_used) + " exprs=" + string(array_length(_exprs)));
    return _result;
}

/// Evaluate a .scm file from disk. Returns the last result.
function scm_eval_file(_path) {
    if (!file_exists(_path)) return scm_err("file not found: " + _path);

    var _buf = buffer_load(_path);
    var _src = buffer_read(_buf, buffer_string);
    buffer_delete(_buf);

    return scm_eval_program(_src, global.scm_env);
}

/// REPL-style eval: evaluate, print result, return result.
function scm_repl_eval(_input) {
    scm_output_write("> " + _input + "\n");

    var _result = scm_eval_string(_input);
    scm_output_flush();

    if (!scm_is_void(_result)) {
        scm_output_write(scm_write_str(_result) + "\n");
    }

    return _result;
}

// ── Auto-initialize on bundle load ──────────────────────────────────
// UMT-injected code has no function hoisting, so cross-function calls
// between source files are unreliable. Auto-init as top-level code
// ensures global.scm_env is ready before any object uses the REPL.
scm_init();
