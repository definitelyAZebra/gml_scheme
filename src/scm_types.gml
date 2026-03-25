/// scm_types.gml — Scheme value representation
///
/// Tagged-struct approach: every Scheme value is a GML struct with a .t (type) field.
/// GMS2.3+ structs are garbage-collected, so no manual memory management needed.
///
/// !! UMT BYTECODE 17 — FORBIDDEN SYNTAX (build.py lint enforced):
///    [$]  [?]  [@]  struct_set()  is_instanceof()
///    Use: variable_struct_get/set, ds_map_find_value/set, array_get/set

// ── Type tags ────────────────────────────────────────────────────────
#macro SCM_NIL     0
#macro SCM_BOOL    1
#macro SCM_NUM     2
#macro SCM_STR     3
#macro SCM_SYM     4
#macro SCM_PAIR    5
#macro SCM_FN      6   // built-in procedure
#macro SCM_LAMBDA  7   // user-defined closure
#macro SCM_VOID    8
#macro SCM_ERR     9
#macro SCM_HANDLE  10  // opaque GML handle (array, struct, ds_map, etc.)
#macro SCM_CASE_LAMBDA 11  // case-lambda (multiple arity clauses)
#macro SCM_PORT    12  // I/O port (string or file)
#macro SCM_EOF     13  // eof-object singleton

// ── Port direction & kind ───────────────────────────────────────────
#macro SCM_PORT_IN      0
#macro SCM_PORT_OUT     1
#macro SCM_PORT_STRING  0
#macro SCM_PORT_FILE    1
#macro SCM_PORT_CONSOLE 2
#macro SCM_PORT_DEBUG   3   // error port → show_debug_message (line-buffered)

// ── Handle sub-types ────────────────────────────────────────────────
// Only types that GML can reliably detect at runtime via is_array()/is_struct().
// ds_map, ds_list, and instance IDs are plain numbers in GML bytecode 17;
// wrapping them in SCM_HANDLE would create an inconsistent type system
// (the tag survives only when created by our builtins, not when round-tripped
// through ds_map_find_value / variable_instance_get / etc.).
#macro SCM_HT_ARRAY    0
#macro SCM_HT_STRUCT   1
#macro SCM_HT_METHOD   2

// ── Sentinel tag (round-trip detection) ─────────────────────────────
// Every Scheme value carries `__tag: global.__scm_tag` so that scm_wrap()
// can recognise structs that are already Scheme values and NOT re-wrap
// them as SCM_HANDLE(STRUCT).
// Sentinel is a plain struct — reference equality is enough to detect it.
// (Avoids is_instanceof which requires GMS 2022.8+.)
global.__scm_tag = {};

/// Return true if _val is a tagged Scheme value.
function scm__is_tagged(_val) {
    return is_struct(_val)
        && variable_struct_exists(_val, "__tag")
        && variable_struct_get(_val, "__tag") == global.__scm_tag;
}

// ── Singletons ──────────────────────────────────────────────────────
global.__scm_nil   = { __tag: global.__scm_tag, t: SCM_NIL };
global.__scm_true  = { __tag: global.__scm_tag, t: SCM_BOOL, v: true };
global.__scm_false = { __tag: global.__scm_tag, t: SCM_BOOL, v: false };
global.__scm_void  = { __tag: global.__scm_tag, t: SCM_VOID };
global.__scm_eof   = { __tag: global.__scm_tag, t: SCM_EOF };

// ── Console port singleton ──────────────────────────────────────────
// Created early so current-output-port works before scm_init().
global.__scm_console_out = {
    __tag: global.__scm_tag, t: SCM_PORT,
    dir: SCM_PORT_OUT, kind: SCM_PORT_CONSOLE,
    buf: "", pos: 0, fid: -1, closed: false
};

// ── Debug (error) port singleton ────────────────────────────────────
// Maps to show_debug_message, line-buffered like console port.
global.__scm_debug_out = {
    __tag: global.__scm_tag, t: SCM_PORT,
    dir: SCM_PORT_OUT, kind: SCM_PORT_DEBUG,
    buf: "", pos: 0, fid: -1, closed: false
};

