; =================================================================
;  scm_repl.scm -- Self-hosted Scheme REPL (v2)
;
;  The GML shell provides ONLY:
;    - Event entry points (scm_repl_create / step / draw / destroy)
;    - Eval dispatch (scm_eval_program + output capture + feed back)
;    - String quoting (for GML->Scheme string passing)
;  Everything else is bootstrapped here via FFI builtins.
;
;  GML entry points:
;    (repl:init!)             -> initialize all state + colors
;    (repl:step!)             -> full keyboard handling, returns eval code or #f
;    (repl:draw!)             -> full GUI rendering
;    (repl:feed-eval-result! text sym)  -> feed eval result
;    (repl:feed-eval-output! text)      -> feed printed output line
; =================================================================

; -- Utilities -----------------------------------------------------

(define (list-ref lst idx)
  (if (= idx 0) (car lst)
    (list-ref (cdr lst) (- idx 1))))

; -- Character predicates ------------------------------------------

(define (repl:delimiter? ch)
  (or (string-empty? ch)
      (char-whitespace? ch)
      (equal? ch "(") (equal? ch ")")
      (equal? ch "\"") (equal? ch ";")
      (equal? ch "'") (equal? ch "`") (equal? ch ",")))

; -- Keyword & builtin tables --------------------------------------

(define repl:keywords
  '("define" "lambda" "if" "cond" "case" "when" "unless"
    "let" "let*" "letrec" "begin" "do" "set!"
    "and" "or" "quote" "quasiquote" "unquote" "unquote-splicing"
    "define-syntax" "syntax-rules"))

(define repl:builtins
  '("car" "cdr" "cons" "list" "null?" "pair?" "map" "filter"
    "foldl" "foldr" "for-each" "append" "reverse" "length"
    "apply" "not" "equal?" "eqv?" "eq?" "number?" "string?"
    "symbol?" "boolean?" "list?" "zero?" "positive?" "negative?"
    "display" "write" "print" "newline" "error"
    "+" "-" "*" "/" "=" "<" ">" "<=" ">=" "modulo"
    "abs" "min" "max" "floor" "ceiling" "round" "sqrt" "expt"
    "string-length" "string-ref" "string-append" "substring"
    "string-contains?" "string-split" "string-join"
    "string->number" "number->string"
    "assoc" "member" "find" "any" "every" "remove" "count"
    "take" "drop" "range" "iota" "make-list" "zip" "partition"))

