"""help_db.py — Help text database for gml_scheme REPL.

Each entry: name → {sig, zh, en, example?}
  sig:     Calling signature (code, never translated)
  zh/en:   One-line description
  example: Optional usage example (code, never translated)

Categories:
  SPECIAL_FORMS   — language keywords (define, lambda, etc.)
  CORE_BUILTINS   — procedures implemented in scm_core.gml
  CORE_EXTRAS     — apropos, %self-test (scm_core.gml)
  PRELUDE         — procedures defined in prelude.scm
  STDLIB          — handle predicates, constructors, converters, pretty printer (stdlib.scm)
  BRIDGE          — FFI (scm_bridge.gml)
  GML_WRAPPERS    — user-facing gml: builtins (from codegen spec)
  ALIASES         — short aliases defined in prelude (instance-get, etc.)

Internal/REPL-only functions (vk-*, draw-*, keyboard-*) are excluded.
"""

from __future__ import annotations

HelpEntry = dict[str, str]  # keys: sig, zh, en, example (optional)

# ── Special Forms ────────────────────────────────────────────────

SPECIAL_FORMS: dict[str, HelpEntry] = {
    "define": {
        "sig": "(define name value)  |  (define (name args...) body...)",
        "zh":  "定义变量或函数。",
        "en":  "Define a variable or function.",
        "example": '(define x 42)\n(define (square n) (* n n))',
    },
    "lambda": {
        "sig": "(lambda (args...) body...)",
        "zh":  "创建匿名函数(闭包)。",
        "en":  "Create an anonymous function (closure).",
        "example": "(lambda (x y) (+ x y))",
    },
    "if": {
        "sig": "(if test then else)",
        "zh":  "条件分支。test 为真执行 then, 否则执行 else。",
        "en":  "Conditional branch. Evaluates then if test is true, else otherwise.",
        "example": "(if (> x 0) \"positive\" \"non-positive\")",
    },
    "cond": {
        "sig": "(cond (test1 expr1...) (test2 expr2...) ... (else expr...))",
        "zh":  "多条件分支, 依次测试直到匹配。",
        "en":  "Multi-way conditional. Tests clauses in order.",
        "example": "(cond ((= x 1) \"one\") ((= x 2) \"two\") (else \"other\"))",
    },
    "when": {
        "sig": "(when test body...)",
        "zh":  "test 为真时执行 body(无 else 分支)。",
        "en":  "Execute body when test is true (no else branch).",
    },
    "unless": {
        "sig": "(unless test body...)",
        "zh":  "test 为假时执行 body。",
        "en":  "Execute body when test is false.",
    },
    "let": {
        "sig": "(let ((var1 val1) ...) body...)  |  (let name ((var val) ...) body...)",
        "zh":  "局部变量绑定。命名 let 可用于循环。",
        "en":  "Local variable bindings. Named let enables loops.",
        "example": "(let ((x 1) (y 2)) (+ x y))\n(let loop ((i 0)) (if (= i 5) i (loop (+ i 1))))",
    },
    "let*": {
        "sig": "(let* ((var1 val1) (var2 val2) ...) body...)",
        "zh":  "顺序绑定的 let, 后面的绑定可引用前面的。",
        "en":  "Sequential let. Later bindings can reference earlier ones.",
    },
    "letrec": {
        "sig": "(letrec ((var1 val1) ...) body...)",
        "zh":  "递归绑定的 let, 绑定之间可互相引用。",
        "en":  "Recursive let. Bindings can reference each other.",
    },
    "begin": {
        "sig": "(begin expr1 expr2 ...)",
        "zh":  "顺序执行多个表达式, 返回最后一个的值。",
        "en":  "Evaluate expressions in sequence, return last value.",
    },
    "set!": {
        "sig": "(set! var value)",
        "zh":  "修改已绑定变量的值。",
        "en":  "Mutate an existing variable binding.",
    },
    "quote": {
        "sig": "(quote datum)  |  'datum",
        "zh":  "返回 datum 本身, 不求值。",
        "en":  "Return datum without evaluating it.",
        "example": "'(1 2 3)  ;=> (1 2 3)",
    },
    "quasiquote": {
        "sig": "`(template ,expr ,@list-expr)",
        "zh":  "准引用模板, 用 , 插入求值结果, ,@ 展开列表。",
        "en":  "Template with , for eval and ,@ for splicing.",
        "example": "`(a ,(+ 1 2) ,@'(x y))  ;=> (a 3 x y)",
    },
    "do": {
        "sig": "(do ((var init step) ...) (test result) body...)",
        "zh":  "迭代循环。每步更新变量, test 为真时返回 result。",
        "en":  "Iteration loop. Steps variables, returns result when test is true.",
        "example": "(do ((i 0 (+ i 1))) ((= i 5) i))",
    },
    "and": {
        "sig": "(and expr ...)",
        "zh":  "逻辑与, 短路求值。全真返回最后一个值, 否则返回 #f。",
        "en":  "Logical and with short-circuit. Returns last true value or #f.",
    },
    "or": {
        "sig": "(or expr ...)",
        "zh":  "逻辑或, 短路求值。返回第一个真值, 全假返回 #f。",
        "en":  "Logical or with short-circuit. Returns first true value or #f.",
    },
    "case": {
        "sig": "(case expr ((datum ...) body ...) ... (else body ...))",
        "zh":  "值匹配分支, 类似 switch。",
        "en":  "Value-matching conditional, similar to switch.",
    },
    "define-macro": {
        "sig": "(define-macro (name params ...) body ...)",
        "zh":  "定义非卫生宏 (Lisp-style)。变换器接收未求值参数, 返回 AST 再求值。",
        "en":  "Define a non-hygienic macro. Transformer receives unevaluated args, returns AST to eval.",
        "example": "(define-macro (swap! a b)\n  `(let ((__tmp ,a)) (set! ,a ,b) (set! ,b __tmp)))",
    },
}

# ── Core Builtins (scm_core.gml) ────────────────────────────────

