/// scm_eval.gml — Evaluator (trampoline TCO)
///
/// Tree-walking interpreter with proper tail-call optimization.
/// The main eval loop uses a while(true) trampoline: at tail positions
/// we reassign _expr/_env and continue instead of recursing.
/// Errors propagate as SCM_ERR values (no exceptions).

// ── Main evaluator (trampoline) ─────────────────────────────────────

function scm_eval(_expr, _env) {
    while (true) {
        // Self-evaluating types
        var _t = _expr.t;
        if (_t == SCM_NUM || _t == SCM_STR || _t == SCM_BOOL ||
            _t == SCM_NIL || _t == SCM_VOID || _t == SCM_ERR ||
            _t == SCM_HANDLE) {
            return _expr;
        }

        // Symbol → environment lookup
        if (_t == SCM_SYM) {
            var _val = scm_env_get(_env, _expr.v);
            if (_val == undefined)
                return scm_err("unbound variable: " + _expr.v);
            return _val;
        }

        // Must be a pair (list) at this point
        if (_t != SCM_PAIR) {
            return scm_err("cannot evaluate: " + scm_to_string(_expr));
        }

        var _head = _expr.car;
        var _rest = _expr.cdr;

        // Special forms (when head is a symbol)
        if (_head.t == SCM_SYM) {
            var _form = _head.v;

            // ── Reordered by frequency (hot forms first) ────────────

            if (_form == "if") {
                var _test = scm_eval(scm_car(_rest), _env);
                if (_test.t == SCM_ERR) return _test;
                if (scm_is_truthy(_test)) {
                    _expr = scm_cadr(_rest);
                    continue;  // TCO
                }
                var _else = scm_cddr(_rest);
                if (_else.t == SCM_NIL) return scm_void();
                _expr = _else.car;
                continue;  // TCO
            }

            if (_form == "define") {
                return scm__eval_define(_rest, _env);
            }

            if (_form == "let") {
                var _first = _rest.car;
                if (_first.t == SCM_SYM) {
                    return scm__eval_named_let(_first, _rest.cdr, _env);
                }
                var _bindings = _first;
                var _body     = _rest.cdr;
                var _new_env  = scm_env_new(_env);
                while (_bindings.t == SCM_PAIR) {
                    var _binding = _bindings.car;
                    var _name    = _binding.car.v;
                    var _bval    = scm_eval(scm_cadr(_binding), _env);
                    if (_bval.t == SCM_ERR) return _bval;
                    scm_env_set(_new_env, _name, _bval);
                    _bindings = _bindings.cdr;
                }
                _env = _new_env;
                while (_body.cdr.t == SCM_PAIR) {
                    var _r = scm_eval(_body.car, _env);
                    if (_r.t == SCM_ERR) return _r;
                    _body = _body.cdr;
                }
                _expr = _body.car;
                continue;  // TCO
            }

            if (_form == "lambda") {
                return scm_lambda(_rest.car, _rest.cdr, _env, undefined);
            }

            if (_form == "begin") {
                while (_rest.cdr.t == SCM_PAIR) {
                    var _r = scm_eval(_rest.car, _env);
                    if (_r.t == SCM_ERR) return _r;
                    _rest = _rest.cdr;
                }
                if (_rest.t == SCM_NIL) return scm_void();
                _expr = _rest.car;
                continue;  // TCO
            }

            if (_form == "quote") {
                return scm_car(_rest);
            }

            if (_form == "set!") {
                return scm__eval_set(_rest, _env);
            }

            if (_form == "cond") {
                var _clauses = _rest;
                while (_clauses.t == SCM_PAIR) {
                    var _clause = _clauses.car;
                    var _ctest  = _clause.car;
                    if (_ctest.t == SCM_SYM && _ctest.v == "else") {
                        var _cbody = _clause.cdr;
                        while (_cbody.cdr.t == SCM_PAIR) {
                            var _r = scm_eval(_cbody.car, _env);
                            if (_r.t == SCM_ERR) return _r;
                            _cbody = _cbody.cdr;
                        }
                        _expr = _cbody.car;
                        continue;  // TCO
                    }
                    var _cval = scm_eval(_ctest, _env);
                    if (_cval.t == SCM_ERR) return _cval;
                    if (scm_is_truthy(_cval)) {
                        if (_clause.cdr.t == SCM_PAIR && _clause.cdr.car.t == SCM_SYM &&
                            _clause.cdr.car.v == "=>") {
                            var _proc = scm_eval(scm_caddr(_clause), _env);
                            if (_proc.t == SCM_ERR) return _proc;
                            return scm_apply(_proc, scm_cons(_cval, scm_nil()));
                        }
                        if (_clause.cdr.t == SCM_NIL) return _cval;
                        var _cbody = _clause.cdr;
                        while (_cbody.cdr.t == SCM_PAIR) {
                            var _r = scm_eval(_cbody.car, _env);
                            if (_r.t == SCM_ERR) return _r;
                            _cbody = _cbody.cdr;
                        }
                        _expr = _cbody.car;
                        continue;  // TCO
                    }
                    _clauses = _clauses.cdr;
                }
                return scm_void();
            }

            if (_form == "and") {
                if (_rest.t == SCM_NIL) return scm_bool(true);
                while (_rest.cdr.t == SCM_PAIR) {
                    var _r = scm_eval(_rest.car, _env);
                    if (_r.t == SCM_ERR) return _r;
                    if (!scm_is_truthy(_r)) return _r;
                    _rest = _rest.cdr;
                }
                _expr = _rest.car;
                continue;  // TCO
            }

            if (_form == "or") {
                if (_rest.t == SCM_NIL) return scm_bool(false);
                while (_rest.cdr.t == SCM_PAIR) {
                    var _r = scm_eval(_rest.car, _env);
                    if (_r.t == SCM_ERR) return _r;
                    if (scm_is_truthy(_r)) return _r;
                    _rest = _rest.cdr;
                }
                _expr = _rest.car;
                continue;  // TCO
            }

            if (_form == "when") {
                var _test = scm_eval(scm_car(_rest), _env);
                if (_test.t == SCM_ERR) return _test;
                if (!scm_is_truthy(_test)) return scm_void();
                var _body = _rest.cdr;
                while (_body.cdr.t == SCM_PAIR) {
                    var _r = scm_eval(_body.car, _env);
                    if (_r.t == SCM_ERR) return _r;
                    _body = _body.cdr;
                }
                _expr = _body.car;
                continue;  // TCO
            }

            if (_form == "unless") {
                var _test = scm_eval(scm_car(_rest), _env);
                if (_test.t == SCM_ERR) return _test;
                if (scm_is_truthy(_test)) return scm_void();
                var _body = _rest.cdr;
                while (_body.cdr.t == SCM_PAIR) {
                    var _r = scm_eval(_body.car, _env);
                    if (_r.t == SCM_ERR) return _r;
                    _body = _body.cdr;
                }
                _expr = _body.car;
                continue;  // TCO
            }

            if (_form == "let*") {
                var _bindings = _rest.car;
                var _body     = _rest.cdr;
                var _new_env  = scm_env_new(_env);
                while (_bindings.t == SCM_PAIR) {
                    var _binding = _bindings.car;
                    var _bval    = scm_eval(scm_cadr(_binding), _new_env);
                    if (_bval.t == SCM_ERR) return _bval;
                    scm_env_set(_new_env, _binding.car.v, _bval);
                    _bindings = _bindings.cdr;
                }
                _env = _new_env;
                while (_body.cdr.t == SCM_PAIR) {
                    var _r = scm_eval(_body.car, _env);
                    if (_r.t == SCM_ERR) return _r;
                    _body = _body.cdr;
                }
                _expr = _body.car;
                continue;  // TCO
            }

            if (_form == "letrec") {
                var _bindings = _rest.car;
                var _body     = _rest.cdr;
                var _new_env  = scm_env_new(_env);
                var _b = _bindings;
                while (_b.t == SCM_PAIR) {
                    scm_env_set(_new_env, _b.car.car.v, scm_void());
                    _b = _b.cdr;
                }
                _b = _bindings;
                while (_b.t == SCM_PAIR) {
                    var _binding = _b.car;
                    var _bval    = scm_eval(scm_cadr(_binding), _new_env);
                    if (_bval.t == SCM_ERR) return _bval;
                    scm_env_set(_new_env, _binding.car.v, _bval);
                    _b = _b.cdr;
                }
                _env = _new_env;
                while (_body.cdr.t == SCM_PAIR) {
                    var _r = scm_eval(_body.car, _env);
                    if (_r.t == SCM_ERR) return _r;
                    _body = _body.cdr;
                }
                _expr = _body.car;
                continue;  // TCO
            }

            if (_form == "do") {
                return scm__eval_do(_rest, _env);
            }

            if (_form == "quasiquote") {
                return scm__eval_qq(scm_car(_rest), _env);
            }

            if (_form == "case") {
                return scm__eval_case(_rest, _env);
            }
        }

        // ── Function application ────────────────────────────────────

        var _fn = scm_eval(_head, _env);
        if (_fn.t == SCM_ERR) return _fn;

        var _args = scm__eval_args(_rest, _env);
        if (_args.t == SCM_ERR) return _args;

        // TCO for lambda: set up env and loop instead of recursing
        if (_fn.t == SCM_LAMBDA) {
            var _new_env = scm_env_new(_fn.env);
            var _bind_err = scm__bind_params(_fn.params, _args, _new_env);
            if (_bind_err != undefined) return scm_err(_fn.name + ": " + _bind_err);
            _env = _new_env;
            var _body = _fn.body;
            while (_body.cdr.t == SCM_PAIR) {
                var _r = scm_eval(_body.car, _env);
                if (_r.t == SCM_ERR) return _r;
                _body = _body.cdr;
            }
            _expr = _body.car;
            continue;  // TCO
        }

        if (_fn.t == SCM_FN) {
            return _fn.fn(_args);
        }

        if (_fn.t == SCM_HANDLE && _fn.ht == SCM_HT_METHOD) {
            return scm__call_gml_method(_fn.v, _args);
        }

        return scm_err("not a procedure: " + scm_to_string(_fn));
    }
}

