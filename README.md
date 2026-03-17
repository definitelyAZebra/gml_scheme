# GML Scheme — A Scheme Interpreter for GameMaker

A Scheme subset interpreter implemented in GML (GameMaker Language), designed for runtime debugging, effect testing, and mod development in [Stoneshard](https://store.steampowered.com/app/625960/Stoneshard/).

## Why Scheme?

- **S-expressions are REPL-friendly** — one line = one complete expression, no multi-line input management
- **Closures + higher-order functions** — compose complex game operation pipelines
- **Minimal syntax** — the interpreter is compact, easy to inject into a game
- **Sandboxed** — game state is only accessible via bridge functions

## Features

- Tree-walking evaluator with **trampoline-based tail-call optimization (TCO)**
- Lexically-scoped environments with closures
- 69 auto-generated GML builtin wrappers (codegen)
- Prelude standard library written in pure Scheme
- Single-file bundle output for easy injection

## Project Structure

```
gml_scheme/
├── README.md
├── src/                          GML sources (injected into game)
│   ├── scm_types.gml            Type system: tags, constructors, predicates
│   ├── scm_env.gml              Lexically-scoped environments
│   ├── scm_read.gml             Reader (tokenizer + parser)
│   ├── scm_print.gml            Value printer
│   ├── scm_eval.gml             Evaluator + TCO trampoline
│   ├── scm_core.gml             Core built-in procedures
│   ├── scm_gml_builtins.gml     Auto-generated GML wrappers (DO NOT EDIT)
│   ├── scm_bridge.gml           Hand-written game FFI
│   ├── scm_init.gml             Init, prelude loading, public API
│   └── prelude.scm              Standard library (pure Scheme)
├── codegen_builtins.py           Generates scm_gml_builtins.gml from spec
├── bundle.py                     Bundles all src/ into a single GML file
├── _verify_bundle.py             Post-build verification
└── build/
    └── scm_bundle.gml            Output: single-file bundle
```

## Quick Start

### 1. Build

```bash
# (Optional) Regenerate GML builtin wrappers from spec
python codegen_builtins.py

# Bundle all sources into a single file
python bundle.py

# Verify bundle integrity
python _verify_bundle.py
```

### 2. Inject into Game

Inject `build/scm_bundle.gml` into Stoneshard via UndertaleModTool as a single script.

Alternatively, inject individual `src/*.gml` files in dependency order:

```
scm_types → scm_env → scm_read → scm_print → scm_eval → scm_core → scm_gml_builtins → scm_bridge → scm_init
```

### 3. Initialize

Call once at game startup:

```gml
scm_init();
```

### 4. Use

```gml
// Evaluate a single expression
var _result = scm_eval_string("(+ 1 2 3)");
show_debug_message(scm_to_string(_result));  // "6"

// Evaluate a program (multiple expressions)
scm_eval_program("(define x 42) (display x)", undefined);

// Evaluate from file
scm_eval_file("mods/my_script.scm");

// REPL-style (auto-prints result to output buffer)
scm_repl_eval("(map (lambda (x) (* x x)) '(1 2 3))");

// Run self-tests
scm_self_test();
```

## Language Features

### Scheme Subset

| Category | Support |
|----------|---------|
| **Data types** | Number, string, boolean, symbol, pair/list, nil, void, handle |
| **Special forms** | `define`, `lambda`, `if`, `cond`, `when`, `unless`, `and`, `or`, `begin`, `let`, `let*`, `letrec`, `set!`, `quote`, `quasiquote`, `do` |
| **Named let** | `(let loop ((x 0)) (if (= x 10) x (loop (+ x 1))))` |
| **Variadic** | `(lambda (a b . rest) ...)`, `(lambda args ...)` |
| **Closures** | Full lexical-scope closures |
| **Quasiquote** | `` `(a ,b ,@c) `` |
| **Dotted pair** | `(cons 1 2)` → `(1 . 2)` |
| **TCO** | Trampoline-based tail-call optimization in `if`, `cond`, `when`, `unless`, `begin`, `let`, `and`, `or` |

### Built-in Procedures

**Arithmetic**: `+` `-` `*` `/` `modulo` `abs` `floor` `ceiling` `round` `sqrt` `expt` `sign` `min` `max` `clamp` `sin` `cos` `random` `irandom` `lerp`

**Comparison**: `=` `<` `>` `<=` `>=` (chained: `(< 1 2 3)` → `#t`)

**Predicates**: `null?` `pair?` `number?` `string?` `symbol?` `boolean?` `list?` `zero?` `positive?` `negative?` `even?` `odd?` `integer?` `procedure?` `void?` `equal?` `eq?` `eqv?` `not`

**List**: `cons` `car` `cdr` `set-car!` `set-cdr!` `list` `length` `reverse` `append` `list-ref` `list-tail` `cadr` `caar` `cdar` `cddr` `cadar` `caddr` `cdddr` `last` `take` `drop` `zip` `flatten`

**Higher-order**: `map` `filter` `remove` `for-each` `foldl` `foldr` `append-map` `any` `every` `find` `count` `partition` `compose` `identity` `const` `flip`

**String**: `string-length` `string-ref` `string-append` `substring` `string->number` `number->string` `string->symbol` `symbol->string` `string-contains?` `string-upcase` `string-downcase` `string-split` `string-empty?` `string-join`

**Association list**: `assoc` `member` `alist-ref` `alist-set`

**Builders**: `range` `iota` `make-list`

**I/O**: `display` `write` `print` `newline`

**Control**: `apply` `error` `void` `gensym`

### Prelude (Standard Library in Scheme)

The prelude is loaded at init time and defines higher-order functions, list utilities, and GML bridge helpers entirely in Scheme. See [src/prelude.scm](src/prelude.scm) for the full source.

## Game Bridge API

The bridge is the core feature — interact with game state directly from Scheme.

### Instance Variables

```scheme
(define player (gml:instance-find (gml:asset-get-index "o_player") 0))

(instance-get player "hp")            ; read
(instance-set! player "hp" 100)       ; write
(gml:variable-instance-exists player "custom_var")  ; check existence
(instance-exists? player)              ; alive?
```

### Global Variables

```scheme
(global-get "game_difficulty")           ; read
(global-set! "my_flag" #t)              ; write
(gml:variable-global-exists "some_var") ; check
```

### Struct Access

```scheme
(struct-get my-struct "field")         ; read
(struct-set! my-struct "field" 42)     ; write
(struct-has? my-struct "field")        ; check existence
(struct-keys my-struct)                ; → ("field1" "field2" ...)
(struct-values my-struct)              ; → (val1 val2 ...)
(struct->alist my-struct)              ; → ((key . val) ...)
(make-struct)                          ; → empty struct {}
(alist->struct '(("a" . 1) ("b" . 2))) ; → struct from pairs
```

### ds_map / ds_list

```scheme
; ds_map — verbose gml: prefix (manual destroy required)
(gml:ds-map-find-value map-id "key")
(gml:ds-map-set map-id "key" value)
(gml:ds-map-exists map-id "key")
(gml:ds-map-size map-id)
(gml:ds-map-create)                  ; → new map (must destroy!)
(gml:ds-map-destroy map-id)          ; free memory

; ds_map helpers (prelude)
(ds-map-keys map-id)                 ; → list of keys
(ds-map-values map-id)               ; → list of values
(ds-map->alist map-id)               ; → ((key . val) ...)
(alist->ds-map '(("a" . 1)))         ; → new map (must destroy!)

; ds_list — verbose gml: prefix (manual destroy required)
(gml:ds-list-find-value list-id 0)
(gml:ds-list-set list-id 0 value)
(gml:ds-list-size list-id)
(gml:ds-list-create)                 ; → new list (must destroy!)
(gml:ds-list-add list-id value)
(gml:ds-list-destroy list-id)        ; free memory

; ds_list helpers (prelude / bridge)
(ds-list->list list-id)              ; → Scheme list
(list->ds-list '(1 2 3))             ; → new list (must destroy!)
```

### Instance Lookup

```scheme
(gml:instance-find (gml:asset-get-index "o_enemy") 0)  ; nth instance
(gml:instance-number (gml:asset-get-index "o_enemy"))   ; count
(instance-exists? inst-id)                               ; alive?
(gml:asset-get-index "o_player")                         ; name → index
```

### Array Operations

```scheme
(array-length arr)                   ; length
(array-ref arr 0)                    ; read element
(array-set! arr 0 value)             ; write element
(gml:array-push arr value)           ; append
(array-create 10)                    ; new array of size 10
(gml:array-copy arr)                 ; shallow copy
(array->list arr)                    ; → Scheme list
(list->array '(1 2 3))               ; → GML array
```

### Type Inspection

```scheme
(typeof value)              ; → "number", "string", "pair", "array", "struct", etc.
(handle? value)             ; is a GML handle?
(array? value)              ; is a GML array?
(struct? value)             ; is a GML struct?
(method? value)             ; is a GML method?
```

### Utility

```scheme
(debug-log "message" x y)  ; → show_debug_message (variadic)
(gml:current-time)         ; → current_time
(gml:room)                 ; → current room index
(gml:room-get-name room)   ; → room name string
(gml:self)                 ; → self instance
(gml:noone)                ; → GML noone constant
```

## Examples

### Runtime Attribute Inspection

```scheme
(define player (gml:instance-find (gml:asset-get-index "o_player") 0))

; Iterate over player attributes
(for-each
  (lambda (attr)
    (when (gml:variable-instance-exists player attr)
      (display (string-append attr ": "
        (number->string (instance-get player attr)) "\n"))))
  '("STR" "AGI" "PRC" "VIT" "WIL"))
```

### Batch Modification Test

```scheme
; Test how different attribute combos affect damage
(define (test-damage str agi)
  (instance-set! player "STR" str)
  (instance-set! player "AGI" agi)
  (let ((dmg (instance-get player "Damage")))
    (display (string-append
      "STR=" (number->string str)
      " AGI=" (number->string agi)
      " → DMG=" (number->string dmg) "\n"))))

(for-each
  (lambda (combo) (test-damage (car combo) (cdr combo)))
  '((10 . 10) (15 . 10) (20 . 10) (10 . 15) (10 . 20)))
```

### Monitor Variable Changes

```scheme
(define prev-hp (instance-get player "hp"))

(define (check-hp-change)
  (let ((cur (instance-get player "hp")))
    (when (not (= cur prev-hp))
      (debug-log "HP changed: " prev-hp " → " cur)
      (set! prev-hp cur))))

; Call (check-hp-change) in a Step event
```

## Architecture

```
codegen_builtins.py
         │
         ▼
  scm_gml_builtins.gml
    69 GML wrappers ──┐
                      │
  scm_types ──┐       │
  scm_env  ───┤       │
  scm_read ───┤       │
  scm_print ──┤       │
  scm_eval ───┼── bundle.py ──→ build/scm_bundle.gml
  scm_core ───┤                       │
  gml_builtins┘                       │
  scm_bridge ─┤               _verify_bundle.py
  scm_init ───┘                  (sanity check)
       ↑
  prelude.scm (embedded as string literal)
```

`bundle.py` concatenates sources in dependency order and embeds `prelude.scm` as a GML string literal (replacing the `@@PRELUDE@@` placeholder in `scm_init.gml`).

`_verify_bundle.py` checks that all `scm_bi_*` references resolve, no orphan definitions exist, and prelude aliases match registered builtins.

## Known Limitations

- **GML call stack ~256 frames** — TCO handles tail positions, but non-tail recursion can still overflow. Prefer `do` or named `let` for iteration
- **No continuations** — no `call/cc`
- **No hygienic macros** — no `syntax-rules`; use `quasiquote` for manual code construction
- **Single numeric type** — maps to GML `real`, no exact integers or rationals
- **No multiple return values** — use lists instead of `values`/`call-with-values`

## Roadmap

- [ ] In-game REPL console UI (text input + output display)
- [ ] `define-macro` with basic pattern matching
- [ ] Error stack traces
- [ ] Mod hot-reload: watch `.scm` file changes
- [ ] Persistent environment: save/restore definitions to file

## License

MIT