CORE_BUILTINS: dict[str, HelpEntry] = {
    # Arithmetic
    "+": {"sig": "(+ n ...)", "zh": "加法。支持多参数。", "en": "Addition. Variadic."},
    "-": {"sig": "(- n ...)", "zh": "减法。单参数取负。", "en": "Subtraction. Unary negation."},
    "*": {"sig": "(* n ...)", "zh": "乘法。支持多参数。", "en": "Multiplication. Variadic."},
    "/": {"sig": "(/ n ...)", "zh": "除法。", "en": "Division."},
    "modulo": {"sig": "(modulo a b)", "zh": "取模(余数)。", "en": "Modulo (remainder)."},
    "min": {"sig": "(min a b)", "zh": "取较小值。", "en": "Minimum of two numbers."},
    "max": {"sig": "(max a b)", "zh": "取较大值。", "en": "Maximum of two numbers."},

    # Comparison (chained)
    "=":  {"sig": "(= a b ...)", "zh": "数值相等。支持链式比较。", "en": "Numeric equality. Chained."},
    "<":  {"sig": "(< a b ...)", "zh": "小于。支持链式: (< 1 2 3) => #t。", "en": "Less than. Chained: (< 1 2 3) => #t."},
    ">":  {"sig": "(> a b ...)", "zh": "大于。支持链式比较。", "en": "Greater than. Chained."},
    "<=": {"sig": "(<= a b ...)", "zh": "小于等于。支持链式比较。", "en": "Less or equal. Chained."},
    ">=": {"sig": "(>= a b ...)", "zh": "大于等于。支持链式比较。", "en": "Greater or equal. Chained."},

    # Predicates
    "null?":    {"sig": "(null? x)", "zh": "是否为空列表。", "en": "Is x the empty list?"},
    "pair?":    {"sig": "(pair? x)", "zh": "是否为点对/列表节点。", "en": "Is x a pair (cons cell)?"},
    "number?":  {"sig": "(number? x)", "zh": "是否为数值。", "en": "Is x a number?"},
    "string?":  {"sig": "(string? x)", "zh": "是否为字符串。", "en": "Is x a string?"},
    "symbol?":  {"sig": "(symbol? x)", "zh": "是否为符号。", "en": "Is x a symbol?"},
    "boolean?": {"sig": "(boolean? x)", "zh": "是否为布尔值。", "en": "Is x a boolean?"},
    "list?":    {"sig": "(list? x)", "zh": "是否为正规列表。", "en": "Is x a proper list?"},
    "zero?":    {"sig": "(zero? x)", "zh": "是否为零。", "en": "Is x zero?"},
    "void?":    {"sig": "(void? x)", "zh": "是否为 void 值。", "en": "Is x void?"},
    "procedure?": {"sig": "(procedure? x)", "zh": "是否为可调用过程。", "en": "Is x a procedure?"},
    "not":      {"sig": "(not x)", "zh": "逻辑非。", "en": "Logical negation."},
    "equal?":   {"sig": "(equal? a b)", "zh": "结构相等比较(深比较)。", "en": "Structural equality (deep comparison)."},
    "eq?":      {"sig": "(eq? a b)", "zh": "引用相等(同一对象)。", "en": "Identity comparison (same object)."},
    "eqv?":     {"sig": "(eqv? a b)", "zh": "等价比较。", "en": "Equivalence comparison."},

    # Pairs & Lists
    "cons":     {"sig": "(cons a b)", "zh": "创建点对。", "en": "Create a pair.", "example": "(cons 1 '(2 3)) ;=> (1 2 3)"},
    "car":      {"sig": "(car pair)", "zh": "取点对首元素（列表的头）。", "en": "First element of a pair (list head)."},
    "cdr":      {"sig": "(cdr pair)", "zh": "取点对尾部（列表除首项外的余下部分）。", "en": "Second element (tail of list)."},
    "set-car!": {"sig": "(set-car! pair val)", "zh": "修改点对的 car。", "en": "Mutate the car of a pair."},
    "set-cdr!": {"sig": "(set-cdr! pair val)", "zh": "修改点对的 cdr。", "en": "Mutate the cdr of a pair."},
    "list":     {"sig": "(list a b ...)", "zh": "创建列表。", "en": "Create a list from arguments.", "example": "(list 1 2 3) ;=> (1 2 3)"},
    "length":   {"sig": "(length lst)", "zh": "列表长度。", "en": "Length of a list."},
    "reverse":  {"sig": "(reverse lst)", "zh": "反转列表。", "en": "Reverse a list."},
    "append":   {"sig": "(append lst ...)", "zh": "拼接多个列表。", "en": "Concatenate lists."},
    "list-ref": {"sig": "(list-ref lst n)", "zh": "取列表第 n 项（下标从 0 起）。", "en": "Get nth element (0-based)."},
    "list-tail": {"sig": "(list-tail lst n)", "zh": "返回跳过前 n 项后的子列表。", "en": "Return tail after skipping n elements."},

    # String
    "string-length":    {"sig": "(string-length s)", "zh": "字符串长度。", "en": "Length of a string."},
    "string-ref":       {"sig": "(string-ref s n)", "zh": "取第 n 个字符（下标从 1 起，GML 规则）。", "en": "Character at position n (1-based, GML convention)."},
    "string-append":    {"sig": "(string-append s ...)", "zh": "拼接字符串。", "en": "Concatenate strings."},
    "substring":        {"sig": "(substring s start end)", "zh": "取子串 [start, end)。", "en": "Extract substring [start, end)."},
    "string->number":   {"sig": "(string->number s)", "zh": "字符串转数值。", "en": "Parse string as number."},
    "number->string":   {"sig": "(number->string n)", "zh": "数值转字符串。", "en": "Convert number to string."},
    "string->symbol":   {"sig": "(string->symbol s)", "zh": "字符串转符号。", "en": "Convert string to symbol."},
    "symbol->string":   {"sig": "(symbol->string s)", "zh": "符号转字符串。", "en": "Convert symbol to string."},
    "string-contains?": {"sig": "(string-contains? s sub)", "zh": "是否包含子串。", "en": "Does s contain sub?"},
    "string-upcase":    {"sig": "(string-upcase s)", "zh": "转大写。", "en": "Convert to uppercase."},
    "string-downcase":  {"sig": "(string-downcase s)", "zh": "转小写。", "en": "Convert to lowercase."},
    "string-split":     {"sig": "(string-split s sep)", "zh": "按分隔符拆分字符串。", "en": "Split string by separator."},
    "string-join":      {"sig": "(string-join lst sep)", "zh": "用分隔符拼接字符串列表。", "en": "Join list of strings with separator."},
    "string-empty?":    {"sig": "(string-empty? s)", "zh": "是否为空字符串。", "en": "Is s an empty string?"},

    # I/O
    "display": {"sig": "(display x)", "zh": "输出值（不含引号，人类可读格式）。", "en": "Print value (human-readable, strings without quotes)."},
    "write":   {"sig": "(write x)", "zh": "输出值（字符串保留引号，机器可读格式）。", "en": "Print value (machine-readable, strings quoted)."},
    "print":   {"sig": "(print x)", "zh": "输出值并换行。", "en": "Print value followed by newline."},
    "newline": {"sig": "(newline)", "zh": "输出换行。", "en": "Print a newline."},

    # Misc
    "apply": {"sig": "(apply proc args)", "zh": "将列表 args 解包为参数调用 proc。", "en": "Call proc with args list spread as arguments.", "example": "(apply + '(1 2 3)) ;=> 6"},
    "error": {"sig": '(error "msg")', "zh": "抛出错误。", "en": "Raise an error."},
    "void":  {"sig": "(void)", "zh": "返回 void 值(无有意义的返回值)。", "en": "Return the void value."},
    "gensym": {"sig": "(gensym)", "zh": "生成全局唯一符号（常用于宏卫生处理）。", "en": "Generate a globally unique symbol (for macro hygiene)."},
    "macroexpand-1": {
        "sig": "(macroexpand-1 form)",
        "zh":  "宏展开一步。若 form 的头部是宏则展开一次, 否则原样返回。",
        "en":  "Single-step macro expansion. Expands once if head is a macro, else returns form unchanged.",
        "example": "(macroexpand-1 '(-> x (f 1) (g 2)))",
    },
    "macroexpand": {
        "sig": "(macroexpand form)",
        "zh":  "完全宏展开。反复展开直到头部不再是宏。",
        "en":  "Fully expand a macro form. Repeats until head is no longer a macro.",
        "example": "(macroexpand '(-> x (f 1) (g 2)))",
    },
    "macro?": {
        "sig": "(macro? sym)",
        "zh":  "判断符号是否是已定义的宏。",
        "en":  "Check if a symbol names a defined macro.",
        "example": "(macro? '->) ;=> #t",
    },
}

# ── Prelude (prelude.scm) ───────────────────────────────────────