// ── Apply (non-TCO entry point for builtin `apply` etc.) ────────────

function scm_apply(_fn, _args) {
    if (_fn.t == SCM_FN) {
        return _fn.fn(_args);
    }
    if (_fn.t == SCM_LAMBDA) {
        var _new_env = scm_env_new(_fn.env);
        var _bind_err = scm__bind_params(_fn.params, _args, _new_env);
        if (_bind_err != undefined) return scm_err(_fn.name + ": " + _bind_err);
        return scm_eval_body(_fn.body, _new_env);
    }
    if (_fn.t == SCM_HANDLE && _fn.ht == SCM_HT_METHOD) {
        return scm__call_gml_method(_fn.v, _args);
    }
    return scm_err("not a procedure: " + scm_to_string(_fn));
}

// ── Call a GML method value with Scheme arguments ───────────────────
// Uses script_execute_ext which accepts method references natively.

function scm__call_gml_method(_gml_method, _scm_args) {
    var _gml_args = [];
    var _a = _scm_args;
    while (_a.t == SCM_PAIR) {
        array_push(_gml_args, scm_unwrap(_a.car));
        _a = _a.cdr;
    }
    return scm_wrap(script_execute_ext(_gml_method, _gml_args));
}

// ── Evaluate a body (sequence of expressions) ───────────────────────

