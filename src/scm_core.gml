/// scm_core.gml — Core built-in procedures
///
/// All builtins receive a Scheme list of already-evaluated arguments.
/// Register them into an environment with scm_register_core(_env).

// ═══════════════════════════════════════════════════════════════════
//  Arithmetic
// ═══════════════════════════════════════════════════════════════════

function scm_bi_add(_args) {
    var _sum = 0;
    while (_args.t == SCM_PAIR) {
        if (_args.car.t != SCM_NUM) return scm_err("+: expected number, got " + scm__type_name(_args.car.t));
        _sum += _args.car.v; _args = _args.cdr;
    }
    return scm_num(_sum);
}

function scm_bi_sub(_args) {
    if (_args.car.t != SCM_NUM) return scm_err("-: expected number, got " + scm__type_name(_args.car.t));
    if (_args.cdr.t == SCM_NIL) return scm_num(-_args.car.v);  // (- x)
    var _r = _args.car.v;
    _args = _args.cdr;
    while (_args.t == SCM_PAIR) {
        if (_args.car.t != SCM_NUM) return scm_err("-: expected number, got " + scm__type_name(_args.car.t));
        _r -= _args.car.v; _args = _args.cdr;
    }
    return scm_num(_r);
}

function scm_bi_mul(_args) {
    var _prod = 1;
    while (_args.t == SCM_PAIR) {
        if (_args.car.t != SCM_NUM) return scm_err("*: expected number, got " + scm__type_name(_args.car.t));
        _prod *= _args.car.v; _args = _args.cdr;
    }
    return scm_num(_prod);
}

function scm_bi_div(_args) {
    if (_args.car.t != SCM_NUM) return scm_err("/: expected number, got " + scm__type_name(_args.car.t));
    if (_args.cdr.t == SCM_NIL) {
        if (_args.car.v == 0) return scm_err("/: division by zero");
        return scm_num(1 / _args.car.v);
    }
    var _r = _args.car.v;
    _args = _args.cdr;
    while (_args.t == SCM_PAIR) {
        if (_args.car.t != SCM_NUM) return scm_err("/: expected number, got " + scm__type_name(_args.car.t));
        if (_args.car.v == 0) return scm_err("/: division by zero");
        _r /= _args.car.v;
        _args = _args.cdr;
    }
    return scm_num(_r);
}

function scm_bi_modulo(_args) {
    if (_args.car.t != SCM_NUM) return scm_err("modulo: expected number, got " + scm__type_name(_args.car.t));
    var _b = scm_cadr(_args);
    if (_b.t != SCM_NUM) return scm_err("modulo: expected number, got " + scm__type_name(_b.t));
    return scm_num(_args.car.v mod _b.v);
}

function scm_bi_min(_args) {
    if (_args.car.t != SCM_NUM) return scm_err("min: expected number, got " + scm__type_name(_args.car.t));
    var _r = _args.car.v;
    _args = _args.cdr;
    while (_args.t == SCM_PAIR) {
        if (_args.car.t != SCM_NUM) return scm_err("min: expected number, got " + scm__type_name(_args.car.t));
        _r = min(_r, _args.car.v); _args = _args.cdr;
    }
    return scm_num(_r);
}

function scm_bi_max(_args) {
    if (_args.car.t != SCM_NUM) return scm_err("max: expected number, got " + scm__type_name(_args.car.t));
    var _r = _args.car.v;
    _args = _args.cdr;
    while (_args.t == SCM_PAIR) {
        if (_args.car.t != SCM_NUM) return scm_err("max: expected number, got " + scm__type_name(_args.car.t));
        _r = max(_r, _args.car.v); _args = _args.cdr;
    }
    return scm_num(_r);
}

// ═══════════════════════════════════════════════════════════════════
//  Numeric comparison (chainable: (< 1 2 3) → #t)
// ═══════════════════════════════════════════════════════════════════

