;; comp-init.scm — String-context completion configuration
;;
;; Loaded during REPL startup (after scm_comp_init).
;; Registers completers for functions that take asset/global names as strings.
;;
;; Each completer specifies:
;;   - Which function + argument index triggers string completion
;;   - Dict(s) of candidate names (indexed at registration time)
;;   - An insert function that transforms the selected name for insertion

;; ── Helper: load a dict from scm_data JSON file ─────────────────
(define (comp:load-dict data-file tag)
  (comp:make-dict
    (gml:json-parse (file->string data-file))
    tag))

;; ── Create dicts for each asset category ────────────────────
(define object-dict  (comp:load-dict "scm_data/objects.json"   "object"))
(define sprite-dict  (comp:load-dict "scm_data/sprites.json"   "sprite"))
(define sound-dict   (comp:load-dict "scm_data/sounds.json"    "sound"))
(define room-dict    (comp:load-dict "scm_data/rooms.json"     "room"))
(define script-dict  (comp:load-dict "scm_data/scripts.json"   "script"))
(define func-dict    (comp:load-dict "scm_data/functions.json" "func"))
(define global-dict  (comp:load-dict "scm_data/globals.json"   "global"))

;; ── Identity insert: just the name (cursor is already inside quotes) ─
(define comp:insert-identity (lambda (name) name))

;; ── Register completers ─────────────────────────────────────

;; (gml:asset-get-index "name") — all asset categories
(comp:on "gml:asset-get-index" 0
  (list object-dict sprite-dict sound-dict room-dict script-dict)
  comp:insert-identity
  "assets")

;; (gml:variable-global-get "name") — global variables + functions
(comp:on "gml:variable-global-get" 0
  (list global-dict func-dict)
  comp:insert-identity
  "globals")

;; (gml:variable-global-set "name" value) — global variables + functions (first arg)
(comp:on "gml:variable-global-set" 0
  (list global-dict func-dict)
  comp:insert-identity
  "globals")

;; (gml:variable-global-exists "name") — global variables + functions
(comp:on "gml:variable-global-exists" 0
  (list global-dict func-dict)
  comp:insert-identity
  "globals")

;; (instances-of "name") — object instances
(comp:on "instances-of" 0
  (list object-dict)
  comp:insert-identity
  "objects")

;; (object-children "name") — child objects
(comp:on "object-children" 0
  (list object-dict)
  comp:insert-identity
  "objects")

;; (object-parent "name") — parent lookup
(comp:on "object-parent" 0
  (list object-dict)
  comp:insert-identity
  "objects")

;; (object-ancestors "name") — ancestor chain
(comp:on "object-ancestors" 0
  (list object-dict)
  comp:insert-identity
  "objects")