function scm_eval_body(_exprs, _env) {
    if (_exprs.t == SCM_NIL) return scm_void();
    while (_exprs.cdr.t == SCM_PAIR) {
        var _r = scm_eval(_exprs.car, _env);
        if (_r.t == SCM_ERR) return _r;
        _exprs = _exprs.cdr;
    }
    return scm_eval(_exprs.car, _env);
}

// ── Evaluate argument list ──────────────────────────────────────────

function scm__eval_args(_args, _env) {
    if (_args.t == SCM_NIL) return scm_nil();

    var _first_val = scm_eval(_args.car, _env);
    if (_first_val.t == SCM_ERR) return _first_val;

    var _head = scm_cons(_first_val, scm_nil());
    var _tail = _head;
    _args = _args.cdr;

    while (_args.t == SCM_PAIR) {
        var _val = scm_eval(_args.car, _env);
        if (_val.t == SCM_ERR) return _val;
        var _pair = scm_cons(_val, scm_nil());
        scm_set_cdr(_tail, _pair);
        _tail = _pair;
        _args = _args.cdr;
    }
    return _head;
}

// ── Bind parameters to arguments ────────────────────────────────────

function scm__bind_params(_params, _args, _env) {
    if (_params.t == SCM_SYM) {
        scm_env_set(_env, _params.v, _args);
        return undefined;
    }
    var _p = _params;
    var _a = _args;
    while (_p.t == SCM_PAIR && _a.t == SCM_PAIR) {
        scm_env_set(_env, _p.car.v, _a.car);
        _p = _p.cdr;
        _a = _a.cdr;
    }
    if (_p.t == SCM_SYM) {
        scm_env_set(_env, _p.v, _a);
        return undefined;
    }
    if (_p.t == SCM_PAIR) return "too few arguments";
    if (_a.t == SCM_PAIR) return "too many arguments";
    return undefined;
}