(define (repl:keyword? s) (if (member s repl:keywords) #t #f))
(define (repl:builtin? s) (if (member s repl:builtins) #t #f))

; -- Tokenizer -----------------------------------------------------
; Returns list of (type . text) pairs.

(define (repl:tokenize src)
  (let ((len (string-length src)))
    (let loop ((pos 0) (tokens '()))
      (if (>= pos len)
        (reverse tokens)
        (let ((ch (string-ref src pos)))
          (cond
            ; Whitespace run
            ((char-whitespace? ch)
             (let ws-loop ((end (+ pos 1)))
               (if (and (< end len) (char-whitespace? (string-ref src end)))
                 (ws-loop (+ end 1))
                 (loop end (cons (cons 'whitespace (substring src pos end))
                                 tokens)))))

            ; Comment: ; to end of line
            ((equal? ch ";")
             (let cmt-loop ((end (+ pos 1)))
               (if (or (>= end len)
                       (equal? (string-ref src end) "\n"))
                 (loop end (cons (cons 'comment (substring src pos end))
                                 tokens))
                 (cmt-loop (+ end 1)))))

            ; String literal
            ((equal? ch "\"")
             (let str-loop ((end (+ pos 1)) (escaped #f))
               (cond
                 ((>= end len)
                  (loop end (cons (cons 'string (substring src pos end))
                                  tokens)))
                 (escaped
                  (str-loop (+ end 1) #f))
                 ((equal? (string-ref src end) "\\")
                  (str-loop (+ end 1) #t))
                 ((equal? (string-ref src end) "\"")
                  (let ((end+1 (+ end 1)))
                    (loop end+1 (cons (cons 'string (substring src pos end+1))
                                      tokens))))
                 (else
                  (str-loop (+ end 1) #f)))))

            ; Parens
            ((equal? ch "(")
             (loop (+ pos 1) (cons (cons 'lparen "(") tokens)))
            ((equal? ch ")")
             (loop (+ pos 1) (cons (cons 'rparen ")") tokens)))

            ; Quote sugar
            ((equal? ch "'")
             (loop (+ pos 1) (cons (cons 'quote-sugar "'") tokens)))
            ((equal? ch "`")
             (loop (+ pos 1) (cons (cons 'quote-sugar "`") tokens)))
            ((equal? ch ",")
             (if (and (< (+ pos 1) len) (equal? (string-ref src (+ pos 1)) "@"))
               (loop (+ pos 2) (cons (cons 'quote-sugar ",@") tokens))
               (loop (+ pos 1) (cons (cons 'quote-sugar ",") tokens))))

            ; Hash literals
            ((equal? ch "#")
             (if (< (+ pos 1) len)
               (let ((next (string-ref src (+ pos 1))))
                 (if (or (equal? next "t") (equal? next "f"))
                   (loop (+ pos 2) (cons (cons 'boolean
                                                (string-append "#" next))
                                         tokens))
                   (loop (+ pos 1) (cons (cons 'symbol "#") tokens))))
               (loop (+ pos 1) (cons (cons 'symbol "#") tokens))))

            ; Atom (number or symbol/keyword/builtin)
            (else
             (let atom-loop ((end (+ pos 1)))
               (if (or (>= end len) (repl:delimiter? (string-ref src end)))
                 (let ((text (substring src pos end)))
                   (let ((type (cond
                                 ((repl:number-string? text) 'number)
                                 ((repl:keyword? text)       'keyword)
                                 ((repl:builtin? text)       'builtin)
                                 (else                       'symbol))))
                     (loop end (cons (cons type text) tokens))))
                 (atom-loop (+ end 1)))))))))))

; -- Number detection ----------------------------------------------

(define (repl:number-string? s)
  (let ((len (string-length s)))
    (if (= len 0) #f
      (let* ((ch0 (string-ref s 0))
             (start (if (or (equal? ch0 "+") (equal? ch0 "-")) 1 0)))
        (if (and (> start 0) (= len 1)) #f
          (let loop ((i start) (has-digit #f) (has-dot #f))
            (if (>= i len)
              has-digit
              (let ((ch (string-ref s i)))
                (cond
                  ((char-numeric? ch)
                   (loop (+ i 1) #t has-dot))
                  ((and (equal? ch ".") (not has-dot))
                   (loop (+ i 1) has-digit #t))
                  (else #f))))))))))

; -- Paren depth ---------------------------------------------------

(define (repl:paren-depth src)
  (let ((len (string-length src)))
    (let loop ((pos 0) (depth 0) (in-string #f) (in-comment #f) (escaped #f))
      (if (>= pos len) depth
        (let ((ch (string-ref src pos)))
          (cond
            (in-comment
             (if (equal? ch "\n")
               (loop (+ pos 1) depth in-string #f #f)
               (loop (+ pos 1) depth in-string #t #f)))
            (in-string
             (cond
               (escaped (loop (+ pos 1) depth #t #f #f))
               ((equal? ch "\\") (loop (+ pos 1) depth #t #f #t))
               ((equal? ch "\"") (loop (+ pos 1) depth #f #f #f))
               (else (loop (+ pos 1) depth #t #f #f))))
            ((equal? ch ";") (loop (+ pos 1) depth #f #t #f))
            ((equal? ch "\"") (loop (+ pos 1) depth #t #f #f))
            ((equal? ch "(") (loop (+ pos 1) (+ depth 1) #f #f #f))
            ((equal? ch ")") (loop (+ pos 1) (- depth 1) #f #f #f))
            (else (loop (+ pos 1) depth #f #f #f))))))))

; -- Balance / complete checks -------------------------------------

(define (repl:balanced? src)
  (= (repl:paren-depth src) 0))

(define (repl:complete? src)
  (and (repl:balanced? src)
       (not (repl:in-string? src))
       (repl:has-content? src)))

(define (repl:in-string? src)
  (let ((len (string-length src)))
    (let loop ((pos 0) (in-str #f) (escaped #f))
      (if (>= pos len)
        in-str
        (let ((ch (string-ref src pos)))
          (cond
            (in-str
             (cond
               (escaped (loop (+ pos 1) #t #f))
               ((equal? ch "\\") (loop (+ pos 1) #t #t))
               ((equal? ch "\"") (loop (+ pos 1) #f #f))
               (else (loop (+ pos 1) #t #f))))
            ((equal? ch "\"") (loop (+ pos 1) #t #f))
            ((equal? ch ";")
             (let skip ((p (+ pos 1)))
               (if (or (>= p len) (equal? (string-ref src p) "\n"))
                 (loop (+ p 1) #f #f)
                 (skip (+ p 1)))))
            (else (loop (+ pos 1) #f #f))))))))

(define (repl:has-content? src)
  (let ((len (string-length src)))
    (let loop ((pos 0) (in-comment #f))
      (if (>= pos len) #f
        (let ((ch (string-ref src pos)))
          (cond
            (in-comment
             (if (equal? ch "\n")
               (loop (+ pos 1) #f)
               (loop (+ pos 1) #t)))
            ((equal? ch ";") (loop (+ pos 1) #t))
            ((char-whitespace? ch) (loop (+ pos 1) #f))
            (else #t)))))))

; -- Auto-indent ---------------------------------------------------

(define (repl:auto-indent src)
  (let ((depth (repl:paren-depth src)))
    (if (<= depth 0) 0
      (* depth 2))))

(define (repl:indent-string n)
  (let loop ((i 0) (acc ""))
    (if (>= i n) acc
      (loop (+ i 1) (string-append acc " ")))))

; -- Highlight: token types -> color symbols -----------------------

(define (repl:highlight tokens)
  (map (lambda (tok)
         (let ((type (car tok))
               (text (cdr tok)))
           (cons (case type
                   ((keyword)      'keyword)
                   ((builtin)      'builtin)
                   ((string)       'string)
                   ((number)       'number)
                   ((boolean)      'boolean)
                   ((comment)      'comment)
                   ((lparen rparen) 'paren)
                   ((quote-sugar)  'quote)
                   ((symbol)       'symbol)
                   (else           'default))
                 text)))
       tokens))

; -- Matching paren finder -----------------------------------------

(define (repl:match-paren src cursor-pos)
  (let ((len (string-length src)))
    (if (or (< cursor-pos 0) (>= cursor-pos len))
      -1
      (let ((ch (string-ref src cursor-pos)))
        (cond
          ((equal? ch "(") (repl:find-close src (+ cursor-pos 1) 1))
          ((equal? ch ")") (repl:find-open  src (- cursor-pos 1) 1))
          (else -1))))))

(define (repl:find-close src pos depth)
  (let ((len (string-length src)))
    (let loop ((p pos) (d depth) (in-str #f) (escaped #f))
      (if (>= p len) -1
        (let ((ch (string-ref src p)))
          (cond
            (in-str
             (cond
               (escaped (loop (+ p 1) d #t #f))
               ((equal? ch "\\") (loop (+ p 1) d #t #t))
               ((equal? ch "\"") (loop (+ p 1) d #f #f))
               (else (loop (+ p 1) d #t #f))))
            ((equal? ch "\"") (loop (+ p 1) d #t #f))
            ((equal? ch "(") (loop (+ p 1) (+ d 1) #f #f))
            ((equal? ch ")")
             (if (= d 1) p
               (loop (+ p 1) (- d 1) #f #f)))
            (else (loop (+ p 1) d #f #f))))))))

(define (repl:find-open src pos depth)
  (let loop ((p pos) (d depth))
    (if (< p 0) -1
      (let ((ch (string-ref src p)))
        (cond
          ((equal? ch ")")
           (loop (- p 1) (+ d 1)))
          ((equal? ch "(")
           (if (= d 1) p
             (loop (- p 1) (- d 1))))
          (else (loop (- p 1) d)))))))

; -- Split string on newlines --------------------------------------

(define (repl:split-lines str)
  (let ((len (string-length str)))
    (if (= len 0) '("")
      (let loop ((pos 0) (start 0) (lines '()))
        (if (>= pos len)
          (reverse (cons (substring str start pos) lines))
          (if (equal? (string-ref str pos) "\n")
            (loop (+ pos 1) (+ pos 1)
                  (cons (substring str start pos) lines))
            (loop (+ pos 1) start lines)))))))

; ==================================================================
;  Color palette -- One Dark inspired
; ==================================================================

(define *repl-colors* '())
(define *repl-c-black* 0)
(define *repl-c-white* 0)

(define (repl:init-colors!)
  (set! *repl-c-black* (gml:make-color-rgb 0 0 0))
  (set! *repl-c-white* (gml:make-color-rgb 255 255 255))
  (set! *repl-colors*
    (list
      (cons 'keyword    (gml:make-color-rgb 198 120 221))
      (cons 'builtin    (gml:make-color-rgb  97 175 239))
      (cons 'string     (gml:make-color-rgb 152 195 121))
      (cons 'number     (gml:make-color-rgb 209 154 102))
      (cons 'boolean    (gml:make-color-rgb 209 154 102))
      (cons 'comment    (gml:make-color-rgb  92  99 112))
      (cons 'paren      (gml:make-color-rgb 171 178 191))
      (cons 'quote      (gml:make-color-rgb 198 120 221))
      (cons 'symbol     (gml:make-color-rgb 224 108 117))
      (cons 'default    (gml:make-color-rgb 171 178 191))
      (cons 'error      (gml:make-color-rgb 224 108 117))
      (cons 'prompt     (gml:make-color-rgb  97 175 239))
      (cons 'result     (gml:make-color-rgb 152 195 121))
      (cons 'match      (gml:make-color-rgb 255 215   0))
      (cons 'whitespace (gml:make-color-rgb 171 178 191)))))

(define (repl:color name)
  (let ((pair (assoc name *repl-colors*)))
    (if pair (cdr pair)
      (cdr (assoc 'default *repl-colors*)))))

; ==================================================================
;  Draw helper -- draw colored text (same color all 4 corners)
; ==================================================================

(define (repl:draw-text x y text color alpha)
  (gml:draw-text-color x y text color color color color alpha))

; ==================================================================
;  VK constants -- cached at init for performance
; ==================================================================

(define *vk-f1*        0)
(define *vk-left*      0)
(define *vk-right*     0)
(define *vk-up*        0)
(define *vk-down*      0)
(define *vk-enter*     0)
(define *vk-backspace* 0)
(define *vk-delete*    0)
(define *vk-home*      0)
(define *vk-end*       0)
(define *vk-tab*       0)
(define *vk-escape*    0)
(define *vk-shift*     0)
(define *vk-control*   0)
(define *ord-V*        0)
(define *ord-L*        0)

(define (repl:init-vk!)
  (set! *vk-f1*        (gml:vk-f1))
  (set! *vk-left*      (gml:vk-left))
  (set! *vk-right*     (gml:vk-right))
  (set! *vk-up*        (gml:vk-up))
  (set! *vk-down*      (gml:vk-down))
  (set! *vk-enter*     (gml:vk-enter))
  (set! *vk-backspace* (gml:vk-backspace))
  (set! *vk-delete*    (gml:vk-delete))
  (set! *vk-home*      (gml:vk-home))
  (set! *vk-end*       (gml:vk-end))
  (set! *vk-tab*       (gml:vk-tab))
  (set! *vk-escape*    (gml:vk-escape))
  (set! *vk-shift*     (gml:vk-shift))
  (set! *vk-control*   (gml:vk-control))
  (set! *ord-V*        (gml:ord "V"))
  (set! *ord-L*        (gml:ord "L")))

; ==================================================================
;  Mutable REPL state
; ==================================================================

(define *repl-buf*           "")     ; current input buffer
(define *repl-cursor*        0)      ; 0-based cursor position
(define *repl-multi*         "")     ; multi-line accumulator
(define *repl-history*       '())    ; past inputs (newest first)
(define *repl-hist-idx*      -1)     ; -1 = not browsing
(define *repl-hist-saved*    "")     ; saved input when browsing
(define *repl-output*        '())    ; output entries (newest first)
(define *repl-output-gen*    0)      ; cache invalidation counter
(define *repl-output-max*    200)    ; max output entries
(define *repl-eval-pending*  #f)     ; #f or code-string to evaluate
(define *repl-visible*       #f)     ; visibility flag
(define *repl-token-cache*   '())    ; cached (buf . tokens) pair
(define *repl-font*          -1)     ; GML font ID, -1 = default

; -- Key repeat state ----------------------------------------------

(define *key-left-hold*  0)
(define *key-right-hold* 0)
(define *key-back-hold*  0)
(define *key-alarm*      0)

; ==================================================================
;  Initialization
; ==================================================================

(define (repl:init!)
  (set! *repl-buf*          "")
  (set! *repl-cursor*       0)
  (set! *repl-multi*        "")
  (set! *repl-history*      '())
  (set! *repl-hist-idx*     -1)
  (set! *repl-hist-saved*   "")
  (set! *repl-output*       '())
  (set! *repl-output-gen*   0)
  (set! *repl-eval-pending* #f)
  (set! *repl-visible*      #f)
  (set! *repl-token-cache*  '())
  (repl:init-colors!)
  (repl:init-vk!)
  ;; Welcome
  (repl:add-output! "Scheme REPL (gml_scheme)" 'comment)
  (repl:add-output! "F1 toggle | Enter eval | Shift+Enter newline | Up/Down history" 'comment)
  (repl:add-output! "" 'default))

; ==================================================================
;  Visibility
; ==================================================================

(define (repl:visible?) *repl-visible*)

(define (repl:toggle!)
  (set! *repl-visible* (not *repl-visible*)))

; ==================================================================
;  String helpers for buffer editing
; ==================================================================

(define (repl:str-insert base pos text)
  (string-append
    (substring base 0 pos)
    text
    (substring base pos (string-length base))))

(define (repl:str-delete-at base pos)
  (string-append
    (substring base 0 pos)
    (substring base (+ pos 1) (string-length base))))

; ==================================================================
;  Key repeat
; ==================================================================

(define (repl:reset-key-state!)
  (set! *key-left-hold*  0)
  (set! *key-right-hold* 0)
  (set! *key-back-hold*  0)
  (set! *key-alarm*      -1))

(define (repl:check-key! which)
  (let* ((vk    (cond ((equal? which 'left)  *vk-left*)
                       ((equal? which 'right) *vk-right*)
                       ((equal? which 'back)  *vk-backspace*)
                       (else 0)))
         (hold  (cond ((equal? which 'left)  *key-left-hold*)
                       ((equal? which 'right) *key-right-hold*)
                       ((equal? which 'back)  *key-back-hold*)
                       (else 0))))
    (if (gml:keyboard-check vk)
      (let* ((dur (+ hold 1))
             (delay (if (>= dur 13) 1 4)))
        ;; Update hold counter
        (cond ((equal? which 'left)  (set! *key-left-hold* dur))
              ((equal? which 'right) (set! *key-right-hold* dur))
              ((equal? which 'back)  (set! *key-back-hold* dur)))
        ;; Check alarm
        (if (<= *key-alarm* 0)
          (begin (set! *key-alarm* delay) #t)
          #f))
      ;; Key not held -> reset
      (begin
        (cond ((equal? which 'left)  (set! *key-left-hold* 0))
              ((equal? which 'right) (set! *key-right-hold* 0))
              ((equal? which 'back)  (set! *key-back-hold* 0)))
        #f))))

; ==================================================================
;  Input operations
; ==================================================================

(define (repl:type-chars! str)
  (set! *repl-buf* (repl:str-insert *repl-buf* *repl-cursor* str))
  (set! *repl-cursor* (+ *repl-cursor* (string-length str)))
  (set! *repl-hist-idx* -1))

(define (repl:paste! str)
  (let ((clean (gml:string-replace-all str "\r" "")))
    (repl:type-chars! clean)))

(define (repl:key! key)
  (case key
    ((left)
     (when (> *repl-cursor* 0)
       (set! *repl-cursor* (- *repl-cursor* 1))))

    ((right)
     (when (< *repl-cursor* (string-length *repl-buf*))
       (set! *repl-cursor* (+ *repl-cursor* 1))))

    ((backspace)
     (when (> *repl-cursor* 0)
       (set! *repl-buf* (repl:str-delete-at *repl-buf* (- *repl-cursor* 1)))
       (set! *repl-cursor* (- *repl-cursor* 1))))

    ((delete)
     (when (< *repl-cursor* (string-length *repl-buf*))
       (set! *repl-buf* (repl:str-delete-at *repl-buf* *repl-cursor*))))

    ((home)
     (set! *repl-cursor* 0))

    ((end)
     (set! *repl-cursor* (string-length *repl-buf*)))

    ((enter)
     (repl:submit!))

    ((shift-enter)
     (repl:newline!))

    ((up)
     (repl:history-nav! 1))

    ((down)
     (repl:history-nav! -1))))

; ==================================================================
;  Submit / newline logic
; ==================================================================

(define (repl:submit!)
  (let ((full (string-append *repl-multi* *repl-buf*)))
    (if (repl:empty-input? full)
      ;; Empty -> reset
      (begin
        (set! *repl-buf* "")
        (set! *repl-cursor* 0)
        (set! *repl-multi* ""))
      ;; Check completeness
      (if (repl:complete? full)
        ;; Complete -> request eval
        (begin
          (repl:echo-input! full)
          (repl:history-push! full)
          (set! *repl-eval-pending* full)
          (set! *repl-buf* "")
          (set! *repl-cursor* 0)
          (set! *repl-multi* ""))
        ;; Incomplete -> continue multi-line
        (repl:newline!)))))

(define (repl:newline!)
  (let* ((full (string-append *repl-multi* *repl-buf*))
         (indent-n (repl:auto-indent full))
         (indent-str (repl:indent-string indent-n)))
    (set! *repl-multi* (string-append full "\n"))
    (set! *repl-buf* indent-str)
    (set! *repl-cursor* indent-n)))

(define (repl:empty-input? str)
  (let ((stripped (gml:string-replace-all
                    (gml:string-replace-all str " " "")
                    "\n" "")))
    (string-empty? stripped)))

; -- Echo highlighted input to output ------------------------------

(define (repl:echo-input! full)
  (let ((lines (repl:split-lines full)))
    (let loop ((ls lines) (first #t))
      (when (pair? ls)
        (let* ((line (car ls))
               (prefix (if first "> " "... "))
               (tokens (repl:tokenize line))
               (highlighted (repl:highlight tokens))
               (spans (cons (cons 'prompt prefix) highlighted)))
          (repl:add-output-spans! spans))
        (loop (cdr ls) #f)))))

; ==================================================================
;  History management
; ==================================================================

(define (repl:history-push! input)
  (when (not (string-empty? input))
    (when (or (null? *repl-history*)
              (not (equal? (car *repl-history*) input)))
      (set! *repl-history* (cons input *repl-history*))
      (when (> (length *repl-history*) 100)
        (set! *repl-history* (take *repl-history* 100))))))

(define (repl:history-nav! dir)
  (let ((size (length *repl-history*)))
    (when (> size 0)
      (cond
        ;; Up -> go back in history
        ((> dir 0)
         (cond
           ((< *repl-hist-idx* 0)
            (set! *repl-hist-saved* *repl-buf*)
            (set! *repl-hist-idx* 0))
           ((< *repl-hist-idx* (- size 1))
            (set! *repl-hist-idx* (+ *repl-hist-idx* 1))))
         (set! *repl-buf* (list-ref *repl-history* *repl-hist-idx*))
         (set! *repl-cursor* (string-length *repl-buf*)))

        ;; Down -> go forward in history
        ((< dir 0)
         (cond
           ((> *repl-hist-idx* 0)
            (set! *repl-hist-idx* (- *repl-hist-idx* 1))
            (set! *repl-buf* (list-ref *repl-history* *repl-hist-idx*))
            (set! *repl-cursor* (string-length *repl-buf*)))
           ((= *repl-hist-idx* 0)
            (set! *repl-hist-idx* -1)
            (set! *repl-buf* *repl-hist-saved*)
            (set! *repl-cursor* (string-length *repl-buf*)))))))))

; ==================================================================
;  Output management (newest-first for O(1) prepend)
; ==================================================================

(define (repl:add-output! text color)
  (set! *repl-output*
    (cons (list 'line color text) *repl-output*))
  (repl:trim-output!)
  (set! *repl-output-gen* (+ *repl-output-gen* 1)))

(define (repl:add-output-spans! spans)
  (set! *repl-output*
    (cons (cons 'spans spans) *repl-output*))
  (repl:trim-output!)
  (set! *repl-output-gen* (+ *repl-output-gen* 1)))

(define (repl:trim-output!)
  (when (> (length *repl-output*) *repl-output-max*)
    (set! *repl-output* (take *repl-output* *repl-output-max*))))

(define (repl:clear-output!)
  (set! *repl-output* '())
  (set! *repl-output-gen* (+ *repl-output-gen* 1)))

; ==================================================================
;  Eval coordination
; ==================================================================

(define (repl:consume-eval!)
  (let ((code *repl-eval-pending*))
    (set! *repl-eval-pending* #f)
    code))

(define (repl:feed-eval-result! text color)
  (when (not (string-empty? text))
    (repl:add-output! text color)))

(define (repl:feed-eval-output! text)
  (repl:add-output! text 'default))

; ==================================================================
;  Token cache for input display
; ==================================================================

(define (repl:get-input-tokens)
  (if (and (pair? *repl-token-cache*)
           (equal? (car *repl-token-cache*) *repl-buf*))
    (cdr *repl-token-cache*)
    (let ((tokens (repl:highlight (repl:tokenize *repl-buf*))))
      (set! *repl-token-cache* (cons *repl-buf* tokens))
      tokens)))

; ==================================================================
;  Keyboard trapping
; ==================================================================

(define (repl:trap-keys!)
  (gml:keyboard-string-clear!)
  (gml:keyboard-clear *vk-enter*)
  (gml:keyboard-clear *vk-backspace*)
  (gml:keyboard-clear *vk-delete*)
  (gml:keyboard-clear *vk-up*)
  (gml:keyboard-clear *vk-down*)
  (gml:keyboard-clear *vk-left*)
  (gml:keyboard-clear *vk-right*)
  (gml:keyboard-clear *vk-home*)
  (gml:keyboard-clear *vk-end*)
  (gml:keyboard-clear *vk-tab*)
  (gml:keyboard-clear *vk-escape*))

; ==================================================================
;  repl:step! -- Full keyboard handling (legacy, not used by GML shell)
;  Returns: pending eval code (string) or #f
; ==================================================================

(define (repl:step!)
  (cond
    ;; Toggle (F1) -- always check, even when hidden
    ((gml:keyboard-check-pressed *vk-f1*)
     (repl:toggle!)
     (gml:keyboard-string-clear!)
     (when *repl-visible* (repl:reset-key-state!))
     #f)

    ;; Normal input (when visible)
    (*repl-visible*
     (repl:step-input!)
     ;; Return pending eval code if any
     (if *repl-eval-pending*
       (repl:consume-eval!)
       #f))

    ;; Not visible, nothing to do
    (else #f)))

; ==================================================================
;  repl:step-visible! -- Input handling only (toggle done in GML)
;  Called by GML shell only when REPL is already visible.
;  Returns: pending eval code (string) or #f
; ==================================================================

(define (repl:step-visible!)
  (repl:step-input!)
  (if *repl-eval-pending*
    (repl:consume-eval!)
    #f))

(define (repl:step-input!)
  ;; Tick alarm
  (when (> *key-alarm* 0)
    (set! *key-alarm* (- *key-alarm* 1)))

  ;; Character input
  (let ((typed (gml:keyboard-string)))
    (when (> (string-length typed) 0)
      (gml:keyboard-string-clear!)
      (repl:type-chars! typed)))

  ;; Key repeat keys
  (when (repl:check-key! 'left)  (repl:key! 'left))
  (when (repl:check-key! 'right) (repl:key! 'right))
  (when (repl:check-key! 'back)  (repl:key! 'backspace))

  ;; Non-repeat special keys
  (when (gml:keyboard-check-pressed *vk-delete*) (repl:key! 'delete))
  (when (gml:keyboard-check-pressed *vk-home*)   (repl:key! 'home))
  (when (gml:keyboard-check-pressed *vk-end*)    (repl:key! 'end))

  ;; Enter / Shift+Enter
  (when (gml:keyboard-check-pressed *vk-enter*)
    (if (gml:keyboard-check *vk-shift*)
      (repl:key! 'shift-enter)
      (repl:key! 'enter)))

  ;; History
  (when (gml:keyboard-check-pressed *vk-up*)   (repl:key! 'up))
  (when (gml:keyboard-check-pressed *vk-down*) (repl:key! 'down))

  ;; Ctrl+V paste
  (when (and (gml:keyboard-check *vk-control*)
             (gml:keyboard-check-pressed *ord-V*)
             (gml:clipboard-has-text?))
    (repl:paste! (gml:clipboard-get-text)))

  ;; Ctrl+L clear output
  (when (and (gml:keyboard-check *vk-control*)
             (gml:keyboard-check-pressed *ord-L*))
    (repl:clear-output!))

  ;; Keyboard trapping
  (repl:trap-keys!))

; ==================================================================
;  repl:draw! -- Full GUI rendering
; ==================================================================

(define (repl:draw!)
  (when *repl-visible*
    (let* ((w (gml:display-get-gui-width))
           (h (gml:display-get-gui-height))
           (prev-font  (gml:draw-get-font))
           (prev-alpha (gml:draw-get-alpha))
           (prev-color (gml:draw-get-color)))
      (gml:draw-set-font *repl-font*)
      (let* ((line-h (+ (gml:string-height "Ay|") 4))
             (pad 16)
             (x0 pad)
             (y-bottom (- h pad)))

        ;; Background overlay
        (gml:draw-set-alpha 0.85)
        (gml:draw-rectangle-color
          0 0 w h
          *repl-c-black* *repl-c-black* *repl-c-black* *repl-c-black* 0)
        (gml:draw-set-alpha 1.0)

        ;; Output history (bottom-up, newest first in list)
        (repl:draw-output! x0 (- y-bottom line-h 6) line-h)

        ;; Input line with highlighting
        (repl:draw-input! x0 y-bottom)

        ;; Blinking cursor
        (repl:draw-cursor! x0 y-bottom))

      ;; Restore draw state
      (gml:draw-set-font prev-font)
      (gml:draw-set-alpha prev-alpha)
      (gml:draw-set-color prev-color))))

; -- Draw output entries -------------------------------------------

(define (repl:draw-output! x0 start-y line-h)
  ;; *repl-output* is newest-first; draw upward from start-y
  (let loop ((entries *repl-output*) (y start-y))
    (when (and (pair? entries) (> y 0))
      (let ((entry (car entries)))
        (cond
          ;; Spans: (spans (color . text) (color . text) ...)
          ((and (pair? entry) (equal? (car entry) 'spans))
           (let span-loop ((spans (cdr entry)) (xx x0))
             (when (pair? spans)
               (let* ((span (car spans))
                      (color-name (car span))
                      (text (cdr span)))
                 (repl:draw-text xx y text (repl:color color-name) 0.9)
                 (span-loop (cdr spans) (+ xx (gml:string-width text)))))))

          ;; Line: (line color text)
          ((and (pair? entry) (equal? (car entry) 'line))
           (let ((color-name (list-ref entry 1))
                 (text (list-ref entry 2)))
             (repl:draw-text x0 y text (repl:color color-name) 0.9)))))

      (loop (cdr entries) (- y line-h)))))

; -- Draw input line -----------------------------------------------

(define (repl:draw-input! x0 y)
  (let* ((prompt (if (string-empty? *repl-multi*) "> " "... "))
         (xx x0))
    ;; Prompt
    (repl:draw-text xx y prompt (repl:color 'prompt) 1.0)
    (set! xx (+ xx (gml:string-width prompt)))

    ;; Highlighted tokens
    (let loop ((toks (repl:get-input-tokens)) (x xx))
      (when (pair? toks)
        (let* ((tok (car toks))
               (color-name (car tok))
               (text (cdr tok)))
          (repl:draw-text x y text (repl:color color-name) 1.0)
          (loop (cdr toks) (+ x (gml:string-width text))))))))

; -- Draw blinking cursor ------------------------------------------

(define (repl:draw-cursor! x0 y)
  (let* ((prompt (if (string-empty? *repl-multi*) "> " "... "))
         (input-start-x (+ x0 (gml:string-width prompt)))
         (cursor-text (substring *repl-buf* 0 *repl-cursor*))
         (cursor-x (+ input-start-x (gml:string-width cursor-text)))
         (blink (gml:abs (gml:sin (/ (gml:current-time) 300)))))
    (repl:draw-text (- cursor-x 1) y "|" *repl-c-white* blink)))
