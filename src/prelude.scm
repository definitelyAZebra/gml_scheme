; ═══════════════════════════════════════════════════════════════
;  prelude.scm — Standard library
;
;  Loaded after scm_register_core, scm_register_gml_builtins,
;  and scm_register_bridge. Everything here is pure Scheme built
;  on those primitives.
;
;  Design principles:
;    • Tail-recursive where possible (GML stack ~256 frames)
;    • R5RS-compatible names; GML specifics use gml: prefix
;    • Avoid redefining core builtins (see scm_core.gml)
; ═══════════════════════════════════════════════════════════════

; ── Scheme-standard math (bare aliases for gml: wrappers) ────
; These are NOT in scm_core, so the prelude provides them.
(define abs     gml:abs)
(define floor   gml:floor)
(define ceiling gml:ceil)
(define round   gml:round)
(define sqrt    gml:sqrt)
(define expt    gml:power)
(define sign    gml:sign)
(define clamp   gml:clamp)
(define sin     gml:sin)
(define cos     gml:cos)
(define random  gml:random)
(define irandom gml:irandom)

;; (lerp a b t) → linear interpolation between a and b
(define (lerp a b t) (+ a (* t (- b a))))

; ── List accessors (ca/cd combinations) ──────────────────────
(define (cadr x)  (car (cdr x)))
(define (caar x)  (car (car x)))
(define (cdar x)  (cdr (car x)))
(define (cddr x)  (cdr (cdr x)))
(define (cadar x) (car (cdr (car x))))
(define (caddr x) (car (cdr (cdr x))))
(define (cdddr x) (cdr (cdr (cdr x))))

; ── Higher-order functions (all tail-recursive) ──────────────