// ═══════════════════════════════════════════════════════════════════
//  Special form implementations (only non-inlined ones remain)
// ═══════════════════════════════════════════════════════════════════

// ── define ──────────────────────────────────────────────────────────

function scm__eval_define(_rest, _env) {
    var _first = _rest.car;

    if (_first.t == SCM_SYM) {
        var _val = scm_eval(scm_cadr(_rest), _env);
        if (_val.t == SCM_ERR) return _val;
        scm_env_set(_env, _first.v, _val);
        return scm_void();
    }

    if (_first.t == SCM_PAIR) {
        var _name   = _first.car;
        var _params = _first.cdr;
        var _body   = _rest.cdr;
        var _lam    = scm_lambda(_params, _body, _env, _name.v);
        scm_env_set(_env, _name.v, _lam);
        return scm_void();
    }

    return scm_err("bad define syntax");
}

// ── set! ────────────────────────────────────────────────────────────

function scm__eval_set(_rest, _env) {
    var _sym = _rest.car;
    if (_sym.t != SCM_SYM) return scm_err("set!: expected symbol");
    var _val = scm_eval(scm_cadr(_rest), _env);
    if (_val.t == SCM_ERR) return _val;
    if (!scm_env_update(_env, _sym.v, _val)) {
        return scm_err("set!: unbound variable: " + _sym.v);
    }
    return scm_void();
}

// ── Named let ───────────────────────────────────────────────────────

function scm__eval_named_let(_name_sym, _rest, _env) {
    var _bindings = _rest.car;
    var _body     = _rest.cdr;

    var _params = scm_nil();
    var _inits  = scm_nil();
    var _b = _bindings;
    while (_b.t == SCM_PAIR) {
        var _binding = _b.car;
        _params = scm_cons(_binding.car, _params);
        var _val = scm_eval(scm_cadr(_binding), _env);
        if (_val.t == SCM_ERR) return _val;
        _inits = scm_cons(_val, _inits);
        _b = _b.cdr;
    }
    _params = scm_list_reverse(_params);
    _inits  = scm_list_reverse(_inits);

    var _loop_env = scm_env_new(_env);
    var _loop     = scm_lambda(_params, _body, _loop_env, _name_sym.v);
    scm_env_set(_loop_env, _name_sym.v, _loop);

    return scm_apply(_loop, _inits);
}

// ── do ──────────────────────────────────────────────────────────────