PRELUDE: dict[str, HelpEntry] = {
    # Math aliases
    "abs":     {"sig": "(abs n)", "zh": "绝对值。", "en": "Absolute value."},
    "floor":   {"sig": "(floor n)", "zh": "向下取整。", "en": "Floor (round down)."},
    "ceiling": {"sig": "(ceiling n)", "zh": "向上取整。", "en": "Ceiling (round up)."},
    "round":   {"sig": "(round n)", "zh": "四舍五入。", "en": "Round to nearest integer."},
    "sqrt":    {"sig": "(sqrt n)", "zh": "平方根。", "en": "Square root."},
    "expt":    {"sig": "(expt base exp)", "zh": "幂运算。", "en": "Exponentiation."},
    "sign":    {"sig": "(sign n)", "zh": "符号函数：返回 -1、0 或 1。", "en": "Sign function: returns -1, 0, or 1."},
    "clamp":   {"sig": "(clamp val lo hi)", "zh": "将值限制在 [lo, hi] 区间内。", "en": "Clamp value to [lo, hi]."},
    "sin":     {"sig": "(sin rad)", "zh": "正弦(弧度)。", "en": "Sine (radians)."},
    "cos":     {"sig": "(cos rad)", "zh": "余弦(弧度)。", "en": "Cosine (radians)."},
    "random":  {"sig": "(random n)", "zh": "生成 [0, n) 范围内的随机实数。", "en": "Random real in [0, n)."},
    "irandom": {"sig": "(irandom n)", "zh": "生成 [0, n] 范围内的随机整数（含 n）。", "en": "Random integer in [0, n] (inclusive)."},
    "lerp":    {"sig": "(lerp a b t)", "zh": "线性插值: a + t*(b-a)。", "en": "Linear interpolation: a + t*(b-a)."},

    # List accessors
    "caar":  {"sig": "(caar x)", "zh": "列表首项的首项，等价于 (car (car x))。", "en": "(car (car x)), first element of first element."},
    "cadr":  {"sig": "(cadr x)", "zh": "列表第二项，等价于 (car (cdr x))。", "en": "(car (cdr x)), second element."},
    "cdar":  {"sig": "(cdar x)", "zh": "取首项的尾部，等价于 (cdr (car x))。", "en": "(cdr (car x)), tail of first element."},
    "cddr":  {"sig": "(cddr x)", "zh": "跳过前两项，等价于 (cdr (cdr x))。", "en": "(cdr (cdr x)), tail after two."},
    "cadar": {"sig": "(cadar x)", "zh": "等价于 (car (cdr (car x)))。", "en": "(car (cdr (car x)))."},
    "caddr": {"sig": "(caddr x)", "zh": "列表第三项，等价于 (car (cdr (cdr x)))。", "en": "(car (cdr (cdr x))), third element."},
    "cdddr": {"sig": "(cdddr x)", "zh": "跳过前三项，等价于 (cdr (cdr (cdr x)))。", "en": "(cdr (cdr (cdr x))), tail after three."},

    # Higher-order
    "map":       {"sig": "(map f lst)", "zh": "对列表每个元素应用 f，返回结果列表。", "en": "Apply f to each element, return results.", "example": "(map (lambda (x) (* x x)) '(1 2 3)) ;=> (1 4 9)"},
    "filter":    {"sig": "(filter pred lst)", "zh": "筛选满足 pred 的元素，返回新列表。", "en": "Keep elements satisfying pred.", "example": "(filter even? '(1 2 3 4)) ;=> (2 4)"},
    "remove":    {"sig": "(remove pred lst)", "zh": "移除满足 pred 的元素（filter 的补集）。", "en": "Remove elements satisfying pred (complement of filter)."},
    "for-each":  {"sig": "(for-each f lst)", "zh": "对每个元素调用 f 产生副作用，忽略返回值。", "en": "Call f on each element for side effects, discard results."},
    "foldl":     {"sig": "(foldl f init lst)", "zh": "左折叠累积，f 接受 (当前元素 累积值) 两个参数（尾递归）。", "en": "Left fold (tail-recursive). f signature: (elem accumulator) -> accumulator.", "example": "(foldl + 0 '(1 2 3)) ;=> 6"},
    "foldr":     {"sig": "(foldr f init lst)", "zh": "右折叠（非尾递归，仅用于短列表）。", "en": "Right fold (not tail-recursive, use on short lists)."},
    "append-map": {"sig": "(append-map f lst)", "zh": "对每个元素应用 f 并拼接结果列表（相当于 flatMap）。", "en": "Map then concatenate results (flatMap)."},
    "any":       {"sig": "(any pred lst)", "zh": "列表中是否存在满足 pred 的元素（短路求值）。", "en": "Does any element satisfy pred? (short-circuits)"},
    "every":     {"sig": "(every pred lst)", "zh": "列表中所有元素是否都满足 pred（短路求值）。", "en": "Do all elements satisfy pred? (short-circuits)"},
    "find":      {"sig": "(find pred lst)", "zh": "返回首个满足 pred 的元素，找不到返回 #f。", "en": "First element satisfying pred, or #f."},
    "count":     {"sig": "(count pred lst)", "zh": "统计满足 pred 的元素个数。", "en": "Count elements satisfying pred."},
    "partition": {"sig": "(partition pred lst)", "zh": "按 pred 将列表一分为二，返回 (满足列表 . 不满足列表) 点对。", "en": "Split into (matching . non-matching) pair.", "example": "(partition even? '(1 2 3 4)) ;=> ((2 4) . (1 3))"},

    # Numeric predicates
    "positive?": {"sig": "(positive? n)", "zh": "是否为正数。", "en": "Is n positive?"},
    "negative?": {"sig": "(negative? n)", "zh": "是否为负数。", "en": "Is n negative?"},
    "even?":     {"sig": "(even? n)", "zh": "是否为偶数。", "en": "Is n even?"},
    "odd?":      {"sig": "(odd? n)", "zh": "是否为奇数。", "en": "Is n odd?"},
    "integer?":  {"sig": "(integer? n)", "zh": "是否为整数。", "en": "Is n an integer?"},

    # Builders
    "range":     {"sig": "(range start end)", "zh": "生成 [start, end) 的整数列表。", "en": "List of integers [start, end).", "example": "(range 0 5) ;=> (0 1 2 3 4)"},
    "iota":      {"sig": "(iota n)", "zh": "生成 [0, n) 的整数列表。", "en": "List of integers [0, n).", "example": "(iota 5) ;=> (0 1 2 3 4)"},
    "make-list": {"sig": "(make-list n val)", "zh": "创建 n 个 val 组成的列表。", "en": "List of n copies of val."},

    # List ops
    "last":    {"sig": "(last lst)", "zh": "列表最后一个元素。", "en": "Last element of a list."},
    "take":    {"sig": "(take lst n)", "zh": "取前 n 个元素。", "en": "First n elements."},
    "drop":    {"sig": "(drop lst n)", "zh": "跳过前 n 个元素。", "en": "Drop first n elements."},
    "zip":     {"sig": "(zip lst1 lst2)", "zh": "将两个列表逐项配对：((a1 b1) (a2 b2) ...)，以最短列表为准。", "en": "Pair up elements from two lists. Stops at shorter list."},
    "flatten": {"sig": "(flatten lst)", "zh": "展平嵌套列表（非尾递归，仅用于浅层嵌套）。", "en": "Flatten nested list (not tail-recursive, shallow nesting only)."},

    # Combinators
    "compose":  {"sig": "(compose f g)", "zh": "函数组合，先 g 后 f：等价于 (lambda (x) (f (g x)))。", "en": "Function composition: (compose f g) = f∘g."},
    "identity": {"sig": "(identity x)", "zh": "恒等函数，原样返回 x。", "en": "Identity function, returns x unchanged."},
    "const":    {"sig": "(const x)", "zh": "构造常量函数：始终返回 x，忽略所有参数。", "en": "Return a function that always returns x regardless of args."},
    "flip":     {"sig": "(flip f)", "zh": "翻转二元函数的参数顺序：(flip f a b) = (f b a)。", "en": "Swap argument order of a binary function."},

    # Alist helpers
    "assoc":     {"sig": "(assoc key alist)", "zh": "在关联表中查找 key，返回 (key . val) 点对，找不到返回 #f。", "en": "Look up key in alist, return (key . val) pair or #f."},
    "member":    {"sig": "(member x lst)", "zh": "在列表中查找 x，返回以 x 开头的尾部子列表，找不到返回 #f。", "en": "Find x in list, return tail starting at x, or #f."},
    "alist-ref": {"sig": "(alist-ref key alist default)", "zh": "查找关联表中的 key，找不到返回 default。", "en": "Look up key in alist, return default if not found."},
    "alist-set": {"sig": "(alist-set key val alist)", "zh": "在关联表中设置 key，返回新的关联表（不修改原表）。", "en": "Set key in alist, return new alist."},

    # String
    "string<?":    {"sig": "(string<? a b)", "zh": "字典序比较：a 是否在 b 之前（区分大小写）。", "en": "Lexicographic less-than comparison (case-sensitive)."},

    # Sorting
    "sort":      {"sig": "(sort lst less?)", "zh": "对列表排序，less? 为二元比较函数。底层为归并排序，尾递归安全。", "en": "Sort list using less? comparator. Uses bottom-up merge sort (stack-safe).", "example": "(sort '(3 1 2) <) ;=> (1 2 3)\n(sort '(\"b\" \"a\") string<?) ;=> (\"a\" \"b\")"},

    # I/O
    "displayln": {"sig": "(displayln x)", "zh": "输出值并换行，等价于 (display x)(newline)。", "en": "Display x then print a newline."},
}

# ── Core extras ────────────────────────────────────────────────

CORE_EXTRAS: dict[str, HelpEntry] = {
    "apropos":       {"sig": "(apropos pattern)", "zh": "在当前环境中搜索含指定子串的名称（不区分大小写），返回 (名称 . 类型) 列表。", "en": "Search env bindings by substring (case-insensitive), returns list of (name . type).", "example": '(apropos "struct")  ;=> (("struct-get" . "builtin") ...)'},
    "%self-test":    {"sig": "(%self-test)", "zh": "运行解释器冒烟测试。", "en": "Run interpreter smoke tests."},
}

# ── Stdlib (handle predicates, constructors, converters) ───────

