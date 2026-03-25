; ═══════════════════════════════════════════════════════════════
;  stdlib.scm — Non-standard library (GML interop & game domain)
;
;  Loaded after prelude.scm.  Everything here depends on gml:
;  builtins and is NOT part of R5RS Scheme.
;
;  Sections:
;    • Handle type predicates (array?, struct?, method?)
;    • Constants (noone)
;    • Constructors & converters (array, struct, alist->struct, list->array)
;    • GML bridge helpers (array->list, ds_map, ds_list, struct iteration)
;    • DS type predicates
;    • Pretty Printer (pp, probe) — with asset index detection
;    • DS constructors
;    • GML short aliases (instance, global, struct, array, object, sprite, ...)
;    • Asset discovery (search-*, object-*)
;    • Logging
; ═══════════════════════════════════════════════════════════════

; ── Handle type predicates ───────────────────────────────────
; These check GML runtime types via codegen wrappers.
; gml:is-array/is-struct/is-method unwrap the SCM handle first,
; so they test the underlying GML value rather than the SCM tag.

(define array?  gml:is-array)
(define struct? gml:is-struct)
(define method? gml:is-method)

; ── Constants ────────────────────────────────────────────────
(define noone -4)

; ── Constructors & converters ────────────────────────────────

;; (array arg ...) → GML array from arguments (variadic, shallow)
(define (array . args)
  (list->array args))

;; (struct key val ...) → GML struct from key-value pairs (variadic, shallow)
(define (struct . args)
  (let ((s (gml:struct-create)))
    (let loop ((p args))
      (cond
        ((null? p) s)
        ((null? (cdr p))
         (error "struct: odd number of arguments (missing value for key " (car p) ")"))
        (else
         (gml:variable-struct-set s (car p) (cadr p))
         (loop (cddr p)))))))

;; (alist->struct alist) → GML struct from ((key . val) ...) pairs (shallow)
(define (alist->struct alist)
  (let ((s (gml:struct-create)))
    (for-each
      (lambda (p) (gml:variable-struct-set s (car p) (cdr p)))
      alist)
    s))

;; (list->array lst) → GML array from Scheme list (shallow)
(define (list->array lst)
  (let* ((n (length lst))
         (a (gml:array-create n)))
    (let loop ((i 0) (p lst))
      (if (null? p) a
        (begin (gml:array-set a i (car p))
               (loop (+ i 1) (cdr p)))))))

; ── GML bridge helpers ───────────────────────────────────────
; Built on gml: builtins. These compose codegen wrappers — moved
; here from scm_bridge.gml since they need no SCM internals.