function scm__eval_do(_rest, _env) {
    var _var_clauses = _rest.car;
    var _test_clause = scm_cadr(_rest);
    var _commands    = scm_cddr(_rest);

    var _loop_env = scm_env_new(_env);
    var _vars = [];
    var _vc = _var_clauses;
    while (_vc.t == SCM_PAIR) {
        var _clause = _vc.car;
        var _name   = _clause.car.v;
        var _init   = scm_eval(scm_cadr(_clause), _env);
        if (_init.t == SCM_ERR) return _init;
        scm_env_set(_loop_env, _name, _init);

        var _step_expr = (scm_cddr(_clause).t != SCM_NIL) ? scm_caddr(_clause) : undefined;
        array_push(_vars, { name: _name, step: _step_expr });
        _vc = _vc.cdr;
    }

    var _test_expr = _test_clause.car;
    var _result_exprs = _test_clause.cdr;

    while (true) {
        var _test = scm_eval(_test_expr, _loop_env);
        if (_test.t == SCM_ERR) return _test;

        if (scm_is_truthy(_test)) {
            if (_result_exprs.t == SCM_NIL) return scm_void();
            return scm_eval_body(_result_exprs, _loop_env);
        }

        var _cmd = _commands;
        while (_cmd.t == SCM_PAIR) {
            var _r = scm_eval(_cmd.car, _loop_env);
            if (_r.t == SCM_ERR) return _r;
            _cmd = _cmd.cdr;
        }

        var _new_vals = [];
        for (var _i = 0; _i < array_length(_vars); _i++) {
            if (_vars[_i].step != undefined) {
                var _sv = scm_eval(_vars[_i].step, _loop_env);
                if (_sv.t == SCM_ERR) return _sv;
                array_push(_new_vals, _sv);
            } else {
                array_push(_new_vals, scm_env_get(_loop_env, _vars[_i].name));
            }
        }
        for (var _i = 0; _i < array_length(_vars); _i++) {
            scm_env_set(_loop_env, _vars[_i].name, _new_vals[_i]);
        }
    }
}

// ── case ────────────────────────────────────────────────────────────
/// (case expr ((datum ...) body ...) ... [(else body ...)])

function scm__eval_case(_rest, _env) {
    var _key = scm_eval(scm_car(_rest), _env);
    if (_key.t == SCM_ERR) return _key;

    var _clauses = _rest.cdr;
    while (_clauses.t == SCM_PAIR) {
        var _clause = _clauses.car;
        var _datums = _clause.car;

        // (else body ...)
        if (_datums.t == SCM_SYM && _datums.v == "else") {
            return scm_eval_body(_clause.cdr, _env);
        }

        // ((datum ...) body ...)
        var _d = _datums;
        while (_d.t == SCM_PAIR) {
            if (scm_equal(_key, _d.car)) {
                return scm_eval_body(_clause.cdr, _env);
            }
            _d = _d.cdr;
        }

        _clauses = _clauses.cdr;
    }
    return scm_void();
}

// ── Quasiquote ──────────────────────────────────────────────────────

function scm__eval_qq(_expr, _env) {
    if (_expr.t != SCM_PAIR) return _expr;

    if (_expr.car.t == SCM_SYM && _expr.car.v == "unquote") {
        return scm_eval(scm_cadr(_expr), _env);
    }

    var _result = scm_nil();
    var _p = _expr;
    while (_p.t == SCM_PAIR) {
        var _item = _p.car;

        if (_item.t == SCM_PAIR && _item.car.t == SCM_SYM &&
            _item.car.v == "unquote-splicing") {
            var _spliced = scm_eval(scm_cadr(_item), _env);
            if (_spliced.t == SCM_ERR) return _spliced;
            while (_spliced.t == SCM_PAIR) {
                _result = scm_cons(_spliced.car, _result);
                _spliced = _spliced.cdr;
            }
        } else {
            _result = scm_cons(scm__eval_qq(_item, _env), _result);
        }
        _p = _p.cdr;
    }

    if (_p.t != SCM_NIL) {
        var _reversed = scm__eval_qq(_p, _env);
        while (_result.t == SCM_PAIR) {
            _reversed = scm_cons(_result.car, _reversed);
            _result = _result.cdr;
        }
        return _reversed;
    }

    return scm_list_reverse(_result);
}