(define (map f lst)
  (let loop ((l lst) (acc '()))
    (if (null? l) (reverse acc)
      (loop (cdr l) (cons (f (car l)) acc)))))

(define (filter pred lst)
  (let loop ((l lst) (acc '()))
    (if (null? l) (reverse acc)
      (if (pred (car l))
        (loop (cdr l) (cons (car l) acc))
        (loop (cdr l) acc)))))

;; (remove pred lst) — complement of filter
(define (remove pred lst)
  (filter (lambda (x) (not (pred x))) lst))

(define (for-each f lst)
  (let loop ((l lst))
    (when (pair? l)
      (f (car l))
      (loop (cdr l)))))

;; (foldl f init lst) — left fold (tail-recursive)
;; f signature: (f element accumulator) → accumulator
(define (foldl f init lst)
  (let loop ((acc init) (l lst))
    (if (null? l) acc
      (loop (f (car l) acc) (cdr l)))))

;; foldr is NOT tail-recursive — use only on short lists.
(define (foldr f init lst)
  (if (null? lst) init
    (f (car lst) (foldr f init (cdr lst)))))

;; (append-map f lst) — map then concatenate results
;; Uses foldr for O(n) total append cost. NOT tail-recursive —
;; safe for typical code-gen clause lists (< 50 elements).
(define (append-map f lst)
  (foldr (lambda (x acc) (append (f x) acc)) '() lst))

; ── Search & membership (tail-recursive) ─────────────────────

(define (assoc key lst)
  (let loop ((l lst))
    (cond
      ((null? l) #f)
      ((equal? key (caar l)) (car l))
      (else (loop (cdr l))))))

(define (member x lst)
  (let loop ((l lst))
    (cond
      ((null? l) #f)
      ((equal? x (car l)) l)
      (else (loop (cdr l))))))

(define (find pred lst)
  (let loop ((l lst))
    (cond
      ((null? l) #f)
      ((pred (car l)) (car l))
      (else (loop (cdr l))))))

; ── Numeric predicates ───────────────────────────────────────

(define (positive? x) (> x 0))
(define (negative? x) (< x 0))
(define (even? x) (= (modulo x 2) 0))
(define (odd? x)  (not (even? x)))
(define (integer? x) (and (number? x) (= x (floor x))))

; ── List builders (tail-recursive) ───────────────────────────

;; (range start end) → (start start+1 ... end-1)
(define (range start end)
  (let loop ((i (- end 1)) (acc '()))
    (if (< i start) acc
      (loop (- i 1) (cons i acc)))))

;; (iota n) → (0 1 ... n-1)
(define (iota n) (range 0 n))

(define (make-list n val)
  (let loop ((i n) (acc '()))
    (if (<= i 0) acc
      (loop (- i 1) (cons val acc)))))

; ── List operations ──────────────────────────────────────────

;; (last lst) → last element (error on empty)
(define (last lst)
  (if (null? lst) (error "last: empty list")
    (if (null? (cdr lst)) (car lst)
      (last (cdr lst)))))

;; (take lst n) → first n elements
(define (take lst n)
  (let loop ((l lst) (i n) (acc '()))
    (if (or (<= i 0) (null? l)) (reverse acc)
      (loop (cdr l) (- i 1) (cons (car l) acc)))))

;; (drop lst n) → list without first n elements
(define (drop lst n)
  (let loop ((l lst) (i n))
    (if (or (<= i 0) (null? l)) l
      (loop (cdr l) (- i 1)))))

;; (zip lst1 lst2) → ((a1 b1) (a2 b2) ...)
(define (zip a b)
  (let loop ((a a) (b b) (acc '()))
    (if (or (null? a) (null? b)) (reverse acc)
      (loop (cdr a) (cdr b) (cons (list (car a) (car b)) acc)))))

;; (partition pred lst) → (matching . non-matching)
;; Single-pass split (tail-recursive)
(define (partition pred lst)
  (let loop ((l lst) (yes '()) (no '()))
    (cond
      ((null? l) (cons (reverse yes) (reverse no)))
      ((pred (car l)) (loop (cdr l) (cons (car l) yes) no))
      (else (loop (cdr l) yes (cons (car l) no))))))

;; (count pred lst) → number of elements satisfying pred
(define (count pred lst)
  (let loop ((l lst) (n 0))
    (cond
      ((null? l) n)
      ((pred (car l)) (loop (cdr l) (+ n 1)))
      (else (loop (cdr l) n)))))

;; (flatten lst) → flat list from nested structure
;; NOT tail-recursive — use only on shallow nesting.
(define (flatten lst)
  (cond
    ((null? lst) '())
    ((pair? (car lst)) (append (flatten (car lst)) (flatten (cdr lst))))
    (else (cons (car lst) (flatten (cdr lst))))))

; ── Predicate combinators (tail-recursive) ───────────────────

;; (any pred lst) → #t if pred holds for some element
(define (any pred lst)
  (let loop ((l lst))
    (cond
      ((null? l) #f)
      ((pred (car l)) #t)
      (else (loop (cdr l))))))

;; (every pred lst) → #t if pred holds for all elements
(define (every pred lst)
  (let loop ((l lst))
    (cond
      ((null? l) #t)
      ((pred (car l)) (loop (cdr l)))
      (else #f))))

; ── Function combinators ─────────────────────────────────────

(define (compose f g)
  (lambda (x) (f (g x))))

(define (identity x) x)

(define (const x)
  (lambda args x))

(define (flip f)
  (lambda (a b) (f b a)))

; ── String helpers ───────────────────────────────────────────

(define (string-empty? s) (= (string-length s) 0))

;; (string-join lst sep) → "a,b,c"
(define (string-join lst sep)
  (if (null? lst) ""
    (let loop ((l (cdr lst)) (acc (car lst)))
      (if (null? l) acc
        (loop (cdr l) (string-append acc sep (car l)))))))

; ── Association list helpers ─────────────────────────────────

;; (alist-ref key alist default) → value or default
(define (alist-ref key alist default)
  (let ((pair (assoc key alist)))
    (if pair (cdr pair) default)))

;; (alist-set key value alist) → new alist with key updated/added
(define (alist-set key value alist)
  (cons (cons key value)
        (filter (lambda (p) (not (equal? key (car p)))) alist)))

; ── GML bridge helpers ───────────────────────────────────────
; Built on gml: builtins. scm_wrap(undefined) → nil terminates
; ds_map iteration.

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
