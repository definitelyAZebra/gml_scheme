/// scm_env.gml — Lexically-scoped environments
///
/// Each environment is a struct { parent, bindings }.
/// `bindings` is also a struct, use variable_struct_* for dynamic key access.

// ── Create / lookup / set ───────────────────────────────────────────

/// Create a new environment frame extending _parent (or undefined for root).
function scm_env_new(_parent) {
    return {
        parent:   _parent,
        bindings: {}
    };
}

/// Look up _sym (a GML string) in the environment chain.
/// Returns the Scheme value, or undefined if unbound.
function scm_env_get(_env, _sym) {
    var _e = _env;
    while (_e != undefined) {
        var _val = variable_struct_get(_e.bindings, _sym);
        if (_val != undefined) return _val;
        _e = _e.parent;
    }
    return undefined;
}

/// Define (or overwrite) _sym in the **current** frame.
function scm_env_set(_env, _sym, _val) {
    variable_struct_set(_env.bindings, _sym, _val);
}

/// set! semantics: find the closest frame that has _sym and update it.
/// Returns true if found, false if unbound.
function scm_env_update(_env, _sym, _val) {
    var _e = _env;
    while (_e != undefined) {
        if (variable_struct_exists(_e.bindings, _sym)) {
            variable_struct_set(_e.bindings, _sym, _val);
            return true;
        }
        _e = _e.parent;
    }
    return false;
}