;; (array->list arr) → Scheme list from GML array (shallow wrap)
(define (array->list arr)
  (let ((n (gml:array-length arr)))
    (let loop ((i (- n 1)) (acc '()))
      (if (< i 0) acc
        (loop (- i 1) (cons (gml:array-get arr i) acc))))))

;; (ds-list->list id) → Scheme list from ds_list (shallow wrap)
(define (ds-list->list lst)
  (let ((n (gml:ds-list-size lst)))
    (let loop ((i (- n 1)) (acc '()))
      (if (< i 0) acc
        (loop (- i 1) (cons (gml:ds-list-find-value lst i) acc))))))

;; (script-execute script_index arg ...) → call legacy GML script (variadic)
(define (script-execute scr . args)
  (gml:script-execute-ext scr (list->array args)))

; ds_map iteration: scm_wrap(undefined) → nil terminates.

(define (ds-map-keys m)
  (let loop ((k (gml:ds-map-find-first m)) (acc '()))
    (if (null? k) (reverse acc)
      (loop (gml:ds-map-find-next m k) (cons k acc)))))

(define (ds-map-values m)
  (map (lambda (k) (gml:ds-map-find-value m k)) (ds-map-keys m)))

(define (ds-map->alist m)
  (map (lambda (k) (cons k (gml:ds-map-find-value m k))) (ds-map-keys m)))

(define (struct-keys s)
  (let* ((names (gml:variable-struct-get-names s))
         (n (gml:array-length names)))
    (let loop ((i 0) (acc '()))
      (if (= i n) (reverse acc)
        (loop (+ i 1) (cons (gml:array-get names i) acc))))))

(define (struct-values s)
  (map (lambda (k) (gml:variable-struct-get s k)) (struct-keys s)))

(define (struct->alist s)
  (map (lambda (k) (cons k (gml:variable-struct-get s k))) (struct-keys s)))

; ── DS type predicates ───────────────────────────────────────
;; NOTE: ds_exists can false-positive — a plain number may
;; coincide with a valid ds_map/ds_list ID.  These are
;; "speculative" predicates useful for REPL introspection,
;; not for production control flow.

(define (ds-map? n)
  (and (number? n) (gml:ds-exists n (gml:ds-type-map))))

(define (ds-list? n)
  (and (number? n) (gml:ds-exists n (gml:ds-type-list))))

;; ── Pretty Printer (pp) ──────────────────────────────────────
;; Three-layer architecture:
;;   pp-*   : typed pretty printers (user-facing, 1 arg)
;;   pp     : generic dispatcher (no probing, works on Scheme types)
;;   probe  : top-level entry — detects GML type for ambiguous real values
;;
;; Features:
;;   • Keys sorted alphabetically (struct, instance, ds_map)
;;   • Value column aligned for key-value structures
;;   • Depth limiting (*pp-max-depth*) — prevents stack overflow
;;   • Item truncation (*pp-max-items*) — keeps output manageable
;;   • Index column right-alignment for arrays/lists
;;   • Cycle detection: #<circular>

(define *pp-width* 80)
(define *pp-max-depth* 8)
(define *pp-max-items* 9999)

;; ── Internal helpers ──

(define (pp--spaces n)
  (let loop ((i 0))
    (if (< i n)
      (begin (display " ") (loop (+ i 1))))))

(define (pp--visited? obj visited)
  (cond
    ((null? visited) #f)
    ((eq? obj (car visited)) #t)
    (else (pp--visited? obj (cdr visited)))))

(define (pp--scalar? x)
  (not (or (struct? x) (array? x) (pair? x))))

(define (pp--write-width x)
  (cond
    ((boolean? x) 2)
    ((null? x) 2)
    ((number? x) 8)
    ((string? x) (+ 2 (gml:string-length x)))
    (else 10)))

;; Check if a proper list of all-scalar elements fits inline.
(define (pp--list-inline? lst indent)
  (let check ((l lst) (n 0) (w 1))
    (cond
      ((and (pair? l) (< n 8) (pp--scalar? (car l)))
       (check (cdr l) (+ n 1) (+ w (pp--write-width (car l)) 1)))
      ((null? l)
       (<= (+ indent w) *pp-width*))
      (else #f))))

;; Max string-length in a GML array of strings.
(define (pp--max-width-arr keys n)
  (let loop ((i 0) (w 0))
    (if (= i n) w
      (loop (+ i 1) (max w (string-length (gml:array-get keys i)))))))

;; Max string-length in a Scheme list of strings.
(define (pp--max-width-lst keys)
  (foldl (lambda (k w) (max (string-length k) w)) 0 keys))

;; Width of an integer when printed (for index alignment).
(define (pp--int-width n)
  (string-length (number->string n)))

;; ── Internal recursive printers ──
;; Convention: print value at current cursor, NO trailing newline.
;; Compound types print header, then each child on a new indented line.
;; depth tracks recursion level for *pp-max-depth* limiting.

(define (pp--struct obj indent visited depth)
  (if (pp--visited? obj visited)
    (display "#<circular>")
    (let* ((vis (cons obj visited))
           (keys (gml:variable-struct-get-names obj))
           (n (gml:array-length keys)))
      (gml:array-sort keys #t)
      (let* ((col-w (pp--max-width-arr keys n))
             (limit (min n *pp-max-items*)))
        (display "{struct ") (display n) (display " fields}")
        (let loop ((i 0))
          (if (< i limit)
            (let ((k (gml:array-get keys i))
                  (ind (+ indent 2)))
              (newline) (pp--spaces ind)
              (display k) (display ":")
              (pp--spaces (+ 1 (- col-w (string-length k))))
              (pp--internal (gml:variable-struct-get obj k) ind vis (+ depth 1))
              (loop (+ i 1)))))
        (if (< limit n)
          (begin (newline) (pp--spaces (+ indent 2))
                 (display "... (") (display (- n limit)) (display " more)")))))))

(define (pp--array obj indent visited depth)
  (if (pp--visited? obj visited)
    (display "#<circular>")
    (let* ((vis (cons obj visited))
           (n (gml:array-length obj))
           (limit (min n *pp-max-items*))
           (idx-w (if (> n 0) (pp--int-width (- n 1)) 1)))
      (display "{array ") (display n) (display "}")
      (let loop ((i 0))
        (if (< i limit)
          (let ((ind (+ indent 2))
                (is (number->string i)))
            (newline) (pp--spaces ind)
            (display "[") (pp--spaces (- idx-w (string-length is)))
            (display is) (display "] ")
            (pp--internal (gml:array-get obj i) ind vis (+ depth 1))
            (loop (+ i 1)))))
      (if (< limit n)
        (begin (newline) (pp--spaces (+ indent 2))
               (display "... (") (display (- n limit)) (display " more)"))))))

(define (pp--instance id indent visited depth)
  (let* ((obj-name (gml:object-get-name
                     (gml:variable-instance-get id "object_index")))
         (keys (gml:variable-instance-get-names id))
         (n (gml:array-length keys)))
    (gml:array-sort keys #t)
    (let* ((col-w (pp--max-width-arr keys n))
           (limit (min n *pp-max-items*)))
      (display "{instance ") (display obj-name)
      (display " #") (display id) (display "}")
      (let loop ((i 0))
        (if (< i limit)
          (let ((k (gml:array-get keys i))
                (ind (+ indent 2)))
            (newline) (pp--spaces ind)
            (display k) (display ":")
            (pp--spaces (+ 1 (- col-w (string-length k))))
            (pp--internal (gml:variable-instance-get id k) ind visited (+ depth 1))
            (loop (+ i 1)))))
      (if (< limit n)
        (begin (newline) (pp--spaces (+ indent 2))
               (display "... (") (display (- n limit)) (display " more)"))))))

(define (pp--ds-map m indent visited depth)
  (let* ((keys (sort (ds-map-keys m) string<?))
         (n (length keys))
         (col-w (pp--max-width-lst keys))
         (limit (min n *pp-max-items*)))
    (display "{ds_map ") (display n) (display " entries}")
    (let loop ((ks keys) (i 0))
      (if (and (pair? ks) (< i limit))
        (let ((k (car ks))
              (ind (+ indent 2)))
          (newline) (pp--spaces ind)
          (display k) (display ":")
          (pp--spaces (+ 1 (- col-w (string-length k))))
          (pp--internal (gml:ds-map-find-value m k) ind visited (+ depth 1))
          (loop (cdr ks) (+ i 1)))))
    (if (< limit n)
      (begin (newline) (pp--spaces (+ indent 2))
             (display "... (") (display (- n limit)) (display " more)")))))

(define (pp--ds-list l indent visited depth)
  (let* ((n (gml:ds-list-size l))
         (limit (min n *pp-max-items*))
         (idx-w (if (> n 0) (pp--int-width (- n 1)) 1)))
    (display "{ds_list ") (display n) (display "}")
    (let loop ((i 0))
      (if (< i limit)
        (let ((ind (+ indent 2))
              (is (number->string i)))
          (newline) (pp--spaces ind)
          (display "[") (pp--spaces (- idx-w (string-length is)))
          (display is) (display "] ")
          (pp--internal (gml:ds-list-find-value l i) ind visited (+ depth 1))
          (loop (+ i 1)))))
    (if (< limit n)
      (begin (newline) (pp--spaces (+ indent 2))
             (display "... (") (display (- n limit)) (display " more)")))))

(define (pp--list obj indent visited depth)
  (if (pp--list-inline? obj indent)
    (write obj)
    (let* ((n (let cnt ((l obj) (c 0))
               (if (pair? l) (cnt (cdr l) (+ c 1)) c)))
           (limit (min n *pp-max-items*))
           (idx-w (if (> n 0) (pp--int-width (- n 1)) 1)))
      (display "{list ") (display n) (display "}")
      (let loop ((l obj) (i 0))
        (cond
          ((null? l))
          ((and (pair? l) (< i limit))
           (let ((ind (+ indent 2))
                 (is (number->string i)))
             (newline) (pp--spaces ind)
             (display "[") (pp--spaces (- idx-w (string-length is)))
             (display is) (display "] ")
             (pp--internal (car l) ind visited (+ depth 1))
             (loop (cdr l) (+ i 1))))
          ((pair? l)
           (newline) (pp--spaces (+ indent 2))
           (display "... (") (display (- n limit)) (display " more)"))
          (else
           (let ((ind (+ indent 2)))
             (newline) (pp--spaces ind)
             (display ". ")
             (pp--internal l ind visited (+ depth 1)))))))))

(define (pp--internal obj indent visited depth)
  (cond
    ((> depth *pp-max-depth*)
     (display "{...}"))
    ((struct? obj) (pp--struct obj indent visited depth))
    ((array? obj)  (pp--array obj indent visited depth))
    ((pair? obj)   (pp--list obj indent visited depth))
    (else (write obj))))

;; ── Asset printers ──
;; These print detailed info about GML asset indices.
;; Convention: print at current cursor, NO trailing newline.

(define (pp--object idx indent)
  (let* ((name    (gml:object-get-name idx))
         (spr-idx (gml:object-get-sprite idx))
         (par-idx (gml:object-get-parent idx))
         (depth   (gml:object-get-depth idx))
         (mask-idx (gml:object-get-mask idx))
         (persist (gml:object-get-persistent idx))
         (vis     (gml:object-get-visible idx))
         (solid   (gml:object-get-solid idx))
         (n-inst  (gml:instance-number idx)))
    (display "{object \"") (display name)
    (display "\" #") (display idx) (display "}")
    ;; sprite
    (newline) (pp--spaces (+ indent 2))
    (display "sprite:      ")
    (if (>= spr-idx 0)
      (let ((sn (gml:sprite-get-name spr-idx)))
        (display sn)
        (display " (") (display (gml:sprite-get-width spr-idx))
        (display "\u00d7") (display (gml:sprite-get-height spr-idx))
        (display ", ") (display (gml:sprite-get-number spr-idx))
        (display " frames)"))
      (display "<none>"))
    ;; parent
    (newline) (pp--spaces (+ indent 2))
    (display "parent:      ")
    (if (>= par-idx 0)
      (display (gml:object-get-name par-idx))
      (display "<none>"))
    ;; depth
    (newline) (pp--spaces (+ indent 2))
    (display "depth:       ") (display depth)
    ;; mask
    (newline) (pp--spaces (+ indent 2))
    (display "mask:        ")
    (cond
      ((< mask-idx 0) (display "<same as sprite>"))
      ((and (>= spr-idx 0) (= mask-idx spr-idx))
       (display "<same as sprite>"))
      ((gml:sprite-exists mask-idx)
       (display (gml:sprite-get-name mask-idx)))
      (else (display mask-idx)))
    ;; flags (only show non-default)
    (newline) (pp--spaces (+ indent 2))
    (display "persistent:  ") (write persist)
    (if (not vis)
      (begin (newline) (pp--spaces (+ indent 2))
             (display "visible:     #f")))
    (if solid
      (begin (newline) (pp--spaces (+ indent 2))
             (display "solid:       #t")))
    ;; live instance count
    (newline) (pp--spaces (+ indent 2))
    (display "instances:   ") (display n-inst)))

(define (pp--sprite idx indent)
  (let* ((name (gml:sprite-get-name idx))
         (w  (gml:sprite-get-width idx))
         (h  (gml:sprite-get-height idx))
         (n  (gml:sprite-get-number idx))
         (ox (gml:sprite-get-xoffset idx))
         (oy (gml:sprite-get-yoffset idx))
         (bl (gml:sprite-get-bbox-left idx))
         (bt (gml:sprite-get-bbox-top idx))
         (br (gml:sprite-get-bbox-right idx))
         (bb (gml:sprite-get-bbox-bottom idx)))
    (display "{sprite \"") (display name)
    (display "\" #") (display idx) (display "}")
    (newline) (pp--spaces (+ indent 2))
    (display "size:    ") (display w) (display " \u00d7 ") (display h)
    (newline) (pp--spaces (+ indent 2))
    (display "frames:  ") (display n)
    (newline) (pp--spaces (+ indent 2))
    (display "origin:  (") (display ox) (display ", ") (display oy) (display ")")
    (newline) (pp--spaces (+ indent 2))
    (display "bbox:    (") (display bl) (display ", ") (display bt)
    (display ") - (") (display br) (display ", ") (display bb) (display ")")))

(define (pp--room idx indent)
  (display "{room \"") (display (gml:room-get-name idx))
  (display "\" #") (display idx) (display "}"))

(define (pp--script idx indent)
  (display "{script \"") (display (gml:script-get-name idx))
  (display "\" #") (display idx) (display "}"))

(define (pp--sound idx indent)
  (display "{sound \"") (display (gml:audio-get-name idx))
  (display "\" #") (display idx) (display "}"))

;; ── Public API ──

;; (pp obj) — generic pretty printer (no probing for GML handles)
(define (pp obj)
  (pp--internal obj 0 '() 0)
  (newline))

;; Typed pretty printers (user knows the type)
(define (pp-struct obj)
  (pp--struct obj 0 '() 0) (newline))

(define (pp-array obj)
  (pp--array obj 0 '() 0) (newline))

(define (pp-instance id)
  (if (not (gml:instance-exists id))
    (error "pp-instance: instance does not exist")
    (begin (pp--instance id 0 '() 0) (newline))))

(define (pp-ds-map m)
  (if (not (gml:ds-exists m (gml:ds-type-map)))
    (error "pp-ds-map: not a valid ds_map")
    (begin (pp--ds-map m 0 '() 0) (newline))))

(define (pp-ds-list l)
  (if (not (gml:ds-exists l (gml:ds-type-list)))
    (error "pp-ds-list: not a valid ds_list")
    (begin (pp--ds-list l 0 '() 0) (newline))))

;; (pp-object idx) — print object asset info
(define (pp-object idx)
  (if (not (gml:object-exists idx))
    (error "pp-object: not a valid object index")
    (begin (pp--object idx 0) (newline))))

;; (pp-sprite idx) — print sprite asset info
(define (pp-sprite idx)
  (if (not (gml:sprite-exists idx))
    (error "pp-sprite: not a valid sprite index")
    (begin (pp--sprite idx 0) (newline))))

;; (pp-room idx) — print room asset info
(define (pp-room idx)
  (if (not (gml:room-exists idx))
    (error "pp-room: not a valid room index")
    (begin (pp--room idx 0) (newline))))

;; (pp-script idx) — print script asset info
(define (pp-script idx)
  (if (not (gml:script-exists idx))
    (error "pp-script: not a valid script index")
    (begin (pp--script idx 0) (newline))))

;; (pp-sound idx) — print sound asset info
(define (pp-sound idx)
  (if (not (gml:audio-exists idx))
    (error "pp-sound: not a valid sound index")
    (begin (pp--sound idx 0) (newline))))

;; (probe obj) — top-level entry with GML type detection for ambiguous reals
;; Detects: struct, array, list, instance, ds_map, ds_list,
;;          object/sprite/room/script/sound asset indices, string.
(define (probe obj)
  (cond
    ((struct? obj) (pp--struct obj 0 '() 0) (newline))
    ((array? obj)  (pp--array obj 0 '() 0) (newline))
    ((pair? obj)   (pp--list obj 0 '() 0) (newline))
    ((number? obj)
     (let* ((int?    (= obj (gml:floor obj)))
            (nnint?  (and int? (>= obj 0)))
            ;; Runtime handles
            (is-map  (gml:ds-exists obj (gml:ds-type-map)))
            (is-list (gml:ds-exists obj (gml:ds-type-list)))
            (is-inst (and (>= obj 100000) int?
                          (gml:instance-exists obj)))
            ;; Asset indices (non-negative integers)
            (is-obj  (and nnint? (gml:object-exists obj)))
            (is-spr  (and nnint? (gml:sprite-exists obj)))
            (is-room (and nnint? (gml:room-exists obj)))
            (is-scr  (and nnint? (gml:script-exists obj)))
            (is-snd  (and nnint? (gml:audio-exists obj)))
            (hits (+ (if is-map 1 0) (if is-list 1 0) (if is-inst 1 0)
                     (if is-obj 1 0) (if is-spr 1 0) (if is-room 1 0)
                     (if is-scr 1 0) (if is-snd 1 0))))
       (cond
         ((= hits 0) (write obj) (newline))
         (else
          (display "=> ") (write obj) (newline)
          (if (> hits 1)
            (display "warning: ambiguous handle — showing all matches:\n"))
          (if is-inst
            (begin (pp--instance obj 0 '() 0) (newline)))
          (if is-map
            (begin (pp--ds-map obj 0 '() 0) (newline)))
          (if is-list
            (begin (pp--ds-list obj 0 '() 0) (newline)))
          (if is-obj
            (begin (pp--object obj 0) (newline)))
          (if is-spr
            (begin (pp--sprite obj 0) (newline)))
          (if is-room
            (begin (pp--room obj 0) (newline)))
          (if is-scr
            (begin (pp--script obj 0) (newline)))
          (if is-snd
            (begin (pp--sound obj 0) (newline)))))))
    ((string? obj)
     (display "{string length=") (display (gml:string-length obj))
     (display "} ") (write obj) (newline))
    (else
     (write obj) (newline))))

; ── DS constructors ──────────────────────────────────────────

;; (alist->ds-map alist) → new ds_map (caller must destroy!)
(define (alist->ds-map alist)
  (let ((m (gml:ds-map-create)))
    (for-each (lambda (p) (gml:ds-map-set m (car p) (cdr p))) alist)
    m))

;; (list->ds-list lst) → new ds_list (caller must destroy!)
(define (list->ds-list lst)
  (let ((l (gml:ds-list-create)))
    (for-each (lambda (x) (gml:ds-list-add l x)) lst)
    l))

; ── GML short aliases ────────────────────────────────────────
; Ergonomic names for the most frequently used gml: builtins.

; Instance variable/existence access
(define instance-get     gml:variable-instance-get)
(define instance-set!    gml:variable-instance-set)
(define instance-exists? gml:instance-exists)
(define (instance-keys id)
  (array->list (gml:variable-instance-get-names id)))

; Global variable access
(define global-get  gml:variable-global-get)
(define global-set! gml:variable-global-set)

; Struct access
(define struct-get    gml:variable-struct-get)
(define struct-set!   gml:variable-struct-set)
(define struct-has?   gml:variable-struct-exists)

; ds_map / ds_list — NO short aliases.
; These require manual gml:ds-map-destroy / gml:ds-list-destroy.
; The verbose gml: prefix is intentional friction.

; Array convenience
(define array-ref     gml:array-get)
(define array-set!    gml:array-set)
(define array-length  gml:array-length)
(define array-create  gml:array-create)

; Object info
(define object-exists?      gml:object-exists)
(define object-get-name     gml:object-get-name)
(define object-get-sprite   gml:object-get-sprite)
(define object-get-depth    gml:object-get-depth)
(define object-get-mask     gml:object-get-mask)

; Sprite info
(define sprite-exists?      gml:sprite-exists)
(define sprite-get-name     gml:sprite-get-name)
(define sprite-get-width    gml:sprite-get-width)
(define sprite-get-height   gml:sprite-get-height)
(define sprite-get-number   gml:sprite-get-number)

; Room info
(define room-exists?        gml:room-exists)
(define room-get-name       gml:room-get-name)

; Script info
(define script-exists?      gml:script-exists)
(define script-get-name     gml:script-get-name)

; Sound info
(define sound-exists?       gml:audio-exists)
(define sound-get-name      gml:audio-get-name)

; ── Asset discovery ──────────────────────────────────────────
; search-* captures the GML array handle at load time (let-over-lambda).
; Tab completion reads these globals directly from GML side.

;; (search-names arr pattern) → list of matching strings
;; Internal helper — not intended for direct REPL use.
(define (search-names arr pat)
  (let ((n (array-length arr))
        (p (gml:string-lower pat)))
    (let loop ((i 0) (acc '()))
      (if (= i n) (reverse acc)
        (let ((name (array-ref arr i)))
          (if (> (gml:string-pos p (gml:string-lower name)) 0)
            (loop (+ i 1) (cons name acc))
            (loop (+ i 1) acc)))))))

;; Search by category (let-over-lambda: load JSON once, capture in closure)
(define search-objects
  (let ((arr (gml:json-parse (file->string "scm_data/objects.json"))))
    (lambda (pat) (search-names arr pat))))
(define search-sprites
  (let ((arr (gml:json-parse (file->string "scm_data/sprites.json"))))
    (lambda (pat) (search-names arr pat))))
(define search-sounds
  (let ((arr (gml:json-parse (file->string "scm_data/sounds.json"))))
    (lambda (pat) (search-names arr pat))))
(define search-rooms
  (let ((arr (gml:json-parse (file->string "scm_data/rooms.json"))))
    (lambda (pat) (search-names arr pat))))
(define search-scripts
  (let ((arr (gml:json-parse (file->string "scm_data/scripts.json"))))
    (lambda (pat) (search-names arr pat))))
(define search-functions
  (let ((arr (gml:json-parse (file->string "scm_data/functions.json"))))
    (lambda (pat) (search-names arr pat))))

;; (object-children name) → list of child names (static struct tree)
(define object-children
  (let ((tree (gml:json-parse (file->string "scm_data/obj_tree.json"))))
    (lambda (name)
      (if (gml:variable-struct-exists tree name)
        (array->list (gml:variable-struct-get tree name))
        '()))))

;; (object-parent name-or-idx) → parent name or #f (runtime GML)
(define (object-parent name-or-idx)
  (let* ((idx (if (string? name-or-idx)
                  (gml:asset-get-index name-or-idx) name-or-idx))
         (p (gml:object-get-parent idx)))
    (if (< p 0) #f (gml:object-get-name p))))

;; (object-ancestors name-or-idx) → ancestor names list (nearest → root)
(define (object-ancestors name-or-idx)
  (let ((idx (if (string? name-or-idx)
                 (gml:asset-get-index name-or-idx) name-or-idx)))
    (let loop ((i (gml:object-get-parent idx)) (acc '()))
      (if (< i 0) (reverse acc)
        (loop (gml:object-get-parent i)
              (cons (gml:object-get-name i) acc))))))

; ── Logging ──────────────────────────────────────────────────
;; (log arg ...) — write to GML debug console via current-error-port.
;; Output: "[scm] <arg1><arg2>..." followed by newline.
(define (log . args)
  (let ((p (current-error-port)))
    (display "[scm] " p)
    (for-each (lambda (x) (display x p)) args)
    (newline p)))

; ── Instance iteration ───────────────────────────────────────

;; (instances-of obj) → list of instance IDs for an object.
;; obj can be a string name ("o_enemy") or a numeric object index.
(define (instances-of obj)
  (let* ((idx (if (string? obj) (gml:asset-get-index obj) obj))
         (n   (gml:instance-number idx)))
    (let loop ((i (- n 1)) (acc '()))
      (if (< i 0) acc
        (loop (- i 1) (cons (gml:instance-find idx i) acc))))))

; ── FP helpers ───────────────────────────────────────────────

;; (partial f arg ...) → a procedure that pre-applies args.
;; (partial + 1) => (lambda rest (apply + 1 rest))
(define (partial f . args)
  (lambda rest (apply f (append args rest))))

;; (complement pred) → a procedure that negates pred.
;; (complement odd?) => (lambda args (not (apply odd? args)))
(define (complement pred)
  (lambda args (not (apply pred args))))

;; (tap f x) → call (f x) for side effect, return x unchanged.
;; Useful in threading pipelines: (-> val (tap print) (+ 1))
(define (tap f x) (f x) x)

; ── Threading macros ─────────────────────────────────────────
; Clojure-style threading (requires define-macro).

;; (-> x form ...) — thread first
;; Inserts x as the FIRST argument of each form.
;; (-> a (f 1) (g 2)) => (g (f a 1) 2)
(define-macro (-> x . rest)
  (if (null? rest) x
    (let ((step (car rest))
          (more (cdr rest)))
      (if (pair? step)
        `(-> (,(car step) ,x ,@(cdr step)) ,@more)
        `(-> (,step ,x) ,@more)))))

;; (->> x form ...) — thread last
;; Inserts x as the LAST argument of each form.
;; (->> a (f 1) (g 2)) => (g 2 (f 1 a))
(define-macro (->> x . rest)
  (if (null? rest) x
    (let ((step (car rest))
          (more (cdr rest)))
      (if (pair? step)
        `(->> (,@step ,x) ,@more)
        `(->> (,step ,x) ,@more)))))

;; (as-> expr name form ...) — thread with named placeholder
;; Binds expr to name, evaluates first form, rebinds result to name, repeat.
;; (as-> 5 x (+ x 3) (* 2 x) (- 100 x)) => 84
(define-macro (as-> expr name . steps)
  (if (null? steps) expr
    `(let ((,name ,expr))
       (as-> ,(car steps) ,name ,@(cdr steps)))))

;; (some-> x form ...) — thread first, short-circuit on noone (-4).
;; Like -> but stops and returns noone if any intermediate result is noone.
(define-macro (some-> x . rest)
  (if (null? rest) x
    (let ((step (car rest))
          (more (cdr rest))
          (tmp  (gensym)))
      `(let ((,tmp ,x))
         (if (= ,tmp noone) noone
           (some-> ,(if (pair? step)
                     `(,(car step) ,tmp ,@(cdr step))
                     `(,step ,tmp))
                   ,@more))))))

;; (some->> x form ...) — thread last, short-circuit on noone (-4).
;; Like ->> but stops and returns noone if any intermediate result is noone.
(define-macro (some->> x . rest)
  (if (null? rest) x
    (let ((step (car rest))
          (more (cdr rest))
          (tmp  (gensym)))
      `(let ((,tmp ,x))
         (if (= ,tmp noone) noone
           (some->> ,(if (pair? step)
                      `(,@step ,tmp)
                      `(,step ,tmp))
                    ,@more))))))
