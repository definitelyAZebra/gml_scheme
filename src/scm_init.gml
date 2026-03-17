/// scm_init.gml — Initialization, output buffer, and entry points
///
/// Call scm_init() once at game start to set up the interpreter.
/// Then use scm_eval_string("(+ 1 2)") to evaluate expressions.

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
        show_debug_message("[scm] " + _line);

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
        show_debug_message("[scm] " + global.__scm_line_buf);
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

// ═══════════════════════════════════════════════════════════════════
//  Initialization
// ═══════════════════════════════════════════════════════════════════

/// Initialize the Scheme interpreter. Call once at startup.
function scm_init() {
    // Output buffer
    global.__scm_output     = [];
    global.__scm_output_max = 200;
    global.__scm_line_buf   = "";

    // Global environment
    global.scm_env = scm_env_new(undefined);

    // Register builtins
    scm_register_core(global.scm_env);
    scm_register_gml_builtins(global.scm_env);
    scm_register_bridge(global.scm_env);

    // Load prelude
    scm__load_prelude(global.scm_env);

    show_debug_message("[scm] Scheme interpreter initialized.");
}

// ═══════════════════════════════════════════════════════════════════
//  Public API
// ═══════════════════════════════════════════════════════════════════

/// Evaluate a single Scheme expression string. Returns the Scheme result value.
function scm_eval_string(_src) {
    var _expr = scm_read_string(_src);
    if (scm_is_err(_expr)) return _expr;
    return scm_eval(_expr, global.scm_env);
}

/// Evaluate a program (multiple top-level expressions). Returns the last result.
function scm_eval_program(_src, _env) {
    if (is_undefined(_env)) _env = global.scm_env;
    var _exprs = scm_read_all(_src);
    var _result = scm_void();
    for (var _i = 0; _i < array_length(_exprs); _i++) {
        if (scm_is_err(_exprs[_i])) return _exprs[_i];
        _result = scm_eval(_exprs[_i], _env);
        if (scm_is_err(_result)) return _result;
    }
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

/// Run a quick self-test to verify the interpreter works.
function scm_self_test() {
    scm_init();

    var _tests = [
        ["(+ 1 2 3)", "6"],
        ["(* 2 3 4)", "24"],
        ["(- 10 3)", "7"],
        ["(/ 10 2)", "5"],
        ["(if #t 'yes 'no)", "yes"],
        ["(if #f 'yes 'no)", "no"],
        ["(car '(1 2 3))", "1"],
        ["(cdr '(1 2 3))", "(2 3)"],
        ["(length '(a b c))", "3"],
        ["(map (lambda (x) (* x x)) '(1 2 3))", "(1 4 9)"],
        ["(filter (lambda (x) (> x 2)) '(1 2 3 4 5))", "(3 4 5)"],
        ["(let ((x 10) (y 20)) (+ x y))", "30"],
        ["(let loop ((n 5) (acc 1)) (if (= n 0) acc (loop (- n 1) (* acc n))))", "120"],
        ["(define (fact n) (if (<= n 1) 1 (* n (fact (- n 1))))) (fact 10)", "3628800"],
        ["(string-append \"hello\" \" \" \"world\")", "\"hello world\""],
        ["(equal? '(1 2 3) '(1 2 3))", "#t"],
        // Error checking tests (must return errors, not crash)
        ["(car 5)", "#<error:"],
        ["(cdr \"hello\")", "#<error:"],
        ["(+ 1 \"a\")", "#<error:"],
        ["(- \"x\" 1)", "#<error:"],
        ["(* 2 #t)", "#<error:"],
        ["(< 1 \"2\")", "#<error:"],
        ["(string-length 42)", "#<error:"],
        ["(string-append \"a\" 1)", "#<error:"],
        ["(abs #f)", "#<error:"],
        ["(modulo \"a\" 2)", "#<error:"],
        ["((lambda (x) x) 1 2)", "#<error:"],
        ["((lambda (x y) x) 1)", "#<error:"],
    ];

    var _pass = 0;
    var _fail = 0;

    for (var _i = 0; _i < array_length(_tests); _i++) {
        var _input    = _tests[_i][0];
        var _expected = _tests[_i][1];

        // Some tests have multiple expressions (define + use)
        var _result;
        if (string_pos(") (", _input) > 0) {
            _result = scm_eval_program(_input, global.scm_env);
        } else {
            _result = scm_eval_string(_input);
        }
        var _actual = scm_write_str(_result);

        // Prefix match for error tests (expected starts with "#<error:")
        var _match = false;
        if (string_pos("#<error:", _expected) == 1) {
            _match = (string_pos("#<error:", _actual) == 1);
        } else {
            _match = (_actual == _expected);
        }

        if (_match) {
            _pass++;
        } else {
            _fail++;
            show_debug_message("[scm-test] FAIL: " + _input);
            show_debug_message("  expected: " + _expected);
            show_debug_message("  actual:   " + _actual);
        }
    }

    show_debug_message("[scm-test] " + string(_pass) + " passed, " + string(_fail) + " failed");
    return _fail == 0;
}