STDLIB: dict[str, HelpEntry] = {
    "array?":         {"sig": "(array? x)", "zh": "是否为 GML 数组。", "en": "Is x a GML array?"},
    "struct?":        {"sig": "(struct? x)", "zh": "是否为 GML 结构体。", "en": "Is x a GML struct?"},
    "method?":        {"sig": "(method? x)", "zh": "是否为 GML 方法（method）。", "en": "Is x a GML method?"},
    "ds-map?":        {"sig": "(ds-map? n)", "zh": "是否为有效的 ds_map 句柄（存在误判风险，仅用于 REPL 探测）。", "en": "Is n a valid ds_map handle? (may false-positive, for REPL probing only)"},
    "ds-list?":       {"sig": "(ds-list? n)", "zh": "是否为有效的 ds_list 句柄（存在误判风险，仅用于 REPL 探测）。", "en": "Is n a valid ds_list handle? (may false-positive, for REPL probing only)"},
    "noone":          {"sig": "noone", "zh": "GML 空实例常量（值为 -4）。", "en": "GML null-instance constant (-4)."},
    "array":          {"sig": "(array arg ...)", "zh": "从参数创建 GML 数组（浅拷贝），等价于字面量 #[1 2 3]。", "en": "Create GML array from args (shallow). Sugar: #[1 2 3]", "example": "(array 1 2 3)  ;=> #[1 2 3]"},
    "struct":         {"sig": "(struct key val ...)", "zh": "从键值对创建 GML 结构体（浅拷贝），等价于字面量 #{\"a\" 1}。", "en": "Create GML struct from key-value pairs (shallow). Sugar: #{\"a\" 1}", "example": '(struct "name" "sword" "dmg" 10)'},
    "alist->struct":  {"sig": "(alist->struct alist)", "zh": "将 Scheme 关联表转换为 GML 结构体（浅拷贝）。", "en": "Create struct from alist pairs (shallow)."},
    "list->array":    {"sig": "(list->array lst)", "zh": "将 Scheme 列表转换为 GML 数组（浅拷贝）。", "en": "Convert Scheme list to GML array (shallow)."},
    "ds-list->list":  {"sig": "(ds-list->list id)", "zh": "将 GML ds_list 转换为 Scheme 列表（浅包装）。", "en": "Convert ds_list to Scheme list (shallow wrap)."},
    "array->list":    {"sig": "(array->list arr)", "zh": "将 GML 数组转换为 Scheme 列表（浅包装）。", "en": "Convert GML array to Scheme list (shallow wrap)."},
    "instance-keys":  {"sig": "(instance-keys id)", "zh": "返回实例的所有变量名列表。", "en": "Return list of all variable names of an instance.", "example": "(instance-keys (gml:self))"},
    "*pp-width*":         {"sig": "*pp-width*", "zh": "美化打印的行宽阈值（默认 80），超出阈值则折行显示列表。", "en": "Pretty-print line width threshold (default 80). Used for list inline heuristic."},
    "*pp-max-depth*":     {"sig": "*pp-max-depth*", "zh": "美化打印最大递归深度（默认 8），超出则显示 {...}。", "en": "Pretty-print max recursion depth (default 8). Deeper nodes shown as {...}."},
    "*pp-max-items*":     {"sig": "*pp-max-items*", "zh": "美化打印每层最多输出项数（默认 9999），超出则显示 ... (N more)。", "en": "Pretty-print max items per level (default 9999). Excess shown as '... (N more)'."},
    "pp":                 {"sig": "(pp obj)", "zh": "通用美化打印。递归展开 struct/array/list，不对数字做 GML 句柄探测（见 probe）。", "en": "Generic pretty-printer. Recursively expands struct/array/list. No GML handle probing (see probe).", "example": "(pp (struct \"a\" 1 \"b\" #[2 3]))"},
    "pp-struct":          {"sig": "(pp-struct obj)", "zh": "美化打印 GML 结构体（字段按字母序，支持嵌套和循环检测）。", "en": "Pretty-print a GML struct (fields sorted, nested, cycle-safe)."},
    "pp-array":           {"sig": "(pp-array obj)", "zh": "美化打印 GML 数组（带索引，支持嵌套和循环检测）。", "en": "Pretty-print a GML array (indexed, nested, cycle-safe)."},
    "pp-instance":        {"sig": "(pp-instance id)", "zh": "美化打印 GML 实例的所有变量（按字母序，显示对象名和实例 ID）。", "en": "Pretty-print all variables of a GML instance (sorted, shows object name and id)."},
    "pp-ds-map":          {"sig": "(pp-ds-map id)", "zh": "美化打印 ds_map 的所有键值对（键按字母序）。", "en": "Pretty-print all key-value pairs of a ds_map (keys sorted)."},
    "pp-ds-list":         {"sig": "(pp-ds-list id)", "zh": "美化打印 ds_list 的所有元素（带索引）。", "en": "Pretty-print all elements of a ds_list (indexed)."},
    "pp-object":          {"sig": "(pp-object idx)", "zh": "美化打印对象资产信息（sprite、父对象、实例数等）。", "en": "Pretty-print object asset info (sprite, parent, instance count, etc.)."},
    "pp-sprite":          {"sig": "(pp-sprite idx)", "zh": "美化打印精灵资产信息（尺寸、帧数、原点、碰撞框）。", "en": "Pretty-print sprite asset info (size, frames, origin, bbox)."},
    "pp-room":            {"sig": "(pp-room idx)", "zh": "美化打印房间资产信息。", "en": "Pretty-print room asset info."},
    "pp-script":          {"sig": "(pp-script idx)", "zh": "美化打印脚本资产信息。", "en": "Pretty-print script asset info."},
    "pp-sound":           {"sig": "(pp-sound idx)", "zh": "美化打印音效资产信息。", "en": "Pretty-print sound asset info."},
    "probe":              {"sig": "(probe obj)", "zh": "顶层美化打印入口。对数字自动探测 GML 类型（实例、ds_map、ds_list、以及对象/精灵/房间/脚本/音效索引）；其余同 pp。", "en": "Top-level pretty-print entry. Probes numbers for GML types (instance, ds_map, ds_list, asset indices); otherwise like pp.", "example": "(probe (gml:self))"},
    "log":                {"sig": "(log arg ...)", "zh": "向 GML 调试控制台输出 [scm] 前缀的多参数消息。", "en": "Write '[scm] ...' message to GML debug console (variadic).", "example": "(log \"hp=\" (instance-get player \"hp\"))"},
    "->": {
        "sig": "(-> x form ...)",
        "zh":  "前插管道宏：将 x 依次插入每个 form 的首个参数位置。",
        "en":  "Thread-first macro. Inserts x as first arg of each form.",
        "example": "(-> 5 (+ 3) (* 2))  ;=> (* (+ 5 3) 2) => 16",
    },
    "->>": {
        "sig": "(->> x form ...)",
        "zh":  "后插管道宏：将 x 依次插入每个 form 的最后一个参数位置。",
        "en":  "Thread-last macro. Inserts x as last arg of each form.",
        "example": "(->> '(1 2 3) (map (lambda (x) (* x x))) (filter odd?))  ;=> (1 9)",
    },
    "as->": {
        "sig": "(as-> expr name form ...)",
        "zh":  "命名占位管道宏：每步将当前值绑定到 name，可在 form 的任意位置引用。",
        "en":  "Thread with named placeholder. Binds result to name at each step.",
        "example": "(as-> 5 x (+ x 3) (* 2 x) (- 100 x))  ;=> 84",
    },
    "some->": {
        "sig": "(some-> x form ...)",
        "zh":  "带短路的前插管道宏：遇 noone 立即返回，用于安全的 GML 实例链式访问。",
        "en":  "Thread-first macro, short-circuits on noone. Safe instance chain access.",
        "example": '(some-> player (instance-get "target") (instance-get "hp"))  ;=> hp or noone',
    },
    "some->>": {
        "sig": "(some->> x form ...)",
        "zh":  "带短路的后插管道宏：遇 noone 立即返回，用于安全的 GML 实例链式访问。",
        "en":  "Thread-last macro, short-circuits on noone. Safe instance chain access.",
    },
    "instances-of": {
        "sig": "(instances-of obj)",
        "zh":  "返回指定对象类型的所有活跃实例 ID 列表，obj 可为名称字符串或数字索引。",
        "en":  "Return list of all active instance IDs for an object. obj: string name or numeric index.",
        "example": '(instances-of "o_enemy")  ;=> (100042 100043 ...)',
    },
    "partial": {
        "sig": "(partial f arg ...)",
        "zh":  "偏函数应用：预绑定前几个参数，返回等待剩余参数的新过程。",
        "en":  "Partial application: pre-apply leading args, return new procedure for the rest.",
        "example": "(define add1 (partial + 1))\n(add1 5)  ;=> 6",
    },
    "complement": {
        "sig": "(complement pred)",
        "zh":  "返回 pred 的逻辑取反版本：(complement f) 等价于 (lambda args (not (apply f args)))。",
        "en":  "Return the negation of pred. (complement f) = (lambda args (not (apply f args))).",
        "example": "(filter (complement zero?) '(0 1 2 0 3))  ;=> (1 2 3)",
    },
    "tap": {
        "sig": "(tap f x)",
        "zh":  "对 x 调用 f 产生副作用，然后原样返回 x。常用于在管道中插入调试输出。",
        "en":  "Call (f x) for side-effect, return x unchanged. Useful for debug in pipelines.",
        "example": "(-> 5 (tap print) (+ 1))  ;=> prints 5, returns 6",
    },
}