function scm_bi_num_eq(_args) {
    if (_args.car.t != SCM_NUM) return scm_err("=: expected number, got " + scm__type_name(_args.car.t));
    var _prev = _args.car.v; _args = _args.cdr;
    while (_args.t == SCM_PAIR) {
        if (_args.car.t != SCM_NUM) return scm_err("=: expected number, got " + scm__type_name(_args.car.t));
        if (_prev != _args.car.v) return scm_bool(false);
        _prev = _args.car.v; _args = _args.cdr;
    }
    return scm_bool(true);
}

function scm_bi_lt(_args) {
    if (_args.car.t != SCM_NUM) return scm_err("<: expected number, got " + scm__type_name(_args.car.t));
    var _prev = _args.car.v; _args = _args.cdr;
    while (_args.t == SCM_PAIR) {
        if (_args.car.t != SCM_NUM) return scm_err("<: expected number, got " + scm__type_name(_args.car.t));
        if (!(_prev < _args.car.v)) return scm_bool(false);
        _prev = _args.car.v; _args = _args.cdr;
    }
    return scm_bool(true);
}

function scm_bi_gt(_args) {
    if (_args.car.t != SCM_NUM) return scm_err(">: expected number, got " + scm__type_name(_args.car.t));
    var _prev = _args.car.v; _args = _args.cdr;
    while (_args.t == SCM_PAIR) {
        if (_args.car.t != SCM_NUM) return scm_err(">: expected number, got " + scm__type_name(_args.car.t));
        if (!(_prev > _args.car.v)) return scm_bool(false);
        _prev = _args.car.v; _args = _args.cdr;
    }
    return scm_bool(true);
}

function scm_bi_le(_args) {
    if (_args.car.t != SCM_NUM) return scm_err("<=: expected number, got " + scm__type_name(_args.car.t));
    var _prev = _args.car.v; _args = _args.cdr;
    while (_args.t == SCM_PAIR) {
        if (_args.car.t != SCM_NUM) return scm_err("<=: expected number, got " + scm__type_name(_args.car.t));
        if (!(_prev <= _args.car.v)) return scm_bool(false);
        _prev = _args.car.v; _args = _args.cdr;
    }
    return scm_bool(true);
}

function scm_bi_ge(_args) {
    if (_args.car.t != SCM_NUM) return scm_err(">=: expected number, got " + scm__type_name(_args.car.t));
    var _prev = _args.car.v; _args = _args.cdr;
    while (_args.t == SCM_PAIR) {
        if (_args.car.t != SCM_NUM) return scm_err(">=: expected number, got " + scm__type_name(_args.car.t));
        if (!(_prev >= _args.car.v)) return scm_bool(false);
        _prev = _args.car.v; _args = _args.cdr;
    }
    return scm_bool(true);
}

// ═══════════════════════════════════════════════════════════════════
//  Boolean & predicates
// ═══════════════════════════════════════════════════════════════════

function scm_bi_not(_args)        { return scm_bool(!scm_is_truthy(_args.car)); }
function scm_bi_is_null(_args)    { return scm_bool(_args.car.t == SCM_NIL); }
function scm_bi_is_pair(_args)    { return scm_bool(_args.car.t == SCM_PAIR); }
function scm_bi_is_number(_args)  { return scm_bool(_args.car.t == SCM_NUM); }
function scm_bi_is_string(_args)  { return scm_bool(_args.car.t == SCM_STR); }
function scm_bi_is_symbol(_args)  { return scm_bool(_args.car.t == SCM_SYM); }
function scm_bi_is_boolean(_args) { return scm_bool(_args.car.t == SCM_BOOL); }
function scm_bi_is_list(_args)    { return scm_bool(scm_is_list(_args.car)); }
function scm_bi_is_zero(_args)    { return scm_bool(_args.car.t == SCM_NUM && _args.car.v == 0); }
function scm_bi_is_proc(_args)    { return scm_bool(scm_is_proc(_args.car)); }
function scm_bi_is_void(_args)    { return scm_bool(_args.car.t == SCM_VOID); }
function scm_bi_is_error(_args)   { return scm_bool(_args.car.t == SCM_ERR); }