// ── Symbol intern table ─────────────────────────────────────────────
global.__scm_sym_table = {};

// ── Global macro table (define-macro writes here) ──────────────────
global.__scm_macros = {};

// ── Small integer cache (-1 .. 256) ────────────────────────────────
global.__scm_small_int_lo = -1;
global.__scm_small_int_hi = 256;
global.__scm_small_ints = array_create(258);  // indices 0..257 → values -1..256
for (var _i = 0; _i < 258; _i++) {
    global.__scm_small_ints[_i] = { __tag: global.__scm_tag, t: SCM_NUM, v: _i + global.__scm_small_int_lo };
}

// ── Constructors ────────────────────────────────────────────────────

function scm_nil() {
    return global.__scm_nil;
}

function scm_bool(_v) {
    return _v ? global.__scm_true : global.__scm_false;
}

function scm_num(_v) {
    // Small integer cache: return pre-allocated struct for -1..256
    if (_v == (_v | 0) && _v >= global.__scm_small_int_lo && _v <= global.__scm_small_int_hi) {
        return global.__scm_small_ints[_v - global.__scm_small_int_lo];
    }
    return { __tag: global.__scm_tag, t: SCM_NUM, v: _v };
}

function scm_str(_v) {
    return { __tag: global.__scm_tag, t: SCM_STR, v: _v };
}

function scm_sym(_name) {
    // Symbol interning: reuse existing struct for same name
    var _tbl = global.__scm_sym_table;
    var _existing = variable_struct_get(_tbl, _name);
    if (_existing != undefined) return _existing;
    var _sym = { __tag: global.__scm_tag, t: SCM_SYM, v: _name };
    variable_struct_set(_tbl, _name, _sym);
    return _sym;
}

function scm_cons(_car, _cdr) {
    return { __tag: global.__scm_tag, t: SCM_PAIR, car: _car, cdr: _cdr };
}

/// Create a built-in procedure.
/// _fn takes a single Scheme list (the evaluated arguments) and returns a Scheme value.
function scm_fn(_name, _func) {
    return { __tag: global.__scm_tag, t: SCM_FN, name: _name, fn: _func };
}

/// Create a user-defined closure (lambda).
function scm_lambda(_params, _body, _env, _name) {
    return { __tag: global.__scm_tag, t: SCM_LAMBDA, params: _params, body: _body, env: _env,
             name: (_name != undefined) ? _name : "<lambda>" };
}

/// Create a case-lambda (multiple arity clauses).
/// _clauses: GML array of { params, body } structs.
function scm_case_lambda(_clauses, _env, _name) {
    return { __tag: global.__scm_tag, t: SCM_CASE_LAMBDA, clauses: _clauses, env: _env,
             name: (_name != undefined) ? _name : "<case-lambda>" };
}

function scm_eof() {
    return global.__scm_eof;
}

/// Create an I/O port.
/// _dir: SCM_PORT_IN or SCM_PORT_OUT.
/// _kind: SCM_PORT_STRING, SCM_PORT_FILE, or SCM_PORT_CONSOLE.
function scm_port(_dir, _kind) {
    return { __tag: global.__scm_tag, t: SCM_PORT,
             dir: _dir, kind: _kind,
             buf: "", pos: 0, fid: -1, closed: false };
}

function scm_void() {
    return global.__scm_void;
}

function scm_err(_msg) {
    return { __tag: global.__scm_tag, t: SCM_ERR, v: _msg };
}

/// Create an opaque handle wrapping a GML value.
/// _ht is a SCM_HT_* sub-type constant.
function scm_handle(_gml_val, _ht) {
    return { __tag: global.__scm_tag, t: SCM_HANDLE, v: _gml_val, ht: _ht };
}

// ── Predicates ──────────────────────────────────────────────────────

