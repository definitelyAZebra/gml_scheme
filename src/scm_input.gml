// ═══════════════════════════════════════════════════════════════════
//  scm_input.gml — Time-based Key Repeat
// ═══════════════════════════════════════════════════════════════════
//  Frame-rate independent key repeat using current_time (milliseconds).
//  Behavior: press → immediate fire. Hold 250ms → first repeat.
//  Then repeat every 30ms (~33 repeats/sec).
//
//  Depends on:  nothing (standalone)
//  Used by:     scm_repl_shell.gml
// ═══════════════════════════════════════════════════════════════════

/// Initialize the input layer. Call once during create.
function scm_input_init() {
    // Two ds_maps storing real values (ds_map can't store arrays)
    //   __input_key_pressed: vk → timestamp of initial press (ms)
    //   __input_key_fired:   vk → timestamp of last fire (ms)
    global.__input_key_pressed = ds_map_create();
    global.__input_key_fired   = ds_map_create();
}

/// Cleanup input resources.
function scm_input_destroy() {
    if (ds_exists(global.__input_key_pressed, ds_type_map)) {
        ds_map_destroy(global.__input_key_pressed);
    }
    if (ds_exists(global.__input_key_fired, ds_type_map)) {
        ds_map_destroy(global.__input_key_fired);
    }
}

/// Check if key _vk should fire this frame.
/// Returns true on initial press and during repeat.
function scm_input_key_tick(_vk) {
    if (!keyboard_check(_vk)) {
        // Key released: clean up state
        ds_map_delete(global.__input_key_pressed, _vk);
        ds_map_delete(global.__input_key_fired, _vk);
        return false;
    }

    var _now = current_time; // milliseconds since OS boot

    if (!ds_map_exists(global.__input_key_pressed, _vk)) {
        // Initial press: fire immediately, record timestamps
        ds_map_set(global.__input_key_pressed, _vk, _now);
        ds_map_set(global.__input_key_fired, _vk, _now);
        return true;
    }

    var _pressed_at = ds_map_find_value(global.__input_key_pressed, _vk);
    var _last_fire  = ds_map_find_value(global.__input_key_fired, _vk);
    var _since_press = _now - _pressed_at;
    var _since_fire  = _now - _last_fire;

    // Initial delay: 250ms from first press before any repeat
    if (_since_press < 250) return false;

    // After initial delay: repeat every 30ms
    if (_since_fire >= 30) {
        ds_map_set(global.__input_key_fired, _vk, _now);
        return true;
    }

    return false;
}

/// Reset all key repeat state (call on REPL toggle).
function scm_input_reset_keys() {
    ds_map_clear(global.__input_key_pressed);
    ds_map_clear(global.__input_key_fired);
}
