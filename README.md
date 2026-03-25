# GML Scheme — A Scheme Interpreter for GameMaker

A Scheme subset interpreter implemented in GML (GameMaker Language), designed for runtime debugging, effect testing, and mod development in [Stoneshard](https://store.steampowered.com/app/625960/Stoneshard/).

## Why Scheme?

Scheme hits a unique sweet spot: **extremely powerful as a scripting layer, yet tractable to implement from scratch in GML**.

- **Trivial to parse** — parenthesized syntax needs no grammar tables or libraries; a recursive-descent reader fits in ~100 lines of GML
- **Minimal core, maximum leverage** — a handful of special forms plus closures and first-class functions cover virtually all use cases; the language is small enough to implement fully, not just sketch
- **Homoiconicity** — code is data; `define-macro` can construct and transform ASTs directly, letting the bridge API feel idiomatic without any code generation
- **TCO is well-specified and necessary** — GML's call stack caps at ~256 frames; the trampoline pattern is a clean, self-contained solution that makes safe recursion and iteration possible at all
- **Single-file injection** — the entire interpreter bundles to one `.gml` for frictionless UMT installation

## Features

- Tree-walking evaluator with **trampoline-based tail-call optimization (TCO)**
- Lexically-scoped environments with closures
- 161 auto-generated GML builtin wrappers (codegen)
- Two-layer standard library: R5RS `prelude.scm` + GML-domain `stdlib.scm`
- In-game REPL with syntax highlighting, command history, and completion
- Tab inline completion + F3 fuzzy search overlay (asset/global/env candidates)
- Bilingual (Chinese/English) in-game help database (272 entries)
- Single-file bundle output for easy injection via UMT C# scripts

## Project Structure

```
gml_scheme/
├── README.md
├── GUIDE.md                      Dev/modding guide
├── build.py                      Build orchestrator (codegen → bundle → verify)
├── bundle.py                     Concatenator (called by build.py)
├── codegen_builtins.py           Generates scm_gml_builtins.gml from spec
├── codegen_help.py               Generates scm_help.gml (bilingual help DB)
├── codegen_meta.py               Validates data/meta/*.json for completion engine
├── help_db.py                    Help entry definitions
├── run_export_meta.py            (noop — export must be done manually via ExportMeta.csx)
├── _verify_bundle.py             Post-build verification + UMT bytecode lint
├── local.json                    Local paths config (gitignored)
├── src/                          GML sources (injected into game)
│   ├── scm_types.gml            Type system: tags, constructors, predicates
│   ├── scm_env.gml              Lexically-scoped environments
│   ├── scm_read.gml             Reader (tokenizer + parser)
│   ├── scm_print.gml            Value printer
│   ├── scm_eval.gml             Evaluator + TCO trampoline
│   ├── scm_core.gml             Core built-in procedures
│   ├── scm_gml_builtins.gml     Auto-generated GML wrappers (DO NOT EDIT)
│   ├── scm_bridge.gml           Hand-written FFI (ffi:proc->method)
│   ├── scm_init.gml             Init, stdlib loading, public API
│   ├── scm_help.gml             Auto-generated help DB — DO NOT EDIT
│   ├── scm_input.gml            Time-based key repeat handler
│   ├── scm_tty.gml              Virtual terminal (font metrics, wrapping, scroll)
│   ├── scm_ui.gml               Lightweight draw primitives for REPL UI
│   ├── scm_lex.gml              Lexer for syntax highlighting
│   ├── scm_sexpr.gml            S-expression structure analysis (indent, balance)
│   ├── scm_comp.gml             Completion engine (Tab popup + F3 fuzzy overlay)
│   ├── scm_repl_shell.gml       Native GML REPL shell (keyboard, draw, history)
│   ├── prelude.scm              R5RS-compatible standard library (pure Scheme)
│   ├── stdlib.scm               GML interop & game-domain helpers (pure Scheme)
│   ├── scm_repl.scm             Self-hosted Scheme REPL logic (v2)
│   └── comp-init.scm            Completion configuration (asset dicts + handlers)
├── scripts/                      UMT C# installer scripts
│   ├── InstallScmReplStub.csx   Active installer (stub pre-registration strategy)
│   ├── ExportMeta.csx           Export asset metadata from loaded game data
│   ├── InstallScmRepl.csx       (legacy — bytecode-patch strategy, superseded)
│   └── PatchScmBundle.csx       (legacy — standalone bytecode patcher, superseded)
└── build/                        Build output
    ├── scm_bundle.gml            Output: single-file bundle
    ├── scm_stubs.gml             Function stubs for UMT pre-registration
    └── scm_data/                 Asset name JSON files for completion
        ├── objects.json
        ├── sprites.json
        ├── sounds.json
        ├── rooms.json
        ├── scripts.json
        ├── functions.json
        ├── globals.json
        └── obj_tree.json
```

## Quick Start

### 1. Build

```bash
# Full rebuild (codegen → bundle → verify)
python gml_scheme/build.py

# Quick rebuild (skip codegen, only bundle + verify)
python gml_scheme/build.py --quick

# Export asset metadata from game, then full rebuild
# (NOTE: run_export_meta.py is currently a noop —
#  run scripts/ExportMeta.csx manually in UMT first)
python gml_scheme/build.py --export
```

The build pipeline:
1. `codegen_builtins` → `src/scm_gml_builtins.gml`
2. `codegen_meta` → validates `data/meta/*.json` (trie/masks are built at GML runtime)
3. `codegen_help` → `src/scm_help.gml`
4. `bundle` → `build/scm_bundle.gml` + `scm_stubs.gml` + `scm_data/`
5. `verify` → reference integrity + UMT bytecode lint

### 2. Inject into Game

Run `scripts/InstallScmReplStub.csx` in UndertaleModTool. This script uses the **stub pre-registration** strategy:
1. Imports `build/scm_stubs.gml` as `scm_bundle` (pre-registers all function names)
2. Replaces with real `build/scm_bundle.gml` (compiler emits direct `call.i` because names are already known)
3. Creates `o_scm_repl` game object with Create/Step/Draw/Destroy events
4. Injects `scm_repl_toggle()` into an existing input handler (toggle key: **F1**)

Prerequisites: game data (`data.win`) loaded in UMT, bundle built. Asset metadata in `build/scm_data/` must be populated first (run `scripts/ExportMeta.csx` in UMT, then rebuild).

Alternatively, inject individual `src/*.gml` files in dependency order:

```
scm_types → scm_env → scm_read → scm_print → scm_eval → scm_core →
scm_gml_builtins → scm_bridge → scm_init → scm_help → scm_input →
scm_tty → scm_ui → scm_lex → scm_sexpr → scm_comp → scm_repl_shell
```

### 3. Initialize

Call once at game startup (or rely on auto-init — the bundle calls `scm_init()` as top-level code on load):

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

// REPL-style (prints prompt + result to output buffer)
scm_repl_eval("(map (lambda (x) (* x x)) '(1 2 3))");
```

### 5. In-Game REPL

The REPL UI is managed by the `o_scm_repl` object (installed by `InstallScmRepl.csx`):

```gml
// Toggle REPL visibility (default key: F1)
scm_repl_toggle();

// Manual lifecycle (if managing the object yourself)
scm_repl_create();   // Create event
scm_repl_step();     // Step event
scm_repl_draw();     // Draw GUI event
scm_repl_destroy();  // Destroy event
```

REPL features:
- Syntax-colored input line (keywords, builtins, macros, strings)
- Multi-line editing with auto-indent
- Command history (Up/Down arrows)
- **Tab** — prefix-based inline completion (bash-style, shows popup at fork)
- **F3** — fuzzy search overlay across env bindings and asset dictionaries
- `(help "symbol")` — display inline help for any procedure or special form

## Language Features

### Scheme Subset

| Category | Support |
|----------|---------|
| **Data types** | Number, string, boolean, symbol, pair/list, nil, void, handle |
| **Special forms** | `define`, `lambda`, `if`, `cond`, `when`, `unless`, `and`, `or`, `begin`, `let`, `let*`, `letrec`, `set!`, `quote`, `quasiquote`, `do`, `case`, `case-lambda`, `define-macro`, `guard` |
| **Named let** | `(let loop ((x 0)) (if (= x 10) x (loop (+ x 1))))` |
| **Variadic** | `(lambda (a b . rest) ...)`, `(lambda args ...)` |
| **Closures** | Full lexical-scope closures |
| **Quasiquote** | `` `(a ,b ,@c) `` |
| **Dotted pair** | `(cons 1 2)` → `(1 . 2)` |
| **TCO** | Trampoline-based tail-call optimization in `if`, `cond`, `when`, `unless`, `begin`, `let`, `and`, `or` |
| **case-lambda** | `(case-lambda ((x) x) ((x y) (+ x y)))` — arity dispatch |
| **Macros** | `define-macro` (Lisp-style, non-hygienic): transformer receives unevaluated args, returns AST |

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

### Prelude & Stdlib (Standard Libraries in Scheme)

Two Scheme files are embedded as string literals and evaluated at init time:

- **`prelude.scm`** — R5RS-compatible library. Pure Scheme built on core builtins. No GML-specific content. See [src/prelude.scm](src/prelude.scm).
- **`stdlib.scm`** — GML interop and game-domain helpers. Defines bridge wrappers (`array?`, `struct?`, `ds-map->alist`, `list->array`, `make-struct`, etc.), asset discovery, pretty printer (`pp`, `probe`), and short-name aliases. See [src/stdlib.scm](src/stdlib.scm).

## Game Bridge API

The bridge is the core feature — interact with game state directly from Scheme.

Bridge procedures fall into three layers:
- **`scm_gml_builtins.gml`** — mechanical 1:1 GML wrappers under the `gml:` prefix (auto-generated)
- **`stdlib.scm`** — higher-level helpers built over those wrappers (array/struct/ds helpers, asset discovery)
- **`scm_bridge.gml`** — one hand-written procedure requiring SCM internals: `ffi:proc->method`

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

; ds_map helpers (stdlib.scm)
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

; ds_list helpers (stdlib.scm)
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

### Pretty Printer

```scheme
(pp value)                  ; pretty-print any Scheme value
(probe value)               ; pp with GML type detection (resolves asset indices)
```

### Utility

```scheme
(log "message" x y)       ; → display to output buffer (variadic)
(gml:current-time)         ; → current_time
(gml:room)                 ; → current room index
(gml:room-get-name room)   ; → room name string
(gml:self)                 ; → self instance
(gml:noone)                ; → GML noone constant
(ffi:proc->method proc)    ; → GML callable method from Scheme procedure
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
      (log "HP changed: " prev-hp " → " cur)
      (set! prev-hp cur))))

; Call (check-hp-change) in a Step event
```

## Architecture

```
codegen_builtins.py
         │
         ▼
  scm_gml_builtins.gml
    161 GML wrappers ─┐
                      │
  codegen_help.py ────► scm_help.gml (272 entries)
                      │          │
  scm_types ──┐       │          │
  scm_env  ───┤       │          │
  scm_read ───┤       │          │
  scm_print ──┤       │          │
  scm_eval ───┼── bundle.py ─────┴──► build/scm_bundle.gml
  scm_core ───┤       │                      │
  gml_builtins┤       │              scm_stubs.gml
  scm_bridge ─┤       │              scm_data/ (asset JSONs)
  scm_init ───┤       │                      │
  scm_help ───┤       │       _verify_bundle.py (sanity check)
  scm_input ──┤       │
  scm_tty ────┤       │
  scm_ui ─────┤       │
  scm_lex ────┤       │
  scm_sexpr ──┤       │
  scm_comp ───┤       │
  scm_repl_shell┘     │
       ↑
  prelude.scm  ─── embedded as GML string literals
  stdlib.scm   ─┘  (@@PRELUDE@@ / @@STDLIB@@ replaced at bundle time)
  scm_repl.scm ─── self-hosted Scheme REPL logic
  comp-init.scm──── completion configuration
```

`build.py` orchestrates the full pipeline: codegen → bundle → verify.

`bundle.py` concatenates sources in dependency order and embeds the three `.scm` files as GML string literals (replacing `@@PRELUDE@@`, `@@STDLIB@@`, `@@REPL@@`, `@@COMP_INIT@@` placeholders in `scm_init.gml`).

`_verify_bundle.py` checks that all `scm_bi_*` references resolve, no orphan definitions exist, and enforces UMT bytecode 17 constraints (no `[$]`, `[?]`, `[@]`, `struct_set()`, `is_instanceof()`).

`scripts/InstallScmReplStub.csx` installs the bundle using stub pre-registration (no bytecode patching required) and wires up the `o_scm_repl` game object.

## Known Limitations

- **GML call stack ~256 frames** — TCO handles tail positions, but non-tail recursion can still overflow. Prefer `do` or named `let` for iteration
- **No continuations** — no `call/cc`
- **No hygienic macros** — no `syntax-rules`; use `quasiquote` for manual code construction
- **Single numeric type** — maps to GML `real`, no exact integers or rationals
- **No multiple return values** — use lists instead of `values`/`call-with-values`

## Roadmap

- [x] In-game REPL console UI (text input + output display, syntax highlighting)
- [x] `define-macro` with basic pattern matching (Lisp-style, non-hygienic)
- [x] Tab inline completion + F3 fuzzy search overlay
- [x] Bilingual in-game help database
- [x] Stub pre-registration installer (no bytecode patching)

## License

MIT