function scm_is_nil(_v)    { return _v.t == SCM_NIL; }
function scm_is_bool(_v)   { return _v.t == SCM_BOOL; }
function scm_is_num(_v)    { return _v.t == SCM_NUM; }
function scm_is_str(_v)    { return _v.t == SCM_STR; }
function scm_is_sym(_v)    { return _v.t == SCM_SYM; }
function scm_is_pair(_v)   { return _v.t == SCM_PAIR; }
function scm_is_fn(_v)     { return _v.t == SCM_FN; }
function scm_is_lambda(_v) { return _v.t == SCM_LAMBDA; }
function scm_is_void(_v)   { return _v.t == SCM_VOID; }
function scm_is_err(_v)    { return _v.t == SCM_ERR; }
function scm_is_handle(_v) { return _v.t == SCM_HANDLE; }

/// Scheme truthiness: everything except #f is truthy.
function scm_is_truthy(_v) {
    return !(_v.t == SCM_BOOL && _v.v == false);
}

function scm_is_proc(_v) {
    return _v.t == SCM_FN || _v.t == SCM_LAMBDA || _v.t == SCM_CASE_LAMBDA
        || (_v.t == SCM_HANDLE && _v.ht == SCM_HT_METHOD);
}

function scm_is_list(_v) {
    while (_v.t == SCM_PAIR) _v = _v.cdr;
    return _v.t == SCM_NIL;
}

/// Return the human-readable name of a type tag.
function scm__type_name(_t) {
    switch (_t) {
        case SCM_NIL:    return "nil";
        case SCM_BOOL:   return "boolean";
        case SCM_NUM:    return "number";
        case SCM_STR:    return "string";
        case SCM_SYM:    return "symbol";
        case SCM_PAIR:   return "pair";
        case SCM_FN:     return "builtin";
        case SCM_LAMBDA: return "lambda";
        case SCM_CASE_LAMBDA: return "case-lambda";
        case SCM_PORT:   return "port";
        case SCM_EOF:    return "eof";
        case SCM_VOID:   return "void";
        case SCM_ERR:    return "error";
        case SCM_HANDLE: return "handle";
        default:         return "unknown";
    }
}

// ── Pair accessors ──────────────────────────────────────────────────

function scm_car(_v)           { return _v.car; }
function scm_cdr(_v)           { return _v.cdr; }
function scm_set_car(_v, _x)   { _v.car = _x; }
function scm_set_cdr(_v, _x)   { _v.cdr = _x; }

function scm_cadr(_v)  { return _v.cdr.car; }
function scm_cddr(_v)  { return _v.cdr.cdr; }
function scm_caddr(_v) { return _v.cdr.cdr.car; }

// ── List helpers ────────────────────────────────────────────────────

function scm_list_len(_lst) {
    var _n = 0;
    while (_lst.t == SCM_PAIR) { _n++; _lst = _lst.cdr; }
    return _n;
}

function scm_list_ref(_lst, _n) {
    for (var _i = 0; _i < _n; _i++) _lst = _lst.cdr;
    return _lst.car;
}

function scm_list_reverse(_lst) {
    var _result = scm_nil();
    while (_lst.t == SCM_PAIR) {
        _result = scm_cons(_lst.car, _result);
        _lst = _lst.cdr;
    }
    return _result;
}

/// Convert a GML array to a Scheme list.
function scm_array_to_list(_arr) {
    var _result = scm_nil();
    for (var _i = array_length(_arr) - 1; _i >= 0; _i--) {
        _result = scm_cons(_arr[_i], _result);
    }
    return _result;
}

/// Convert a Scheme list to a GML array.
function scm_list_to_array(_lst) {
    var _arr = [];
    while (_lst.t == SCM_PAIR) {
        array_push(_arr, _lst.car);
        _lst = _lst.cdr;
    }
    return _arr;
}

// ── Deep equality ───────────────────────────────────────────────────

function scm_equal(_a, _b) {
    if (_a == _b) return true;  // fast path: same struct (interned syms, cached ints)
    if (_a.t != _b.t) return false;
    switch (_a.t) {
        case SCM_NIL:    return true;
        case SCM_BOOL:   return _a.v == _b.v;
        case SCM_NUM:    return _a.v == _b.v;
        case SCM_STR:    return _a.v == _b.v;
        case SCM_SYM:    return false;  // interned: same name → same struct → caught above
        case SCM_PAIR:   return scm_equal(_a.car, _b.car) && scm_equal(_a.cdr, _b.cdr);
        case SCM_HANDLE: return _a.v == _b.v;
        default:         return false;
    }
}