# ── Bridge (FFI) ───────────────────────────────────────────────

BRIDGE: dict[str, HelpEntry] = {
    "ffi:proc->method":   {"sig": "(ffi:proc->method proc)", "zh": "将 Scheme 过程转为 GML method。", "en": "Convert Scheme procedure to GML method."},
}

# ── GML Wrappers (user-facing, from codegen spec) ───────────────
# Skip internal ones: keyboard-*, draw-*, vk-*, display-*, clipboard-*

GML_WRAPPERS: dict[str, HelpEntry] = {
    # Instance variable access
    "gml:variable-instance-get":    {"sig": "(gml:variable-instance-get inst name)", "zh": "读取实例变量。", "en": "Read instance variable."},
    "gml:variable-instance-set":    {"sig": "(gml:variable-instance-set inst name val)", "zh": "设置实例变量。", "en": "Set instance variable."},
    "gml:variable-instance-exists": {"sig": "(gml:variable-instance-exists inst name)", "zh": "检查实例变量是否存在。", "en": "Check if instance variable exists."},

    # Global
    "gml:global":                 {"sig": "(gml:global)", "zh": "返回 global 作用域引用，可与 struct-keys/pp 等配合使用。", "en": "Return the global scope reference. Usable with struct-keys/pp.", "example": "(struct-keys (gml:global))"},

    # Global variable access
    "gml:variable-global-get":    {"sig": "(gml:variable-global-get name)", "zh": "读取全局变量。", "en": "Read global variable."},
    "gml:variable-global-set":    {"sig": "(gml:variable-global-set name val)", "zh": "设置全局变量。", "en": "Set global variable."},
    "gml:variable-global-exists": {"sig": "(gml:variable-global-exists name)", "zh": "检查全局变量是否存在。", "en": "Check if global variable exists."},

    # Struct access
    "gml:variable-struct-get":       {"sig": "(gml:variable-struct-get s name)", "zh": "读取结构体字段。", "en": "Read struct field."},
    "gml:variable-struct-set":       {"sig": "(gml:variable-struct-set s name val)", "zh": "设置结构体字段。", "en": "Set struct field."},
    "gml:variable-struct-exists":    {"sig": "(gml:variable-struct-exists s name)", "zh": "检查结构体字段是否存在。", "en": "Check if struct field exists."},
    "gml:variable-struct-get-names": {"sig": "(gml:variable-struct-get-names s)", "zh": "获取结构体所有字段名(数组)。", "en": "Get all struct field names (array)."},
    "gml:variable-instance-get-names": {"sig": "(gml:variable-instance-get-names id)", "zh": "获取实例所有变量名(数组)。", "en": "Get all instance variable names (array)."},

    # ds_map
    "gml:ds-map-find-value": {"sig": "(gml:ds-map-find-value map key)", "zh": "查找 ds_map 中 key 对应的值。", "en": "Look up value in ds_map."},
    "gml:ds-map-find-first": {"sig": "(gml:ds-map-find-first map)", "zh": "返回 ds_map 的第一个键（用于迭代），无键时返回 #f。", "en": "Return first key of ds_map for iteration, or #f if empty."},
    "gml:ds-map-find-next":  {"sig": "(gml:ds-map-find-next map key)", "zh": "返回 ds_map 中 key 的下一个键（用于迭代），到达末尾返回 #f。", "en": "Return next key after key in ds_map, or #f at end."},
    "gml:ds-map-set":        {"sig": "(gml:ds-map-set map key val)", "zh": "设置 ds_map 键值对。", "en": "Set key-value in ds_map."},
    "gml:ds-map-exists":     {"sig": "(gml:ds-map-exists map key)", "zh": "检查 ds_map 中 key 是否存在。", "en": "Check if key exists in ds_map."},
    "gml:ds-map-size":       {"sig": "(gml:ds-map-size map)", "zh": "ds_map 的条目数。", "en": "Size of ds_map."},
    "gml:ds-map-create":     {"sig": "(gml:ds-map-create)", "zh": "创建 ds_map（必须手动调用 gml:ds-map-destroy 释放！）。", "en": "Create ds_map (must destroy manually!)."},
    "gml:ds-map-destroy":    {"sig": "(gml:ds-map-destroy map)", "zh": "销毁 ds_map，释放内存。", "en": "Destroy ds_map, free memory."},
    "gml:ds-exists":         {"sig": "(gml:ds-exists id type)", "zh": "检查 ds 句柄是否存在，type 用 gml:ds-type-* 常量。", "en": "Check if a ds handle exists. Use gml:ds-type-* for type.", "example": "(gml:ds-exists m (gml:ds-type-map))"},
    "gml:ds-type-map":       {"sig": "(gml:ds-type-map)", "zh": "ds_map 类型常量，供 gml:ds-exists 使用。", "en": "ds_map type constant for gml:ds-exists."},
    "gml:ds-type-list":      {"sig": "(gml:ds-type-list)", "zh": "ds_list 类型常量，供 gml:ds-exists 使用。", "en": "ds_list type constant for gml:ds-exists."},
    "gml:ds-type-grid":      {"sig": "(gml:ds-type-grid)", "zh": "ds_grid 类型常量，供 gml:ds-exists 使用。", "en": "ds_grid type constant for gml:ds-exists."},

    # ds_list
    "gml:ds-list-create":     {"sig": "(gml:ds-list-create)", "zh": "创建 ds_list（必须手动调用 gml:ds-list-destroy 释放！）。", "en": "Create ds_list (must destroy manually!)."},
    "gml:ds-list-add":        {"sig": "(gml:ds-list-add list val)", "zh": "向 ds_list 追加元素。", "en": "Append value to ds_list."},
    "gml:ds-list-size":       {"sig": "(gml:ds-list-size list)", "zh": "ds_list 大小。", "en": "Size of ds_list."},
    "gml:ds-list-find-value": {"sig": "(gml:ds-list-find-value list idx)", "zh": "按索引读取 ds_list 元素。", "en": "Get ds_list element by index."},
    "gml:ds-list-destroy":    {"sig": "(gml:ds-list-destroy list)", "zh": "销毁 ds_list, 释放内存。", "en": "Destroy ds_list, free memory."},

    # Instance / object
    "gml:instance-find":   {"sig": "(gml:instance-find obj-idx n)", "zh": "查找指定对象的第 n 个实例。", "en": "Find nth instance of an object.", "example": '(gml:instance-find (gml:asset-get-index "o_player") 0)'},
    "gml:instance-number": {"sig": "(gml:instance-number obj-idx)", "zh": "指定对象的实例数量。", "en": "Count instances of an object."},
    "gml:instance-exists": {"sig": "(gml:instance-exists inst)", "zh": "实例是否存活。", "en": "Is instance alive?"},
    "gml:instance-create-depth": {"sig": "(gml:instance-create-depth x y depth obj-idx)", "zh": "在指定深度创建实例。", "en": "Create instance at depth.", "example": '(gml:instance-create-depth 100 100 0 (gml:asset-get-index "o_item"))'},
    "gml:instance-destroy": {"sig": "(gml:instance-destroy inst)", "zh": "销毁实例。", "en": "Destroy instance."},
    "gml:asset-get-index": {"sig": '(gml:asset-get-index "name")', "zh": "资产名称转索引。", "en": "Asset name to index.", "example": '(gml:asset-get-index "o_player")'},
    "gml:asset-get-type":  {"sig": '(gml:asset-get-type "name")', "zh": "获取资产类型。", "en": "Get asset type."},
    "script-execute":     {"sig": "(script-execute idx arg...)", "zh": "调用脚本(变参)。", "en": "Execute script by index (variadic).", "example": '(script-execute (scr:scr_damage) player 50)'},
    "gml:script-execute-ext": {"sig": "(gml:script-execute-ext idx args-array)", "zh": "调用脚本(数组传参)。", "en": "Execute script with array of args.", "example": '(gml:script-execute-ext (scr:scr_damage) #[player 50])'},
    "gml:script-exists":      {"sig": "(gml:script-exists idx)", "zh": "脚本是否存在。", "en": "Check if script exists."},
    "gml:script-get-name":    {"sig": "(gml:script-get-name idx)", "zh": "脚本索引转名称。", "en": "Script index to name."},

    # Object / sprite info
    "gml:object-get-name":       {"sig": "(gml:object-get-name obj-idx)", "zh": "对象索引转名称字符串。", "en": "Object index to name string."},
    "gml:object-get-sprite":     {"sig": "(gml:object-get-sprite obj-idx)", "zh": "获取对象默认精灵索引。", "en": "Get object's default sprite index."},
    "gml:object-get-parent":     {"sig": "(gml:object-get-parent obj-idx)", "zh": "获取对象的父对象索引，无父则返回 -1。", "en": "Get object's parent index, or -1 if none."},
    "gml:object-get-depth":      {"sig": "(gml:object-get-depth obj-idx)", "zh": "获取对象的默认深度值。", "en": "Get object's default depth."},
    "gml:object-get-mask":       {"sig": "(gml:object-get-mask obj-idx)", "zh": "获取对象的碰撞遮罩精灵索引，-1 表示与 sprite 相同。", "en": "Get object's collision mask sprite index (-1 = same as sprite)."},
    "gml:object-get-persistent": {"sig": "(gml:object-get-persistent obj-idx)", "zh": "对象是否为持久对象（跨房间保留）。", "en": "Is the object persistent (survives room changes)?"},
    "gml:object-get-visible":    {"sig": "(gml:object-get-visible obj-idx)", "zh": "对象默认是否可见。", "en": "Is the object visible by default?"},
    "gml:object-get-solid":      {"sig": "(gml:object-get-solid obj-idx)", "zh": "对象默认是否为实体（solid）。", "en": "Is the object solid by default?"},
    "gml:object-is-ancestor":    {"sig": "(gml:object-is-ancestor obj-idx parent-idx)", "zh": "检查 parent-idx 是否是 obj-idx 的祖先（继承链查询）。", "en": "Check if parent-idx is an ancestor of obj-idx."},
    "gml:sprite-get-name":       {"sig": "(gml:sprite-get-name spr-idx)", "zh": "精灵索引转名称字符串。", "en": "Sprite index to name string."},
    "gml:sprite-get-number":     {"sig": "(gml:sprite-get-number spr-idx)", "zh": "精灵的帧数。", "en": "Number of sprite frames."},
    "gml:sprite-get-width":      {"sig": "(gml:sprite-get-width spr-idx)", "zh": "精灵宽度（像素）。", "en": "Sprite width in pixels."},
    "gml:sprite-get-height":     {"sig": "(gml:sprite-get-height spr-idx)", "zh": "精灵高度（像素）。", "en": "Sprite height in pixels."},
    "gml:sprite-get-xoffset":    {"sig": "(gml:sprite-get-xoffset spr-idx)", "zh": "精灵原点 X 坐标。", "en": "Sprite origin X offset."},
    "gml:sprite-get-yoffset":    {"sig": "(gml:sprite-get-yoffset spr-idx)", "zh": "精灵原点 Y 坐标。", "en": "Sprite origin Y offset."},
    "gml:sprite-get-bbox-left":  {"sig": "(gml:sprite-get-bbox-left spr-idx)", "zh": "精灵碰撞框左边界。", "en": "Sprite bounding box left."},
    "gml:sprite-get-bbox-top":   {"sig": "(gml:sprite-get-bbox-top spr-idx)", "zh": "精灵碰撞框上边界。", "en": "Sprite bounding box top."},
    "gml:sprite-get-bbox-right": {"sig": "(gml:sprite-get-bbox-right spr-idx)", "zh": "精灵碰撞框右边界。", "en": "Sprite bounding box right."},
    "gml:sprite-get-bbox-bottom":{"sig": "(gml:sprite-get-bbox-bottom spr-idx)", "zh": "精灵碰撞框下边界。", "en": "Sprite bounding box bottom."},
    "gml:object-exists":         {"sig": "(gml:object-exists obj-idx)", "zh": "对象索引是否有效。", "en": "Is object index valid?"},
    "gml:sprite-exists":         {"sig": "(gml:sprite-exists spr-idx)", "zh": "精灵索引是否有效。", "en": "Is sprite index valid?"},
    "gml:room-exists":           {"sig": "(gml:room-exists rm-idx)", "zh": "房间索引是否有效。", "en": "Is room index valid?"},
    "gml:audio-exists":          {"sig": "(gml:audio-exists snd-idx)", "zh": "音效索引是否有效。", "en": "Is sound index valid?"},
    "gml:audio-get-name":        {"sig": "(gml:audio-get-name snd-idx)", "zh": "音效索引转名称字符串。", "en": "Sound index to name string."},

    # Array
    "gml:array-length": {"sig": "(gml:array-length arr)", "zh": "返回 GML 数组长度。", "en": "Array length."},
    "gml:array-get":    {"sig": "(gml:array-get arr idx)", "zh": "读取数组中索引 idx 处的元素（0-based）。", "en": "Get array element at index (0-based)."},
    "gml:array-set":    {"sig": "(gml:array-set arr idx val)", "zh": "设置数组中索引 idx 处的元素（0-based）。", "en": "Set array element at index (0-based)."},
    "gml:array-push":   {"sig": "(gml:array-push arr val)", "zh": "向数组末尾追加元素。", "en": "Append value to end of array."},
    "gml:array-create": {"sig": "(gml:array-create n)", "zh": "创建长度为 n 的数组（元素初始化为 0）。", "en": "Create array of size n (elements initialized to 0)."},
    "gml:array-copy":   {"sig": "(gml:array-copy arr)", "zh": "浅拷贝数组。", "en": "Shallow copy array."},
    "gml:array-sort":   {"sig": "(gml:array-sort arr ascending)", "zh": "原地排序 GML 字符串数组。ascending=#t 升序，#f 降序。", "en": "Sort GML string array in-place. ascending: #t for ascending, #f for descending."},
    "gml:struct-create":{"sig": "(gml:struct-create)", "zh": "创建空 GML 结构体（struct 构造函数的底层实现）。", "en": "Create an empty GML struct (low-level). Use struct instead."},

    # String (GML builtins)
    "gml:string-replace-all": {"sig": "(gml:string-replace-all s old new)", "zh": "将 s 中所有 old 替换为 new。", "en": "Replace all occurrences of old with new."},
    "gml:string-pos":         {"sig": "(gml:string-pos sub s)", "zh": "查找 sub 在 s 中首次出现的位置（1-based），未找到返回 0。", "en": "Find first occurrence of sub in s (1-based), 0 if not found."},
    "gml:string-lower":       {"sig": "(gml:string-lower s)", "zh": "转为全小写字符串（GML string_lower）。", "en": "Convert string to lowercase (GML string_lower)."},
    "gml:string-length":      {"sig": "(gml:string-length s)", "zh": "GML 原生字符串长度（与 string-length 相同）。", "en": "GML native string length (same as string-length)."},
    "gml:real":    {"sig": "(gml:real s)", "zh": "字符串转数值（GML real）。", "en": "Parse string to GML real."},
    "gml:string":  {"sig": "(gml:string x)", "zh": "任意值转字符串（GML string）。", "en": "Convert any value to string."},

    # Math (for the gml: prefixed versions users might search)
    "gml:clamp":        {"sig": "(gml:clamp val lo hi)", "zh": "将值限制到指定范围（同 clamp）。", "en": "Clamp value to range."},
    "gml:random-range":  {"sig": "(gml:random-range lo hi)", "zh": "范围内随机实数。", "en": "Random real in range."},
    "gml:irandom-range": {"sig": "(gml:irandom-range lo hi)", "zh": "范围内随机整数。", "en": "Random integer in range."},
    "gml:degtorad":      {"sig": "(gml:degtorad deg)", "zh": "角度转弧度。", "en": "Degrees to radians."},
    "gml:radtodeg":      {"sig": "(gml:radtodeg rad)", "zh": "弧度转角度。", "en": "Radians to degrees."},
    "gml:power":         {"sig": "(gml:power base exp)", "zh": "幂运算(GML power)。", "en": "Exponentiation (GML power)."},

    # State
    "gml:current-time":  {"sig": "(gml:current-time)", "zh": "当前时间(毫秒, 系统启动后)。", "en": "Current time (ms since OS boot)."},
    "gml:self":          {"sig": "(gml:self)", "zh": "当前实例 ID。", "en": "Current instance ID."},
    "gml:room":          {"sig": "(gml:room)", "zh": "当前房间索引。", "en": "Current room index."},
    "gml:room-get-name": {"sig": '(gml:room-get-name idx)', "zh": "房间索引转名称。", "en": "Room index to name string."},
    "gml:room-width":    {"sig": "(gml:room-width)", "zh": "当前房间宽度。", "en": "Current room width."},
    "gml:room-height":   {"sig": "(gml:room-height)", "zh": "当前房间高度。", "en": "Current room height."},
    "gml:room-goto":     {"sig": "(gml:room-goto idx)", "zh": "跳转到指定房间。", "en": "Go to room."},

    # ds_grid
    "gml:ds-grid-create":  {"sig": "(gml:ds-grid-create w h)", "zh": "创建 ds_grid(需手动 destroy!)。", "en": "Create ds_grid (must destroy!)."},
    "gml:ds-grid-destroy": {"sig": "(gml:ds-grid-destroy grid)", "zh": "销毁 ds_grid。", "en": "Destroy ds_grid."},
    "gml:ds-grid-get":     {"sig": "(gml:ds-grid-get grid x y)", "zh": "读取 ds_grid 单元格。", "en": "Read ds_grid cell."},
    "gml:ds-grid-set":     {"sig": "(gml:ds-grid-set grid x y val)", "zh": "设置 ds_grid 单元格。", "en": "Set ds_grid cell."},
    "gml:ds-grid-width":   {"sig": "(gml:ds-grid-width grid)", "zh": "ds_grid 宽度。", "en": "Width of ds_grid."},
    "gml:ds-grid-height":  {"sig": "(gml:ds-grid-height grid)", "zh": "ds_grid 高度。", "en": "Height of ds_grid."},

    # Type checks
    "gml:is-real":      {"sig": "(gml:is-real val)", "zh": "是否为 GML 实数。", "en": "Is GML real?"},
    "gml:is-string":    {"sig": "(gml:is-string val)", "zh": "是否为 GML 字符串。", "en": "Is GML string?"},
    "gml:is-array":     {"sig": "(gml:is-array val)", "zh": "是否为 GML 数组。", "en": "Is GML array?"},
    "gml:is-struct":    {"sig": "(gml:is-struct val)", "zh": "是否为 GML 结构体。", "en": "Is GML struct?"},
    "gml:is-undefined": {"sig": "(gml:is-undefined val)", "zh": "是否为 undefined。", "en": "Is undefined?"},
    "gml:is-method":    {"sig": "(gml:is-method val)", "zh": "是否为 GML method。", "en": "Is GML method?"},

    # JSON
    "gml:json-stringify": {"sig": "(gml:json-stringify val)", "zh": "值转 JSON 字符串。", "en": "Value to JSON string."},
    "gml:json-parse":     {"sig": '(gml:json-parse str)', "zh": "JSON 字符串解析为值。", "en": "Parse JSON string to value."},
    "gml:method":        {"sig": "(gml:method inst proc)", "zh": "将 Scheme 过程绑定到指定实例上下文，返回 GML method。", "en": "Bind Scheme procedure to instance context, return GML method."},
    "gml:show-debug-message": {"sig": "(gml:show-debug-message msg)", "zh": "向 GML 调试控制台输出消息。", "en": "Print message to GML debug console."},
}