function scm_bi_equal(_args) {
    return scm_bool(scm_equal(_args.car, scm_cadr(_args)));
}

function scm_bi_eq(_args) {
    var _a = _args.car;
    var _b = scm_cadr(_args);
    if (_a.t != _b.t) return scm_bool(false);
    switch (_a.t) {
        case SCM_NIL:  return scm_bool(true);
        case SCM_BOOL: return scm_bool(_a.v == _b.v);
        case SCM_NUM:  return scm_bool(_a.v == _b.v);
        case SCM_SYM:  return scm_bool(_a.v == _b.v);
        default:       return scm_bool(_a == _b);  // reference equality
    }
}

// ═══════════════════════════════════════════════════════════════════
//  List operations
// ═══════════════════════════════════════════════════════════════════

function scm_bi_cons(_args)    { return scm_cons(_args.car, scm_cadr(_args)); }
function scm_bi_car(_args) {
    if (_args.car.t != SCM_PAIR) return scm_err("car: expected pair, got " + scm__type_name(_args.car.t));
    return _args.car.car;
}
function scm_bi_cdr(_args) {
    if (_args.car.t != SCM_PAIR) return scm_err("cdr: expected pair, got " + scm__type_name(_args.car.t));
    return _args.car.cdr;
}
function scm_bi_set_car(_args) {
    if (_args.car.t != SCM_PAIR) return scm_err("set-car!: expected pair, got " + scm__type_name(_args.car.t));
    _args.car.car = scm_cadr(_args); return scm_void();
}
function scm_bi_set_cdr(_args) {
    if (_args.car.t != SCM_PAIR) return scm_err("set-cdr!: expected pair, got " + scm__type_name(_args.car.t));
    _args.car.cdr = scm_cadr(_args); return scm_void();
}

function scm_bi_list(_args) {
    return _args;  // args are already a proper list!
}

function scm_bi_length(_args) {
    if (_args.car.t != SCM_PAIR && _args.car.t != SCM_NIL)
        return scm_err("length: expected list, got " + scm__type_name(_args.car.t));
    return scm_num(scm_list_len(_args.car));
}

function scm_bi_reverse(_args) {
    if (_args.car.t != SCM_PAIR && _args.car.t != SCM_NIL)
        return scm_err("reverse: expected list, got " + scm__type_name(_args.car.t));
    return scm_list_reverse(_args.car);
}

function scm_bi_append(_args) {
    if (_args.t == SCM_NIL) return scm_nil();
    if (_args.cdr.t == SCM_NIL) return _args.car;

    // Collect all lists
    var _lists = scm_list_to_array(_args);
    var _last  = _lists[array_length(_lists) - 1];

    for (var _i = array_length(_lists) - 2; _i >= 0; _i--) {
        var _lst = _lists[_i];
        if (_lst.t == SCM_NIL) continue;
        // Copy this list and append _last at end
        var _head = scm_cons(_lst.car, scm_nil());
        var _tail = _head;
        var _p = _lst.cdr;
        while (_p.t == SCM_PAIR) {
            var _np = scm_cons(_p.car, scm_nil());
            scm_set_cdr(_tail, _np);
            _tail = _np;
            _p = _p.cdr;
        }
        scm_set_cdr(_tail, _last);
        _last = _head;
    }
    return _last;
}

function scm_bi_list_ref(_args) {
    if (_args.car.t != SCM_PAIR) return scm_err("list-ref: expected pair, got " + scm__type_name(_args.car.t));
    var _n = scm_cadr(_args);
    if (_n.t != SCM_NUM) return scm_err("list-ref: expected number for index, got " + scm__type_name(_n.t));
    return scm_list_ref(_args.car, _n.v);
}