// ── GML ↔ Scheme conversion ────────────────────────────────────────

/// Wrap a GML value into a Scheme value.
/// Round-trip guard: if the value is already a tagged Scheme struct, return it as-is.
function scm_wrap(_gml_val) {
    if (is_undefined(_gml_val)) return scm_nil();
    if (is_bool(_gml_val))      return scm_bool(_gml_val);
    if (is_real(_gml_val))       return scm_num(_gml_val);
    if (is_int32(_gml_val))      return scm_num(_gml_val);
    if (is_int64(_gml_val))      return scm_num(_gml_val);
    if (is_string(_gml_val))     return scm_str(_gml_val);
    if (is_array(_gml_val))      return scm_handle(_gml_val, SCM_HT_ARRAY);
    if (is_method(_gml_val))     return scm_handle(_gml_val, SCM_HT_METHOD);
    if (is_struct(_gml_val)) {
        if (scm__is_tagged(_gml_val)) return _gml_val;
        return scm_handle(_gml_val, SCM_HT_STRUCT);
    }
    return scm_num(_gml_val);
}

/// Unwrap a Scheme value to a GML value.
function scm_unwrap(_scm_val) {
    switch (_scm_val.t) {
        case SCM_NIL:    return undefined;
        case SCM_BOOL:   return _scm_val.v;
        case SCM_NUM:    return _scm_val.v;
        case SCM_STR:    return _scm_val.v;
        case SCM_SYM:    return _scm_val.v;
        case SCM_HANDLE: return _scm_val.v;
        case SCM_VOID:   return undefined;
        default:         return _scm_val;  // return struct as-is
    }
}

/// Deep-unwrap: recursively convert Scheme values to GML-native values.
/// - PAIR  → GML array (recursive)
/// - FN/LAMBDA → GML method (closure-based, self stays free)
/// - ERR   → undefined (logged)
/// - others → scm_unwrap
function scm_deep_unwrap(_scm_val) {
    switch (_scm_val.t) {
        case SCM_PAIR:
            // Convert list/pair to GML array, recursively deep-unwrapping elements
            var _arr = [];
            var _p = _scm_val;
            while (_p.t == SCM_PAIR) {
                array_push(_arr, scm_deep_unwrap(_p.car));
                _p = _p.cdr;
            }
            // Improper list: last cdr is not nil, append it
            if (_p.t != SCM_NIL) {
                array_push(_arr, scm_deep_unwrap(_p));
            }
            return _arr;
        case SCM_FN:
        case SCM_LAMBDA:
        case SCM_CASE_LAMBDA:
            return scm__proc_to_method(_scm_val);
        case SCM_ERR:
            show_debug_message("[scm] deep_unwrap error: " + _scm_val.v);
            return undefined;
        default:
            return scm_unwrap(_scm_val);
    }
}

/// Deep-wrap: recursively convert GML-native values to Scheme values.
/// - GML array → Scheme list (recursive)
/// - others → scm_wrap
function scm_deep_wrap(_gml_val) {
    if (is_array(_gml_val)) {
        var _result = scm_nil();
        for (var _i = array_length(_gml_val) - 1; _i >= 0; _i--) {
            _result = scm_cons(scm_deep_wrap(_gml_val[_i]), _result);
        }
        return _result;
    }
    return scm_wrap(_gml_val);
}

/// Convert a Scheme procedure (FN or LAMBDA) to a GML callable.
/// Uses a bare function() closure so that `self` is NOT locked —
/// the caller can freely rebind via method(instance, fn).
function scm__proc_to_method(_scm_proc) {
    return function() {
        var _scm_args = scm_nil();
        for (var _i = argument_count - 1; _i >= 0; _i--) {
            _scm_args = scm_cons(scm_wrap(argument[_i]), _scm_args);
        }
        var _result = scm_apply(_scm_proc, _scm_args);
        if (_result.t == SCM_ERR) {
            show_debug_message("[scm] callback error: " + _result.v);
            return undefined;
        }
        return scm_deep_unwrap(_result);
    };
}