# ── Aliases (prelude short names → canonical) ───────────────────

ALIASES: dict[str, HelpEntry] = {
    "instance-get":     {"sig": "(instance-get inst name)", "zh": "读取实例变量（gml:variable-instance-get 的简短别名）。", "en": "Read instance variable. Alias for gml:variable-instance-get."},
    "instance-set!":    {"sig": "(instance-set! inst name val)", "zh": "设置实例变量（gml:variable-instance-set 的简短别名）。", "en": "Set instance variable. Alias for gml:variable-instance-set."},
    "instance-exists?": {"sig": "(instance-exists? inst)", "zh": "实例是否存活（gml:instance-exists 的简短别名）。", "en": "Is instance alive? Alias for gml:instance-exists."},
    "global-get":       {"sig": "(global-get name)", "zh": "读取全局变量（gml:variable-global-get 的简短别名）。", "en": "Read global variable. Alias for gml:variable-global-get."},
    "global-set!":      {"sig": "(global-set! name val)", "zh": "设置全局变量（gml:variable-global-set 的简短别名）。", "en": "Set global variable. Alias for gml:variable-global-set."},
    "struct-get":       {"sig": "(struct-get s name)", "zh": "读取结构体字段（gml:variable-struct-get 的简短别名）。", "en": "Read struct field. Alias for gml:variable-struct-get."},
    "struct-set!":      {"sig": "(struct-set! s name val)", "zh": "设置结构体字段（gml:variable-struct-set 的简短别名）。", "en": "Set struct field. Alias for gml:variable-struct-set."},
    "struct-has?":      {"sig": "(struct-has? s name)", "zh": "检查结构体字段是否存在（gml:variable-struct-exists 的简短别名）。", "en": "Check struct field exists. Alias for gml:variable-struct-exists."},
    "array-ref":        {"sig": "(array-ref arr idx)", "zh": "读取数组元素（gml:array-get 的简短别名）。", "en": "Get array element. Alias for gml:array-get."},
    "array-set!":       {"sig": "(array-set! arr idx val)", "zh": "设置数组元素（gml:array-set 的简短别名）。", "en": "Set array element. Alias for gml:array-set."},
    "array-length":     {"sig": "(array-length arr)", "zh": "数组长度（gml:array-length 的简短别名）。", "en": "Array length. Alias for gml:array-length."},
    "array-create":     {"sig": "(array-create n)", "zh": "创建数组（gml:array-create 的简短别名）。", "en": "Create array. Alias for gml:array-create."},

    # Object info
    "object-exists?":    {"sig": "(object-exists? obj-idx)", "zh": "对象索引是否有效（gml:object-exists 的简短别名）。", "en": "Is object index valid? Alias for gml:object-exists."},
    "object-get-name":   {"sig": "(object-get-name obj-idx)", "zh": "对象索引转名称（gml:object-get-name 的简短别名）。", "en": "Object index to name. Alias for gml:object-get-name."},
    "object-get-sprite": {"sig": "(object-get-sprite obj-idx)", "zh": "获取对象默认精灵索引（gml:object-get-sprite 的简短别名）。", "en": "Get object's default sprite. Alias for gml:object-get-sprite."},
    "object-get-depth":  {"sig": "(object-get-depth obj-idx)", "zh": "获取对象默认深度（gml:object-get-depth 的简短别名）。", "en": "Get object's default depth. Alias for gml:object-get-depth."},
    "object-get-mask":   {"sig": "(object-get-mask obj-idx)", "zh": "获取对象碰撞遮罩精灵索引（gml:object-get-mask 的简短别名）。", "en": "Get object's collision mask sprite. Alias for gml:object-get-mask."},

    # Sprite info
    "sprite-exists?":       {"sig": "(sprite-exists? spr-idx)", "zh": "精灵索引是否有效（gml:sprite-exists 的简短别名）。", "en": "Is sprite index valid? Alias for gml:sprite-exists."},
    "sprite-get-name":      {"sig": "(sprite-get-name spr-idx)", "zh": "精灵索引转名称（gml:sprite-get-name 的简短别名）。", "en": "Sprite index to name. Alias for gml:sprite-get-name."},
    "sprite-get-width":     {"sig": "(sprite-get-width spr-idx)", "zh": "精灵宽度（gml:sprite-get-width 的简短别名）。", "en": "Sprite width. Alias for gml:sprite-get-width."},
    "sprite-get-height":    {"sig": "(sprite-get-height spr-idx)", "zh": "精灵高度（gml:sprite-get-height 的简短别名）。", "en": "Sprite height. Alias for gml:sprite-get-height."},
    "sprite-get-number":    {"sig": "(sprite-get-number spr-idx)", "zh": "精灵帧数（gml:sprite-get-number 的简短别名）。", "en": "Sprite frame count. Alias for gml:sprite-get-number."},

    # Room info
    "room-exists?":   {"sig": "(room-exists? rm-idx)", "zh": "房间索引是否有效（gml:room-exists 的简短别名）。", "en": "Is room index valid? Alias for gml:room-exists."},
    "room-get-name":  {"sig": "(room-get-name rm-idx)", "zh": "房间索引转名称（gml:room-get-name 的简短别名）。", "en": "Room index to name. Alias for gml:room-get-name."},

    # Script info
    "script-exists?":   {"sig": "(script-exists? idx)", "zh": "脚本索引是否有效（gml:script-exists 的简短别名）。", "en": "Is script index valid? Alias for gml:script-exists."},
    "script-get-name":  {"sig": "(script-get-name idx)", "zh": "脚本索引转名称（gml:script-get-name 的简短别名）。", "en": "Script index to name. Alias for gml:script-get-name."},

    # Sound info
    "sound-exists?":    {"sig": "(sound-exists? idx)", "zh": "音效索引是否有效（gml:audio-exists 的简短别名）。", "en": "Is sound index valid? Alias for gml:audio-exists."},
    "sound-get-name":   {"sig": "(sound-get-name idx)", "zh": "音效索引转名称（gml:audio-get-name 的简短别名）。", "en": "Sound index to name. Alias for gml:audio-get-name."},
    "ds-map-keys":   {"sig": "(ds-map-keys map)", "zh": "获取 ds_map 所有键，返回 Scheme 列表（遍历顺序不保证）。", "en": "Get all keys of ds_map as Scheme list (order not guaranteed)."},
    "ds-map-values": {"sig": "(ds-map-values map)", "zh": "获取 ds_map 所有值，返回 Scheme 列表（顺序与 ds-map-keys 对应）。", "en": "Get all values of ds_map as Scheme list (same order as ds-map-keys)."},
    "ds-map->alist": {"sig": "(ds-map->alist map)", "zh": "将 ds_map 转换为 Scheme 关联表 ((key . val) ...)。", "en": "Convert ds_map to alist ((key . val) ...)."},
    "alist->ds-map": {"sig": "(alist->ds-map alist)", "zh": "将 Scheme 关联表转换为 ds_map（必须手动 gml:ds-map-destroy 释放！）。", "en": "Create ds_map from alist (must destroy with gml:ds-map-destroy!)."},
    "list->ds-list": {"sig": "(list->ds-list lst)", "zh": "将 Scheme 列表转换为 ds_list（必须手动 gml:ds-list-destroy 释放！）。", "en": "Create ds_list from list (must destroy with gml:ds-list-destroy!)."},
    "struct-keys":   {"sig": "(struct-keys s)", "zh": "获取结构体所有字段名，返回 Scheme 字符串列表。", "en": "Get all struct field names as Scheme string list."},
    "struct-values": {"sig": "(struct-values s)", "zh": "获取结构体所有字段值，返回 Scheme 列表（顺序与 struct-keys 对应）。", "en": "Get all struct field values as Scheme list (same order as struct-keys)."},
    "struct->alist": {"sig": "(struct->alist s)", "zh": "将结构体转换为 Scheme 关联表 ((key . val) ...)。", "en": "Convert struct to alist ((key . val) ...)."},

    # Asset discovery (prelude: search-* with let-over-lambda + runtime GML)
    "search-names":     {"sig": '(search-names arr pattern)', "zh": "在 GML 字符串数组中按子串搜索（不区分大小写）。", "en": "Substring search in a GML string array (case-insensitive)."},
    "search-objects":   {"sig": '(search-objects pattern)', "zh": "按子串搜索对象名（从预缓存 objects.json 中查找）。", "en": "Search object names by substring.", "example": '(search-objects "enemy")'},
    "search-sprites":   {"sig": '(search-sprites pattern)', "zh": "按子串搜索精灵名（从预缓存 sprites.json 中查找）。", "en": "Search sprite names by substring.", "example": '(search-sprites "player")'},
    "search-sounds":    {"sig": '(search-sounds pattern)', "zh": "按子串搜索音效名（从预缓存 sounds.json 中查找）。", "en": "Search sound names by substring.", "example": '(search-sounds "hit")'},
    "search-rooms":     {"sig": '(search-rooms pattern)', "zh": "按子串搜索房间名（从预缓存 rooms.json 中查找）。", "en": "Search room names by substring.", "example": '(search-rooms "tavern")'},
    "search-functions": {"sig": '(search-functions pattern)', "zh": "按子串搜索 GML function 声明名，可用 fn:name 直接引用。", "en": "Search function declaration names. Use fn:name to reference.", "example": '(search-functions "damage")'},
    "search-scripts":   {"sig": '(search-scripts pattern)', "zh": "按子串搜索脚本资源名，可用 scr:name 获取 asset index。", "en": "Search script asset names. Use scr:name for asset index.", "example": '(search-scripts "damage")'},
    "object-parent":    {"sig": "(object-parent name-or-idx)", "zh": "返回父对象名称，无父则返回 #f（运行时 GML 查询）。", "en": "Return parent object name or #f (runtime GML query).", "example": '(object-parent "o_enemy_goblin")'},
    "object-children":  {"sig": "(object-children name)", "zh": "返回直接子对象名称列表（基于静态 obj_tree.json，加载时捕获）。", "en": "Return list of direct child object names (static metadata, captured at load).", "example": '(object-children "o_enemy")'},
    "object-ancestors": {"sig": "(object-ancestors name-or-idx)", "zh": "返回祖先对象名称链（从近到远），运行时 GML 查询。", "en": "Return ancestor chain, nearest first (runtime GML query).", "example": '(object-ancestors "o_enemy_goblin")'},
}