function scm_bi_list_tail(_args) {
    var _lst = _args.car;
    var _n   = scm_cadr(_args);
    if (_n.t != SCM_NUM) return scm_err("list-tail: expected number for index, got " + scm__type_name(_n.t));
    for (var _i = 0; _i < _n.v; _i++) {
        if (_lst.t != SCM_PAIR) return scm_err("list-tail: list too short");
        _lst = _lst.cdr;
    }
    return _lst;
}

// ═══════════════════════════════════════════════════════════════════
//  String operations
// ═══════════════════════════════════════════════════════════════════

function scm_bi_string_length(_args) {
    if (_args.car.t != SCM_STR) return scm_err("string-length: expected string, got " + scm__type_name(_args.car.t));
    return scm_num(string_length(_args.car.v));
}

function scm_bi_string_ref(_args) {
    if (_args.car.t != SCM_STR) return scm_err("string-ref: expected string, got " + scm__type_name(_args.car.t));
    var _idx = scm_cadr(_args);
    if (_idx.t != SCM_NUM) return scm_err("string-ref: expected number for index, got " + scm__type_name(_idx.t));
    return scm_str(string_char_at(_args.car.v, _idx.v + 1));  // 0→1 indexed
}

function scm_bi_string_append(_args) {
    var _s = "";
    while (_args.t == SCM_PAIR) {
        if (_args.car.t != SCM_STR) return scm_err("string-append: expected string, got " + scm__type_name(_args.car.t));
        _s += _args.car.v; _args = _args.cdr;
    }
    return scm_str(_s);
}

function scm_bi_substring(_args) {
    if (_args.car.t != SCM_STR) return scm_err("substring: expected string, got " + scm__type_name(_args.car.t));
    var _s     = _args.car.v;
    var _start_v = scm_cadr(_args);
    if (_start_v.t != SCM_NUM) return scm_err("substring: expected number for start, got " + scm__type_name(_start_v.t));
    var _start = _start_v.v;
    var _end   = (scm_cddr(_args).t != SCM_NIL) ? scm_caddr(_args).v : string_length(_s);
    return scm_str(string_copy(_s, _start + 1, _end - _start));
}

function scm_bi_string_to_number(_args) {
    if (_args.car.t != SCM_STR) return scm_err("string->number: expected string, got " + scm__type_name(_args.car.t));
    var _s = _args.car.v;
    if (scm__is_number_str(_s)) return scm_num(real(_s));
    return scm_bool(false);
}

function scm_bi_number_to_string(_args) {
    if (_args.car.t != SCM_NUM) return scm_err("number->string: expected number, got " + scm__type_name(_args.car.t));
    var _v = _args.car.v;
    if (_v == floor(_v) && abs(_v) < 1000000000000000) return scm_str(string(int64(_v)));
    return scm_str(string(_v));
}

function scm_bi_string_to_symbol(_args) {
    if (_args.car.t != SCM_STR) return scm_err("string->symbol: expected string, got " + scm__type_name(_args.car.t));
    return scm_sym(_args.car.v);
}
function scm_bi_symbol_to_string(_args) {
    if (_args.car.t != SCM_SYM) return scm_err("symbol->string: expected symbol, got " + scm__type_name(_args.car.t));
    return scm_str(_args.car.v);
}

function scm_bi_string_contains(_args) {
    if (_args.car.t != SCM_STR) return scm_err("string-contains?: expected string, got " + scm__type_name(_args.car.t));
    var _sub = scm_cadr(_args);
    if (_sub.t != SCM_STR) return scm_err("string-contains?: expected string, got " + scm__type_name(_sub.t));
    return scm_bool(string_pos(_sub.v, _args.car.v) > 0);
}

function scm_bi_string_upcase(_args) {
    if (_args.car.t != SCM_STR) return scm_err("string-upcase: expected string, got " + scm__type_name(_args.car.t));
    return scm_str(string_upper(_args.car.v));
}
function scm_bi_string_downcase(_args) {
    if (_args.car.t != SCM_STR) return scm_err("string-downcase: expected string, got " + scm__type_name(_args.car.t));
    return scm_str(string_lower(_args.car.v));
}

