/// scm_core.gml — Core built-in procedures
///
/// All builtins receive a Scheme list of already-evaluated arguments.
/// Register them into an environment with scm_register_core(_env).
///
/// !! UMT BYTECODE 17 — FORBIDDEN SYNTAX (build.py lint enforced):
///    [$]  [?]  [@]  struct_set()  is_instanceof()
///    Use: variable_struct_get/set, ds_map_find_value/set, array_get/set

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
//  Higher-order list operations
// ═══════════════════════════════════════════════════════════════════

/// (map f lst) — apply f to each element, return new list
/// Native GML loop — zero fuel cost, no intermediate reverse.
function scm_bi_map(_args) {
    var _fn  = _args.car;
    var _lst = scm_cadr(_args);
    if (!scm_is_proc(_fn)) return scm_err("map: expected procedure, got " + scm__type_name(_fn.t));
    if (_lst.t == SCM_NIL) return scm_nil();
    if (_lst.t != SCM_PAIR) return scm_err("map: expected list, got " + scm__type_name(_lst.t));

    // Build result list forward (head/tail pointers, no reverse needed)
    var _head = scm_nil();
    var _tail = _head;
    var _p = _lst;
    while (_p.t == SCM_PAIR) {
        var _val = scm_apply(_fn, scm_cons(_p.car, scm_nil()));
        if (_val.t == SCM_ERR) return _val;
        var _node = scm_cons(_val, scm_nil());
        if (_head.t == SCM_NIL) {
            _head = _node;
        } else {
            scm_set_cdr(_tail, _node);
        }
        _tail = _node;
        _p = _p.cdr;
    }
    return _head;
}

/// (filter pred lst) — return elements where pred returns truthy
function scm_bi_filter(_args) {
    var _fn  = _args.car;
    var _lst = scm_cadr(_args);
    if (!scm_is_proc(_fn)) return scm_err("filter: expected procedure, got " + scm__type_name(_fn.t));
    if (_lst.t == SCM_NIL) return scm_nil();
    if (_lst.t != SCM_PAIR) return scm_err("filter: expected list, got " + scm__type_name(_lst.t));

    var _head = scm_nil();
    var _tail = _head;
    var _p = _lst;
    while (_p.t == SCM_PAIR) {
        var _test = scm_apply(_fn, scm_cons(_p.car, scm_nil()));
        if (_test.t == SCM_ERR) return _test;
        // Scheme truthy: anything not #f
        if (!(_test.t == SCM_BOOL && _test.v == false)) {
            var _node = scm_cons(_p.car, scm_nil());
            if (_head.t == SCM_NIL) {
                _head = _node;
            } else {
                scm_set_cdr(_tail, _node);
            }
            _tail = _node;
        }
        _p = _p.cdr;
    }
    return _head;
}

/// (for-each f lst) — apply f to each element for side effects
function scm_bi_for_each(_args) {
    var _fn  = _args.car;
    var _lst = scm_cadr(_args);
    if (!scm_is_proc(_fn)) return scm_err("for-each: expected procedure, got " + scm__type_name(_fn.t));
    if (_lst.t == SCM_NIL) return scm_void();

    // Support both lists and arrays
    if (_lst.t == SCM_PAIR) {
        var _p = _lst;
        while (_p.t == SCM_PAIR) {
            var _val = scm_apply(_fn, scm_cons(_p.car, scm_nil()));
            if (_val.t == SCM_ERR) return _val;
            _p = _p.cdr;
        }
        return scm_void();
    }
    if (_lst.t == SCM_HANDLE && _lst.ht == SCM_HT_ARRAY) {
        var _arr = _lst.v;
        var _n = array_length(_arr);
        for (var _i = 0; _i < _n; _i++) {
            var _val = scm_apply(_fn, scm_cons(scm_wrap(_arr[_i]), scm_nil()));
            if (_val.t == SCM_ERR) return _val;
        }
        return scm_void();
    }
    return scm_err("for-each: expected list or array, got " + scm__type_name(_lst.t));
}