# ── REPL Chrome Strings ─────────────────────────────────────────

REPL_STRINGS: dict[str, dict[str, str]] = {
    "help_header":      {"zh": "REPL 命令:", "en": "REPL Commands:"},
    "help_cmd_help":    {"zh": "  :help           显示此帮助", "en": "  :help           Show this help"},
    "help_cmd_help_fn": {"zh": "  :help <name>    查看函数帮助", "en": "  :help <name>    Show help for a function"},
    "help_cmd_clear":   {"zh": "  :clear          清屏", "en": "  :clear          Clear output"},
    "help_cmd_env":     {"zh": "  :env [prefix]   列出环境绑定(可过滤)", "en": "  :env [prefix]   List env bindings (filter)"},
    "help_cmd_load":    {"zh": "  :load <path>    加载并执行 Scheme 文件", "en": "  :load <path>    Load and evaluate a Scheme file"},
    "help_cmd_tab":     {"zh": "  Tab             补全光标处符号", "en": "  Tab             Complete symbol at cursor"},
    "help_cmd_ctrl_l":  {"zh": "  Ctrl+L          清屏(快捷键)", "en": "  Ctrl+L          Clear output (shortcut)"},
    "help_cmd_ctrl_c":  {"zh": "  Ctrl+C          取消当前输入", "en": "  Ctrl+C          Cancel current input"},
    "help_cmd_ctrl_ae": {"zh": "  Ctrl+A/E        光标移至行首/行尾", "en": "  Ctrl+A/E        Cursor to beginning/end"},
    "unknown_cmd":      {"zh": "未知命令: {0} (试试 :help)", "en": "Unknown command: {0}  (try :help)"},
    "help_not_found":   {"zh": "未找到: {0} (试试 :env {0} 或 Tab 补全)", "en": "Not found: {0}  (try :env {0} or Tab)"},
    "load_usage":       {"zh": "用法: :load <path>", "en": "Usage: :load <path>"},
    "load_loading":     {"zh": "加载 {0} ...", "en": "Loading {0} ..."},
    "welcome_1":        {"zh": "Stoneshard Scheme REPL", "en": "Stoneshard Scheme REPL"},
    "welcome_hint":     {"zh": "  :help 命令帮助 | F1 切换 | Tab 补全 | Ctrl+L 清屏", "en": "  :help commands | F1 toggle | Tab complete | Ctrl+L clear"},
}


# ── Aggregation ─────────────────────────────────────────────────

def all_entries() -> dict[str, HelpEntry]:
    """Merge all help entries into a single dict (later dicts win on collision)."""
    merged: dict[str, HelpEntry] = {}
    for table in [SPECIAL_FORMS, CORE_BUILTINS, CORE_EXTRAS, PRELUDE, STDLIB, BRIDGE, GML_WRAPPERS, ALIASES]:
        merged.update(table)
    return merged


def get_locale_text(entry: HelpEntry, locale: str) -> str:
    """Get description text for a given locale, falling back to 'en'."""
    return entry.get(locale, entry.get("en", ""))


if __name__ == "__main__":
    entries = all_entries()
    print(f"Total help entries: {len(entries)}")
    for cat_name, cat in [
        ("Special Forms", SPECIAL_FORMS),
        ("Core Builtins", CORE_BUILTINS),
        ("Prelude", PRELUDE),
        ("Bridge", BRIDGE),
        ("GML Wrappers", GML_WRAPPERS),
        ("Aliases", ALIASES),
    ]:
        print(f"  {cat_name}: {len(cat)}")