/// (string-split str delimiter) → list of strings
function scm_bi_string_split(_args) {
    if (_args.car.t != SCM_STR) return scm_err("string-split: expected string, got " + scm__type_name(_args.car.t));
    var _sep_arg = scm_cadr(_args);
    if (_sep_arg.t != SCM_STR) return scm_err("string-split: expected string for delimiter, got " + scm__type_name(_sep_arg.t));
    var _s   = _args.car.v;
    var _sep = _sep_arg.v;
    var _sep_len = string_length(_sep);
    if (_sep_len == 0) return scm_err("string-split: empty delimiter");

    var _result = scm_nil();
    var _start = 1;
    var _slen = string_length(_s);

    while (_start <= _slen) {
        var _pos = string_pos_ext(_sep, _s, _start - 1);  // 0-based offset
        if (_pos == 0) {
            // No more separators — take the rest
            _result = scm_cons(scm_str(string_copy(_s, _start, _slen - _start + 1)), _result);
            _start = _slen + 1;
        } else {
            _result = scm_cons(scm_str(string_copy(_s, _start, _pos - _start)), _result);
            _start = _pos + _sep_len;
        }
    }
    // Edge case: trailing delimiter gives empty string
    if (_start == _slen + 1 + _sep_len) {
        _result = scm_cons(scm_str(""), _result);
    }
    return scm_list_reverse(_result);
}

// ═══════════════════════════════════════════════════════════════════
//  Character operations
// ═══════════════════════════════════════════════════════════════════

function scm_bi_char_alphabetic(_args) {
    if (_args.car.t != SCM_STR) return scm_err("char-alphabetic?: expected string, got " + scm__type_name(_args.car.t));
    var _c = ord(string_char_at(_args.car.v, 1));
    return scm_bool((_c >= 65 && _c <= 90) || (_c >= 97 && _c <= 122));
}

function scm_bi_char_numeric(_args) {
    if (_args.car.t != SCM_STR) return scm_err("char-numeric?: expected string, got " + scm__type_name(_args.car.t));
    var _c = ord(string_char_at(_args.car.v, 1));
    return scm_bool(_c >= 48 && _c <= 57);
}

function scm_bi_char_whitespace(_args) {
    if (_args.car.t != SCM_STR) return scm_err("char-whitespace?: expected string, got " + scm__type_name(_args.car.t));
    var _c = ord(string_char_at(_args.car.v, 1));
    return scm_bool(_c == 32 || _c == 9 || _c == 10 || _c == 13);
}

function scm_bi_char_to_integer(_args) {
    if (_args.car.t != SCM_STR) return scm_err("char->integer: expected string, got " + scm__type_name(_args.car.t));
    return scm_num(ord(string_char_at(_args.car.v, 1)));
}

function scm_bi_integer_to_char(_args) {
    if (_args.car.t != SCM_NUM) return scm_err("integer->char: expected number, got " + scm__type_name(_args.car.t));
    return scm_str(chr(_args.car.v));
}

// ═══════════════════════════════════════════════════════════════════
//  I/O
// ═══════════════════════════════════════════════════════════════════

function scm_bi_display(_args) {
    scm_output_write(scm_display_str(_args.car));
    return scm_void();
}

function scm_bi_write(_args) {
    scm_output_write(scm_write_str(_args.car));
    return scm_void();
}

function scm_bi_print(_args) {
    scm_output_write(scm_write_str(_args.car));
    scm_output_write("\n");
    return scm_void();
}

function scm_bi_newline(_args) {
    scm_output_write("\n");
    return scm_void();
}

// ═══════════════════════════════════════════════════════════════════
//  Control
// ═══════════════════════════════════════════════════════════════════