/// (assoc key alist) — find first pair with equal? key, or #f
function scm_bi_assoc(_args) {
    var _key = _args.car;
    var _lst = scm_cadr(_args);
    var _p = _lst;
    while (_p.t == SCM_PAIR) {
        var _pair = _p.car;
        if (_pair.t == SCM_PAIR && scm_equal(_key, _pair.car)) {
            return _pair;
        }
        _p = _p.cdr;
    }
    return scm_bool(false);
}

/// (member x lst) — find first tail whose car is equal? to x, or #f
function scm_bi_member(_args) {
    var _x   = _args.car;
    var _lst = scm_cadr(_args);
    var _p = _lst;
    while (_p.t == SCM_PAIR) {
        if (scm_equal(_x, _p.car)) return _p;
        _p = _p.cdr;
    }
    return scm_bool(false);
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

function scm__is_number_str(_s) {
    var _len = string_length(_s);
    if (_len == 0) return false;
    var _i = 1;
    var _c = string_char_at(_s, 1);
    if (_c == "+" || _c == "-") { _i++; if (_i > _len) return false; }
    var _has_digit = false;
    var _has_dot = false;
    while (_i <= _len) {
        _c = string_char_at(_s, _i);
        if (_c >= "0" && _c <= "9") { _has_digit = true; }
        else if (_c == "." && !_has_dot) { _has_dot = true; }
        else { return false; }
        _i++;
    }
    return _has_digit;
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
//  I/O — Port helpers
// ═══════════════════════════════════════════════════════════════════

/// Write a string to a port.  Dispatches on port kind.
function scm__port_write(_port, _str) {
    if (_port.closed) return scm_err("write to closed port");
    switch (_port.kind) {
        case SCM_PORT_CONSOLE:
            scm_output_write(_str);
            break;
        case SCM_PORT_STRING:
            _port.buf += _str;
            break;
        case SCM_PORT_FILE:
            file_text_write_string(_port.fid, _str);
            break;
        case SCM_PORT_DEBUG:
            // Line-buffered: accumulate until \n, then flush via show_debug_message
            _port.buf += _str;
            var _nl = string_pos("\n", _port.buf);
            while (_nl > 0) {
                var _line = string_copy(_port.buf, 1, _nl - 1);
                show_debug_message(_line);
                _port.buf = string_copy(_port.buf, _nl + 1,
                    string_length(_port.buf) - _nl);
                _nl = string_pos("\n", _port.buf);
            }
            break;
    }
    return undefined;  // no error
}

/// Read one character from an input port.  Returns 1-char string or "".
function scm__port_read_char(_port) {
    if (_port.closed) return "";
    switch (_port.kind) {
        case SCM_PORT_STRING:
            if (_port.pos >= string_length(_port.buf)) return "";
            _port.pos++;
            return string_char_at(_port.buf, _port.pos);
        case SCM_PORT_FILE:
            // GML file_text_read_string reads an entire line.
            // Buffer one line at a time and serve chars from the buffer.
            if (_port.pos >= string_length(_port.buf)) {
                if (file_text_eof(_port.fid)) return "";
                _port.buf = file_text_read_string(_port.fid);
                file_text_readln(_port.fid);
                _port.buf += "\n";
                _port.pos = 0;
            }
            _port.pos++;
            return string_char_at(_port.buf, _port.pos);
        default:
            return "";
    }
}

/// Extract the optional port argument from _args.cdr.
/// Returns the port, or global console port if absent.
/// Returns an error value if the argument is present but not a port.
function scm__opt_output_port(_args, _name) {
    if (_args.cdr.t == SCM_PAIR) {
        var _p = _args.cdr.car;
        if (_p.t != SCM_PORT) return scm_err(_name + ": expected port, got " + scm__type_name(_p.t));
        if (_p.dir != SCM_PORT_OUT) return scm_err(_name + ": not an output port");
        if (_p.closed) return scm_err(_name + ": port is closed");
        return _p;
    }
    return global.__scm_console_out;
}

// ═══════════════════════════════════════════════════════════════════
//  I/O — display / write / print / newline  (optional port arg)
// ═══════════════════════════════════════════════════════════════════

function scm_bi_display(_args) {
    if (_args.t != SCM_PAIR) return scm_err("display: expected 1-2 arguments, got 0");
    var _port = scm__opt_output_port(_args, "display");
    if (_port.t == SCM_ERR) return _port;
    var _e = scm__port_write(_port, scm_display_str(_args.car));
    if (_e != undefined) return _e;
    return scm_void();
}

function scm_bi_write(_args) {
    if (_args.t != SCM_PAIR) return scm_err("write: expected 1-2 arguments, got 0");
    var _port = scm__opt_output_port(_args, "write");
    if (_port.t == SCM_ERR) return _port;
    var _e = scm__port_write(_port, scm_write_str(_args.car));
    if (_e != undefined) return _e;
    return scm_void();
}

function scm_bi_print(_args) {
    if (_args.t != SCM_PAIR) return scm_err("print: expected 1-2 arguments, got 0");
    var _port = scm__opt_output_port(_args, "print");
    if (_port.t == SCM_ERR) return _port;
    var _e = scm__port_write(_port, scm_write_str(_args.car));
    if (_e != undefined) return _e;
    scm__port_write(_port, "\n");
    return scm_void();
}

function scm_bi_newline(_args) {
    var _port;
    if (_args.t == SCM_PAIR) {
        var _p = _args.car;
        if (_p.t != SCM_PORT) return scm_err("newline: expected port, got " + scm__type_name(_p.t));
        if (_p.dir != SCM_PORT_OUT) return scm_err("newline: not an output port");
        if (_p.closed) return scm_err("newline: port is closed");
        _port = _p;
    } else {
        _port = global.__scm_console_out;
    }
    scm__port_write(_port, "\n");
    return scm_void();
}

// ═══════════════════════════════════════════════════════════════════
//  I/O — Port constructors & accessors
// ═══════════════════════════════════════════════════════════════════

/// (open-output-string) → output string port
function scm_bi_open_output_string(_args) {
    return scm_port(SCM_PORT_OUT, SCM_PORT_STRING);
}

/// (get-output-string port) → accumulated string
function scm_bi_get_output_string(_args) {
    var _p = _args.car;
    if (_p.t != SCM_PORT) return scm_err("get-output-string: expected port, got " + scm__type_name(_p.t));
    if (_p.kind != SCM_PORT_STRING || _p.dir != SCM_PORT_OUT)
        return scm_err("get-output-string: expected output string port");
    return scm_str(_p.buf);
}

/// (open-input-string str) → input string port
function scm_bi_open_input_string(_args) {
    if (_args.car.t != SCM_STR) return scm_err("open-input-string: expected string, got " + scm__type_name(_args.car.t));
    var _p = scm_port(SCM_PORT_IN, SCM_PORT_STRING);
    _p.buf = _args.car.v;
    _p.pos = 0;
    return _p;
}

/// (file->string path) → read entire file into a string
function scm_bi_file_to_string(_args) {
    if (_args.car.t != SCM_STR) return scm_err("file->string: expected string, got " + scm__type_name(_args.car.t));
    var _path = _args.car.v;
    if (!file_exists(_path)) return scm_err("file->string: file not found: " + _path);
    var _buf = buffer_load(_path);
    var _str = buffer_read(_buf, buffer_text);
    buffer_delete(_buf);
    return scm_str(_str);
}

// ═══════════════════════════════════════════════════════════════════
//  Completion configuration builtins (comp:make-dict, comp:on)
// ═══════════════════════════════════════════════════════════════════

/// (comp:make-dict names-array [tag]) → opaque dict struct
/// names-array: GML array of name strings (from gml:json-parse)
/// tag: optional string — short label for overlay display (e.g. "obj", "spr")
/// Index (trie + masks) is built later by comp:on when all dicts are known.
function scm_bi_comp_make_dict(_args) {
    // arg 1: names — must be a GML-wrapped array
    var _names_val = _args.car;

    // Unwrap GML values to raw GML types
    var _names_raw = scm_unwrap(_names_val);

    if (!is_array(_names_raw))
        return scm_err("comp:make-dict: argument must be a GML array of names");

    // Optional arg 2: tag string
    var _tag = "";
    var _rest = _args.cdr;
    if (_rest.t == SCM_PAIR && _rest.car.t == SCM_STR) {
        _tag = _rest.car.v;
    }

    // Return as an opaque GML-wrapped struct (only names + tag; index built by comp:on)
    var _dict = { names: _names_raw, tag: _tag };
    return scm_wrap(_dict);
}

/// (comp:on fn-name arg-idx dicts insert-fn [label]) → void
/// Registers a string-context completer.
/// fn-name:    string — the Scheme function name to trigger on
/// arg-idx:    number — 0-based argument index where completion applies
/// dicts:      list of dict structs (from comp:make-dict)
/// insert-fn:  lambda (name → string) — transforms selected name for insertion
/// label:      optional string — footer hint label (default "items")
///
/// Concatenates all dict names → builds unified index (trie + masks).
function scm_bi_comp_on(_args) {
    var _fn = _args.car;
    if (_fn.t != SCM_STR)
        return scm_err("comp:on: fn-name must be a string, got " + scm__type_name(_fn.t));
    var _fn_name = _fn.v;

    var _idx = _args.cdr.car;
    if (_idx.t != SCM_NUM)
        return scm_err("comp:on: arg-idx must be a number, got " + scm__type_name(_idx.t));
    var _arg_idx = floor(_idx.v);

    var _dicts_list = _args.cdr.cdr.car;
    // Convert Scheme list of dicts to GML array, collecting all names
    var _dicts = [];
    var _all_names = [];
    var _all_tags = [];
    var _cur = _dicts_list;
    while (_cur.t == SCM_PAIR) {
        var _p = _cur.car;
        var _raw = scm_unwrap(_p);
        if (!is_struct(_raw) || !variable_struct_exists(_raw, "names"))
            return scm_err("comp:on: dicts must be a list of comp:make-dict results");
        array_push(_dicts, _raw);
        // Concatenate names + tags from this dict
        var _pnames = _raw.names;
        var _ptag = variable_struct_exists(_raw, "tag") ? _raw.tag : "";
        var _pn = array_length(_pnames);
        for (var _i = 0; _i < _pn; _i++) {
            array_push(_all_names, _pnames[_i]);
            array_push(_all_tags, _ptag);
        }
        _cur = _cur.cdr;
    }
    if (array_length(_dicts) == 0)
        return scm_err("comp:on: dicts list must not be empty");

    var _insert_fn = _args.cdr.cdr.cdr.car;
    if (_insert_fn.t != SCM_FN && _insert_fn.t != SCM_LAMBDA)
        return scm_err("comp:on: insert-fn must be a function, got " + scm__type_name(_insert_fn.t));

    // Optional 5th arg: label string (default "items")
    var _label = "items";
    var _rest = _args.cdr.cdr.cdr.cdr;
    if (_rest.t == SCM_PAIR && _rest.car.t == SCM_STR) {
        _label = _rest.car.v;
    }

    var _count = array_length(_all_names);

    // Build unified index (trie + masks + tags) from merged names
    var _index = scm_comp__build_index(_all_names, _all_tags);

    // Register in the completer registry
    scm_comp__register(_fn_name, _arg_idx, _insert_fn, _label, _index);

    return scm_void();
}

/// (open-input-file path) → input file port
function scm_bi_open_input_file(_args) {
    if (_args.car.t != SCM_STR) return scm_err("open-input-file: expected string, got " + scm__type_name(_args.car.t));
    var _path = _args.car.v;
    if (!file_exists(_path)) return scm_err("open-input-file: file not found: " + _path);
    var _fid = file_text_open_read(_path);
    var _p = scm_port(SCM_PORT_IN, SCM_PORT_FILE);
    _p.fid = _fid;
    return _p;
}

/// (open-output-file path) → output file port
function scm_bi_open_output_file(_args) {
    if (_args.car.t != SCM_STR) return scm_err("open-output-file: expected string, got " + scm__type_name(_args.car.t));
    var _path = _args.car.v;
    var _fid = file_text_open_write(_path);
    var _p = scm_port(SCM_PORT_OUT, SCM_PORT_FILE);
    _p.fid = _fid;
    return _p;
}

/// (close-port port) / (close-input-port port) / (close-output-port port)
function scm_bi_close_port(_args) {
    var _p = _args.car;
    if (_p.t != SCM_PORT) return scm_err("close-port: expected port, got " + scm__type_name(_p.t));
    if (_p.closed) return scm_void();
    _p.closed = true;
    if (_p.kind == SCM_PORT_FILE && _p.fid >= 0) {
        file_text_close(_p.fid);
        _p.fid = -1;
    }
    return scm_void();
}

/// (port? x)
function scm_bi_is_port(_args)        { return scm_bool(_args.car.t == SCM_PORT); }
/// (input-port? x)
function scm_bi_is_input_port(_args)   { return scm_bool(_args.car.t == SCM_PORT && _args.car.dir == SCM_PORT_IN); }
/// (output-port? x)
function scm_bi_is_output_port(_args)  { return scm_bool(_args.car.t == SCM_PORT && _args.car.dir == SCM_PORT_OUT); }
/// (port-open? port) — not R7RS, but useful
function scm_bi_port_open(_args) {
    if (_args.car.t != SCM_PORT) return scm_err("port-open?: expected port, got " + scm__type_name(_args.car.t));
    return scm_bool(!_args.car.closed);
}

/// (eof-object) → eof singleton
function scm_bi_eof_object(_args)     { return scm_eof(); }
/// (eof-object? x)
function scm_bi_is_eof(_args)         { return scm_bool(_args.car.t == SCM_EOF); }

/// (current-output-port) → console output port
function scm_bi_current_output_port(_args) { return global.__scm_console_out; }

/// (current-error-port) → debug output port (show_debug_message)
function scm_bi_current_error_port(_args) { return global.__scm_debug_out; }

/// (read-char [port])
function scm_bi_read_char(_args) {
    var _port;
    if (_args.t == SCM_PAIR) {
        _port = _args.car;
        if (_port.t != SCM_PORT) return scm_err("read-char: expected port, got " + scm__type_name(_port.t));
        if (_port.dir != SCM_PORT_IN) return scm_err("read-char: not an input port");
    } else {
        return scm_err("read-char: no default input port");
    }
    if (_port.closed) return scm_err("read-char: port is closed");
    var _ch = scm__port_read_char(_port);
    if (_ch == "") return scm_eof();
    return scm_str(_ch);
}

/// (peek-char [port])
function scm_bi_peek_char(_args) {
    var _port;
    if (_args.t == SCM_PAIR) {
        _port = _args.car;
        if (_port.t != SCM_PORT) return scm_err("peek-char: expected port, got " + scm__type_name(_port.t));
        if (_port.dir != SCM_PORT_IN) return scm_err("peek-char: not an input port");
    } else {
        return scm_err("peek-char: no default input port");
    }
    if (_port.closed) return scm_err("peek-char: port is closed");
    // Peek without advancing — save and restore pos
    var _saved_pos = _port.pos;
    var _saved_buf = _port.buf;
    var _ch = scm__port_read_char(_port);
    _port.pos = _saved_pos;
    _port.buf = _saved_buf;
    if (_ch == "") return scm_eof();
    return scm_str(_ch);
}

/// (read-line [port])
function scm_bi_read_line(_args) {
    var _port;
    if (_args.t == SCM_PAIR) {
        _port = _args.car;
        if (_port.t != SCM_PORT) return scm_err("read-line: expected port, got " + scm__type_name(_port.t));
        if (_port.dir != SCM_PORT_IN) return scm_err("read-line: not an input port");
    } else {
        return scm_err("read-line: no default input port");
    }
    if (_port.closed) return scm_err("read-line: port is closed");
    // Accumulate chars until newline or EOF
    var _buf = "";
    var _got_any = false;
    while (true) {
        var _ch = scm__port_read_char(_port);
        if (_ch == "") break;
        _got_any = true;
        if (_ch == "\n") break;
        _buf += _ch;
    }
    if (!_got_any) return scm_eof();
    return scm_str(_buf);
}

/// (write-char ch [port])
function scm_bi_write_char(_args) {
    if (_args.car.t != SCM_STR) return scm_err("write-char: expected char (string), got " + scm__type_name(_args.car.t));
    var _port = scm__opt_output_port(_args, "write-char");
    if (_port.t == SCM_ERR) return _port;
    var _e = scm__port_write(_port, _args.car.v);
    if (_e != undefined) return _e;
    return scm_void();
}

/// (write-string str [port])
function scm_bi_write_string(_args) {
    if (_args.car.t != SCM_STR) return scm_err("write-string: expected string, got " + scm__type_name(_args.car.t));
    var _port = scm__opt_output_port(_args, "write-string");
    if (_port.t == SCM_ERR) return _port;
    var _e = scm__port_write(_port, _args.car.v);
    if (_e != undefined) return _e;
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

/// (macroexpand-1 form) → expanded form (single expansion step)
/// If form is a list whose head names a macro, expand once; otherwise return as-is.
function scm_bi_macroexpand_1(_args) {
    if (_args.t != SCM_PAIR) return scm_err("macroexpand-1: expected 1 argument");
    var _form = _args.car;
    if (_form.t != SCM_PAIR) return _form;           // not a list → return as-is
    var _head = _form.car;
    if (_head.t != SCM_SYM) return _form;            // head not a symbol → return as-is
    var _mac = variable_struct_get(global.__scm_macros, _head.v);
    if (is_undefined(_mac)) return _form;            // not a macro → return as-is
    return scm_apply(_mac, _form.cdr);               // expand once
}

/// (macroexpand form) → fully expanded form (loop until stable)
function scm_bi_macroexpand(_args) {
    if (_args.t != SCM_PAIR) return scm_err("macroexpand: expected 1 argument");
    var _form = _args.car;
    for (var _i = 0; _i < 1000; _i++) {              // safety limit
        if (_form.t != SCM_PAIR) return _form;
        var _head = _form.car;
        if (_head.t != SCM_SYM) return _form;
        var _mac = variable_struct_get(global.__scm_macros, _head.v);
        if (is_undefined(_mac)) return _form;
        var _next = scm_apply(_mac, _form.cdr);
        if (_next.t == SCM_ERR) return _next;
        _form = _next;
    }
    return scm_err("macroexpand: expansion did not stabilize after 1000 steps");
}

/// (macro? sym) → #t if sym names a macro in the global macro table
function scm_bi_is_macro(_args) {
    if (_args.t != SCM_PAIR || _args.car.t != SCM_SYM)
        return scm_err("macro?: expected a symbol");
    return scm_bool(!is_undefined(variable_struct_get(global.__scm_macros, _args.car.v)));
}

// ═══════════════════════════════════════════════════════════════════
//  Environment introspection
// ═══════════════════════════════════════════════════════════════════

/// (apropos pattern) → list of (name . type-string) for bindings containing pattern
/// pattern is matched as substring (case-insensitive).
function scm_bi_apropos(_args) {
    if (_args.t != SCM_PAIR || _args.car.t != SCM_STR)
        return scm_err("apropos: expected string pattern");
    var _pattern = _args.car.v;
    var _pat_lower = string_lower(_pattern);
    var _env = global.scm_env;
    var _seen = ds_map_create();
    var _result = scm_nil();

    while (_env != undefined) {
        var _keys = variable_struct_get_names(_env.bindings);
        for (var _i = 0; _i < array_length(_keys); _i++) {
            var _k = _keys[_i];
            if (!ds_map_exists(_seen, _k)) {
                ds_map_set(_seen, _k, true);
                if (string_pos(_pat_lower, string_lower(_k)) > 0) {
                    var _val = variable_struct_get(_env.bindings, _k);
                    var _type_name;
                    switch (_val.t) {
                        case SCM_FN:          _type_name = "builtin"; break;
                        case SCM_LAMBDA:      _type_name = "lambda"; break;
                        case SCM_CASE_LAMBDA: _type_name = "lambda"; break;
                        case SCM_NUM:         _type_name = "number"; break;
                        case SCM_STR:         _type_name = "string"; break;
                        case SCM_BOOL:        _type_name = "boolean"; break;
                        case SCM_PAIR:        _type_name = "pair"; break;
                        case SCM_NIL:         _type_name = "nil"; break;
                        case SCM_HANDLE:      _type_name = "handle"; break;
                        default:              _type_name = "other"; break;
                    }
                    _result = scm_cons(
                        scm_cons(scm_str(_k), scm_str(_type_name)),
                        _result
                    );
                }
            }
        }
        _env = _env.parent;
    }
    ds_map_destroy(_seen);
    return _result;
}

// ═══════════════════════════════════════════════════════════════════
//  Self-test (smoke test for REPL)
// ═══════════════════════════════════════════════════════════════════

/// (%self-test) — run interpreter smoke tests, return result summary
function scm_bi_self_test(_args) {
    scm_trace("[self-test] starting smoke tests");
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
        ["(map (lambda (x) (+ x 1)) '())", "()"],
        ["(filter (lambda (x) (> x 2)) '(1 2 3 4 5))", "(3 4 5)"],
        ["(filter (lambda (x) #f) '(1 2 3))", "()"],
        ["(assoc 'b '((a 1) (b 2) (c 3)))", "(b 2)"],
        ["(assoc 'z '((a 1) (b 2)))", "#f"],
        ["(member 3 '(1 2 3 4 5))", "(3 4 5)"],
        ["(member 9 '(1 2 3))", "#f"],
        ["(let ((acc '())) (for-each (lambda (x) (set! acc (cons x acc))) '(1 2 3)) acc)", "(3 2 1)"],
        ["(let ((x 10) (y 20)) (+ x y))", "30"],
        ["(let loop ((n 5) (acc 1)) (if (= n 0) acc (loop (- n 1) (* acc n))))", "120"],
        ["(define (fact n) (if (<= n 1) 1 (* n (fact (- n 1))))) (fact 10)", "3628800"],
        ["(string-append \"hello\" \" \" \"world\")", "\"hello world\""],
        ["(equal? '(1 2 3) '(1 2 3))", "#t"],
        ["(car 5)", "#<error:"],
        ["(cdr \"hello\")", "#<error:"],
        ["(+ 1 \"a\")", "#<error:"],
        ["(abs #f)", "#<error:"],
        ["(modulo \"a\" 2)", "#<error:"],
        ["((lambda (x) x) 1 2)", "#<error:"],
        ["((lambda (x y) x) 1)", "#<error:"],
        ["(guard (e (#t (string-append \"caught: \" e))) (car 5))", "\"caught: car: expected pair, got number\""],
        ["(guard (e (#t 'ok)) (+ 1 2))", "3"],
    ];

    var _pass = 0;
    var _fail = 0;

    for (var _i = 0; _i < array_length(_tests); _i++) {
        var _input    = _tests[_i][0];
        var _expected = _tests[_i][1];
        var _actual;
        try {
            var _result = scm_eval_program(_input, global.scm_env);
            _actual = scm_write_str(_result);
        } catch (_e) {
            _actual = "#<gml-crash: " + string(_e) + ">";
        }
        var _match = false;
        if (string_pos("#<error:", _expected) == 1) {
            _match = (string_pos("#<error:", _actual) == 1);
        } else {
            _match = (_actual == _expected);
        }
        if (_match) {
            _pass++;
            scm_output_write("  ok  #" + string(_i) + " " + _input + "\n");
        } else {
            _fail++;
            scm_output_write("  FAIL #" + string(_i) + " " + _input + "\n");
            scm_output_write("       got:      " + _actual + "\n");
            scm_output_write("       expected: " + _expected + "\n");
        }
    }

    var _summary = string(_pass) + "/" + string(_pass + _fail) + " passed";
    if (_fail > 0) {
        _summary += ", " + string(_fail) + " FAILED";
    }
    scm_output_write(_summary + "\n");
    scm_trace("[self-test] " + _summary);
    return scm_void();
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
    scm_env_set(_env, "map",       scm_fn("map",       scm_bi_map));
    scm_env_set(_env, "filter",    scm_fn("filter",    scm_bi_filter));
    scm_env_set(_env, "for-each",  scm_fn("for-each",  scm_bi_for_each));
    scm_env_set(_env, "assoc",     scm_fn("assoc",     scm_bi_assoc));
    scm_env_set(_env, "member",    scm_fn("member",    scm_bi_member));

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

    // Ports
    scm_env_set(_env, "open-output-string",  scm_fn("open-output-string",  scm_bi_open_output_string));
    scm_env_set(_env, "get-output-string",   scm_fn("get-output-string",   scm_bi_get_output_string));
    scm_env_set(_env, "open-input-string",   scm_fn("open-input-string",   scm_bi_open_input_string));
    scm_env_set(_env, "open-input-file",     scm_fn("open-input-file",     scm_bi_open_input_file));
    scm_env_set(_env, "file->string",        scm_fn("file->string",        scm_bi_file_to_string));
    scm_env_set(_env, "open-output-file",    scm_fn("open-output-file",    scm_bi_open_output_file));
    scm_env_set(_env, "close-port",          scm_fn("close-port",          scm_bi_close_port));
    scm_env_set(_env, "close-input-port",    scm_fn("close-input-port",    scm_bi_close_port));
    scm_env_set(_env, "close-output-port",   scm_fn("close-output-port",   scm_bi_close_port));
    scm_env_set(_env, "port?",               scm_fn("port?",               scm_bi_is_port));
    scm_env_set(_env, "input-port?",         scm_fn("input-port?",         scm_bi_is_input_port));
    scm_env_set(_env, "output-port?",        scm_fn("output-port?",        scm_bi_is_output_port));
    scm_env_set(_env, "port-open?",          scm_fn("port-open?",          scm_bi_port_open));
    scm_env_set(_env, "eof-object",          scm_fn("eof-object",          scm_bi_eof_object));
    scm_env_set(_env, "eof-object?",         scm_fn("eof-object?",         scm_bi_is_eof));
    scm_env_set(_env, "current-output-port", scm_fn("current-output-port", scm_bi_current_output_port));
    scm_env_set(_env, "current-error-port",  scm_fn("current-error-port",  scm_bi_current_error_port));
    scm_env_set(_env, "read-char",           scm_fn("read-char",           scm_bi_read_char));
    scm_env_set(_env, "peek-char",           scm_fn("peek-char",           scm_bi_peek_char));
    scm_env_set(_env, "read-line",           scm_fn("read-line",           scm_bi_read_line));
    scm_env_set(_env, "write-char",          scm_fn("write-char",          scm_bi_write_char));
    scm_env_set(_env, "write-string",        scm_fn("write-string",        scm_bi_write_string));

    // Control
    scm_env_set(_env, "apply", scm_fn("apply", scm_bi_apply));
    scm_env_set(_env, "error", scm_fn("error", scm_bi_error));
    scm_env_set(_env, "void",  scm_fn("void",  scm_bi_void_fn));

    // Misc
    scm_env_set(_env, "gensym", scm_fn("gensym", scm_bi_gensym));

    // Macro introspection
    scm_env_set(_env, "macroexpand-1", scm_fn("macroexpand-1", scm_bi_macroexpand_1));
    scm_env_set(_env, "macroexpand",   scm_fn("macroexpand",   scm_bi_macroexpand));
    scm_env_set(_env, "macro?",        scm_fn("macro?",        scm_bi_is_macro));

    // Environment introspection
    scm_env_set(_env, "apropos",    scm_fn("apropos",    scm_bi_apropos));

    // Self-test
    scm_env_set(_env, "%self-test", scm_fn("%self-test", scm_bi_self_test));

    // Completion configuration
    scm_env_set(_env, "comp:make-dict", scm_fn("comp:make-dict", scm_bi_comp_make_dict));
    scm_env_set(_env, "comp:on",        scm_fn("comp:on",        scm_bi_comp_on));
}