function scm_bi_apply(_args) {
    var _fn   = _args.car;
    if (!scm_is_proc(_fn)) return scm_err("apply: expected procedure, got " + scm__type_name(_fn.t));
    var _last = _args;
    // (apply fn a b ... lst) → gather intermediate args, then append list
    var _mid  = scm_nil();
    var _p = _args.cdr;
    while (_p.cdr.t == SCM_PAIR) {
        _mid = scm_cons(_p.car, _mid);
        _p = _p.cdr;
    }
    // _p.car is the final list argument
    var _final_args = _p.car;
    // Prepend mid args (reversed) onto final
    while (_mid.t == SCM_PAIR) {
        _final_args = scm_cons(_mid.car, _final_args);
        _mid = _mid.cdr;
    }
    return scm_apply(_fn, _final_args);
}

function scm_bi_error(_args) {
    var _msg = "";
    while (_args.t == SCM_PAIR) {
        _msg += scm_display_str(_args.car);
        _args = _args.cdr;
        if (_args.t == SCM_PAIR) _msg += " ";
    }
    return scm_err(_msg);
}

function scm_bi_void_fn(_args) {
    return scm_void();
}

// ═══════════════════════════════════════════════════════════════════
//  Misc
// ═══════════════════════════════════════════════════════════════════

function scm_bi_gensym(_args) {
    global.__scm_gensym_counter++;
    return scm_sym("__g" + string(global.__scm_gensym_counter));
}

// ═══════════════════════════════════════════════════════════════════
//  Registration
// ═══════════════════════════════════════════════════════════════════

function scm_register_core(_env) {
    global.__scm_gensym_counter = 0;

    // Arithmetic
    scm_env_set(_env, "+",        scm_fn("+",        scm_bi_add));
    scm_env_set(_env, "-",        scm_fn("-",        scm_bi_sub));
    scm_env_set(_env, "*",        scm_fn("*",        scm_bi_mul));
    scm_env_set(_env, "/",        scm_fn("/",        scm_bi_div));
    scm_env_set(_env, "modulo",   scm_fn("modulo",   scm_bi_modulo));
    scm_env_set(_env, "remainder",scm_fn("remainder", scm_bi_modulo));
    scm_env_set(_env, "min",      scm_fn("min",      scm_bi_min));
    scm_env_set(_env, "max",      scm_fn("max",      scm_bi_max));

    // Comparison
    scm_env_set(_env, "=",  scm_fn("=",  scm_bi_num_eq));
    scm_env_set(_env, "<",  scm_fn("<",  scm_bi_lt));
    scm_env_set(_env, ">",  scm_fn(">",  scm_bi_gt));
    scm_env_set(_env, "<=", scm_fn("<=", scm_bi_le));
    scm_env_set(_env, ">=", scm_fn(">=", scm_bi_ge));

    // Boolean & predicates
    scm_env_set(_env, "not",        scm_fn("not",        scm_bi_not));
    scm_env_set(_env, "null?",      scm_fn("null?",      scm_bi_is_null));
    scm_env_set(_env, "pair?",      scm_fn("pair?",      scm_bi_is_pair));
    scm_env_set(_env, "number?",    scm_fn("number?",    scm_bi_is_number));
    scm_env_set(_env, "string?",    scm_fn("string?",    scm_bi_is_string));
    scm_env_set(_env, "symbol?",    scm_fn("symbol?",    scm_bi_is_symbol));
    scm_env_set(_env, "boolean?",   scm_fn("boolean?",   scm_bi_is_boolean));
    scm_env_set(_env, "list?",      scm_fn("list?",      scm_bi_is_list));
    scm_env_set(_env, "zero?",      scm_fn("zero?",      scm_bi_is_zero));
    scm_env_set(_env, "procedure?", scm_fn("procedure?",  scm_bi_is_proc));
    scm_env_set(_env, "void?",      scm_fn("void?",      scm_bi_is_void));
    scm_env_set(_env, "error?",     scm_fn("error?",     scm_bi_is_error));
    scm_env_set(_env, "equal?",     scm_fn("equal?",     scm_bi_equal));
    scm_env_set(_env, "eqv?",       scm_fn("eqv?",       scm_bi_eq));
    scm_env_set(_env, "eq?",        scm_fn("eq?",        scm_bi_eq));

    // List operations
    scm_env_set(_env, "cons",      scm_fn("cons",      scm_bi_cons));
    scm_env_set(_env, "car",       scm_fn("car",       scm_bi_car));
    scm_env_set(_env, "cdr",       scm_fn("cdr",       scm_bi_cdr));
    scm_env_set(_env, "set-car!",  scm_fn("set-car!",  scm_bi_set_car));
    scm_env_set(_env, "set-cdr!",  scm_fn("set-cdr!",  scm_bi_set_cdr));
    scm_env_set(_env, "list",      scm_fn("list",      scm_bi_list));
    scm_env_set(_env, "length",    scm_fn("length",    scm_bi_length));
    scm_env_set(_env, "reverse",   scm_fn("reverse",   scm_bi_reverse));
    scm_env_set(_env, "append",    scm_fn("append",    scm_bi_append));
    scm_env_set(_env, "list-ref",  scm_fn("list-ref",  scm_bi_list_ref));
    scm_env_set(_env, "list-tail", scm_fn("list-tail", scm_bi_list_tail));

    // String operations
    scm_env_set(_env, "string-length",   scm_fn("string-length",   scm_bi_string_length));
    scm_env_set(_env, "string-ref",      scm_fn("string-ref",      scm_bi_string_ref));
    scm_env_set(_env, "string-append",   scm_fn("string-append",   scm_bi_string_append));
    scm_env_set(_env, "substring",       scm_fn("substring",       scm_bi_substring));
    scm_env_set(_env, "string->number",  scm_fn("string->number",  scm_bi_string_to_number));
    scm_env_set(_env, "number->string",  scm_fn("number->string",  scm_bi_number_to_string));
    scm_env_set(_env, "string->symbol",  scm_fn("string->symbol",  scm_bi_string_to_symbol));
    scm_env_set(_env, "symbol->string",  scm_fn("symbol->string",  scm_bi_symbol_to_string));
    scm_env_set(_env, "string-contains?",scm_fn("string-contains?",scm_bi_string_contains));
    scm_env_set(_env, "string-upcase",   scm_fn("string-upcase",   scm_bi_string_upcase));
    scm_env_set(_env, "string-downcase", scm_fn("string-downcase", scm_bi_string_downcase));
    scm_env_set(_env, "string-split",    scm_fn("string-split",    scm_bi_string_split));

    // Character operations
    scm_env_set(_env, "char-alphabetic?", scm_fn("char-alphabetic?", scm_bi_char_alphabetic));
    scm_env_set(_env, "char-numeric?",    scm_fn("char-numeric?",    scm_bi_char_numeric));
    scm_env_set(_env, "char-whitespace?", scm_fn("char-whitespace?", scm_bi_char_whitespace));
    scm_env_set(_env, "char->integer",    scm_fn("char->integer",    scm_bi_char_to_integer));
    scm_env_set(_env, "integer->char",    scm_fn("integer->char",    scm_bi_integer_to_char));

    // I/O
    scm_env_set(_env, "display", scm_fn("display", scm_bi_display));
    scm_env_set(_env, "write",   scm_fn("write",   scm_bi_write));
    scm_env_set(_env, "print",   scm_fn("print",   scm_bi_print));
    scm_env_set(_env, "newline", scm_fn("newline",  scm_bi_newline));

    // Control
    scm_env_set(_env, "apply", scm_fn("apply", scm_bi_apply));
    scm_env_set(_env, "error", scm_fn("error", scm_bi_error));
    scm_env_set(_env, "void",  scm_fn("void",  scm_bi_void_fn));

    // Misc
    scm_env_set(_env, "gensym", scm_fn("gensym", scm_bi_gensym));
}
