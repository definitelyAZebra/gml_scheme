"""help_db.py — Help text database for gml_scheme REPL.

Each entry: name → {sig, zh, en, example?}
  sig:     Calling signature (code, never translated)
  zh/en:   One-line description
  example: Optional usage example (code, never translated)

Categories:
  SPECIAL_FORMS   — language keywords (define, lambda, etc.)
  CORE_BUILTINS   — procedures implemented in scm_core.gml
  PRELUDE         — procedures defined in prelude.scm
  BRIDGE          — hand-written bridge functions (scm_bridge.gml)
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
    "car":      {"sig": "(car pair)", "zh": "取点对的第一个元素。", "en": "First element of a pair."},
    "cdr":      {"sig": "(cdr pair)", "zh": "取点对的第二个元素(列表的尾部)。", "en": "Second element (tail of list)."},
    "set-car!": {"sig": "(set-car! pair val)", "zh": "修改点对的 car。", "en": "Mutate the car of a pair."},
    "set-cdr!": {"sig": "(set-cdr! pair val)", "zh": "修改点对的 cdr。", "en": "Mutate the cdr of a pair."},
    "list":     {"sig": "(list a b ...)", "zh": "创建列表。", "en": "Create a list from arguments.", "example": "(list 1 2 3) ;=> (1 2 3)"},
    "length":   {"sig": "(length lst)", "zh": "列表长度。", "en": "Length of a list."},
    "reverse":  {"sig": "(reverse lst)", "zh": "反转列表。", "en": "Reverse a list."},
    "append":   {"sig": "(append lst ...)", "zh": "拼接多个列表。", "en": "Concatenate lists."},
    "list-ref": {"sig": "(list-ref lst n)", "zh": "取列表第 n 个元素(0-based)。", "en": "Get nth element (0-based)."},
    "list-tail": {"sig": "(list-tail lst n)", "zh": "跳过前 n 个元素。", "en": "Skip first n elements."},

    # String
    "string-length":    {"sig": "(string-length s)", "zh": "字符串长度。", "en": "Length of a string."},
    "string-ref":       {"sig": "(string-ref s n)", "zh": "取第 n 个字符(1-based, GML 规则)。", "en": "Character at position n (1-based, GML convention)."},
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
    "display": {"sig": "(display x)", "zh": "输出值(人类可读格式)。", "en": "Print value (human-readable)."},
    "write":   {"sig": "(write x)", "zh": "输出值(机器可读格式, 字符串带引号)。", "en": "Print value (machine-readable, strings quoted)."},
    "print":   {"sig": "(print x)", "zh": "输出值并换行。", "en": "Print value followed by newline."},
    "newline": {"sig": "(newline)", "zh": "输出换行。", "en": "Print a newline."},

    # Misc
    "apply": {"sig": "(apply proc args)", "zh": "将列表 args 展开为参数调用 proc。", "en": "Call proc with args list as arguments.", "example": "(apply + '(1 2 3)) ;=> 6"},
    "error": {"sig": '(error "msg")', "zh": "抛出错误。", "en": "Raise an error."},
    "void":  {"sig": "(void)", "zh": "返回 void 值(无有意义的返回值)。", "en": "Return the void value."},
    "gensym": {"sig": "(gensym)", "zh": "生成唯一符号。", "en": "Generate a unique symbol."},
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
    "sign":    {"sig": "(sign n)", "zh": "符号函数: -1/0/1。", "en": "Sign: -1, 0, or 1."},
    "clamp":   {"sig": "(clamp val lo hi)", "zh": "钳制值到 [lo, hi] 范围。", "en": "Clamp value to [lo, hi]."},
    "sin":     {"sig": "(sin rad)", "zh": "正弦(弧度)。", "en": "Sine (radians)."},
    "cos":     {"sig": "(cos rad)", "zh": "余弦(弧度)。", "en": "Cosine (radians)."},
    "random":  {"sig": "(random n)", "zh": "0 到 n 之间的随机实数。", "en": "Random real in [0, n)."},
    "irandom": {"sig": "(irandom n)", "zh": "0 到 n 之间的随机整数。", "en": "Random integer in [0, n]."},
    "lerp":    {"sig": "(lerp a b t)", "zh": "线性插值: a + t*(b-a)。", "en": "Linear interpolation: a + t*(b-a)."},

    # List accessors
    "cadr":  {"sig": "(cadr x)", "zh": "(car (cdr x)), 取第二个元素。", "en": "(car (cdr x)), second element."},
    "caddr": {"sig": "(caddr x)", "zh": "(car (cdr (cdr x))), 取第三个元素。", "en": "Third element."},

    # Higher-order
    "map":       {"sig": "(map f lst)", "zh": "对每个元素调用 f, 返回结果列表。", "en": "Apply f to each element, return results.", "example": "(map (lambda (x) (* x x)) '(1 2 3)) ;=> (1 4 9)"},
    "filter":    {"sig": "(filter pred lst)", "zh": "保留满足 pred 的元素。", "en": "Keep elements satisfying pred.", "example": "(filter even? '(1 2 3 4)) ;=> (2 4)"},
    "remove":    {"sig": "(remove pred lst)", "zh": "移除满足 pred 的元素(filter 的反面)。", "en": "Remove elements satisfying pred."},
    "for-each":  {"sig": "(for-each f lst)", "zh": "对每个元素调用 f(忽略返回值)。", "en": "Call f on each element for side effects."},
    "foldl":     {"sig": "(foldl f init lst)", "zh": "左折叠: f 签名 (elem acc) -> acc。", "en": "Left fold: f signature (elem acc) -> acc.", "example": "(foldl + 0 '(1 2 3)) ;=> 6"},
    "foldr":     {"sig": "(foldr f init lst)", "zh": "右折叠(非尾递归, 短列表使用)。", "en": "Right fold (not tail-recursive, use on short lists)."},
    "append-map": {"sig": "(append-map f lst)", "zh": "map 后 append 结果。", "en": "Map then concatenate results."},
    "any":       {"sig": "(any pred lst)", "zh": "是否存在元素满足 pred。", "en": "Does any element satisfy pred?"},
    "every":     {"sig": "(every pred lst)", "zh": "是否所有元素满足 pred。", "en": "Do all elements satisfy pred?"},
    "find":      {"sig": "(find pred lst)", "zh": "返回第一个满足 pred 的元素, 或 #f。", "en": "First element satisfying pred, or #f."},
    "count":     {"sig": "(count pred lst)", "zh": "满足 pred 的元素个数。", "en": "Count elements satisfying pred."},
    "partition": {"sig": "(partition pred lst)", "zh": "按 pred 分成两组: (满足 . 不满足)。", "en": "Split into (matching . non-matching).", "example": "(partition even? '(1 2 3 4)) ;=> ((2 4) 1 3)"},

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
    "zip":     {"sig": "(zip lst1 lst2)", "zh": "配对合并: ((a1 b1) (a2 b2) ...)。", "en": "Pair up elements from two lists."},
    "flatten": {"sig": "(flatten lst)", "zh": "扁平化嵌套列表(浅层使用)。", "en": "Flatten nested list (shallow nesting only)."},

    # Combinators
    "compose":  {"sig": "(compose f g)", "zh": "函数组合: (compose f g) => (lambda (x) (f (g x)))。", "en": "Function composition."},
    "identity": {"sig": "(identity x)", "zh": "恒等函数, 返回 x 本身。", "en": "Identity function, returns x."},
    "const":    {"sig": "(const x)", "zh": "返回一个永远返回 x 的函数。", "en": "Return a function that always returns x."},
    "flip":     {"sig": "(flip f)", "zh": "交换二元函数的参数顺序。", "en": "Swap argument order of a binary function."},

    # Alist helpers
    "assoc":     {"sig": "(assoc key alist)", "zh": "在关联表中查找 key, 返回 (key . val) 或 #f。", "en": "Look up key in alist, return (key . val) or #f."},
    "member":    {"sig": "(member x lst)", "zh": "查找 x, 返回从 x 开始的子列表, 或 #f。", "en": "Find x in list, return tail starting at x, or #f."},
    "alist-ref": {"sig": "(alist-ref key alist default)", "zh": "查找 key, 找不到返回 default。", "en": "Look up key in alist, return default if not found."},
    "alist-set": {"sig": "(alist-set key val alist)", "zh": "设置 key 的值, 返回新 alist。", "en": "Set key in alist, return new alist."},
}

# ── Bridge (scm_bridge.gml) ────────────────────────────────────

BRIDGE: dict[str, HelpEntry] = {
    "typeof":    {"sig": "(typeof val)", "zh": "返回值的类型名(字符串)。", "en": "Return type name as string.", "example": '(typeof 42) ;=> "number"'},
    "debug-log": {"sig": "(debug-log arg ...)", "zh": "输出到 GML 调试控制台(可变参数)。", "en": "Print to GML debug console (variadic)."},
    "handle?":   {"sig": "(handle? x)", "zh": "是否为 GML handle(数组/结构体/方法)。", "en": "Is x a GML handle?"},
    "array?":    {"sig": "(array? x)", "zh": "是否为 GML 数组。", "en": "Is x a GML array?"},
    "struct?":   {"sig": "(struct? x)", "zh": "是否为 GML 结构体。", "en": "Is x a GML struct?"},
    "method?":   {"sig": "(method? x)", "zh": "是否为 GML method。", "en": "Is x a GML method?"},
    "make-struct":    {"sig": "(make-struct)", "zh": "创建空 GML 结构体 {}。", "en": "Create an empty GML struct {}."},
    "array":          {"sig": "(array arg ...)", "zh": "从参数创建 GML 数组。语法糖: #[1 2 3]", "en": "Create GML array from args. Sugar: #[1 2 3]", "example": "(array 1 2 3)  ;=> #[1 2 3]"},
    "struct":         {"sig": "(struct key val ...)", "zh": "从键值对创建 GML 结构体。语法糖: #{\"a\" 1 \"b\" 2}", "en": "Create GML struct from key-value pairs. Sugar: #{\"a\" 1}", "example": '(struct "name" "sword" "dmg" 10)'},
    "alist->struct":  {"sig": "(alist->struct alist)", "zh": "从关联表创建结构体。", "en": "Create struct from alist pairs."},
    "ds-list->list":  {"sig": "(ds-list->list id)", "zh": "将 ds_list 转为 Scheme 列表。", "en": "Convert ds_list to Scheme list."},
    "array->list":    {"sig": "(array->list arr)", "zh": "将 GML 数组转为 Scheme 列表。", "en": "Convert GML array to Scheme list."},
    "list->array":    {"sig": "(list->array lst)", "zh": "将 Scheme 列表转为 GML 数组。", "en": "Convert Scheme list to GML array."},
    "proc->method":   {"sig": "(proc->method proc)", "zh": "将 Scheme 过程转为 GML method。", "en": "Convert Scheme procedure to GML method."},
    "self-test":      {"sig": "(self-test)", "zh": "运行解释器冒烟测试。", "en": "Run interpreter smoke tests."},
    "instance-keys":  {"sig": "(instance-keys id)", "zh": "返回实例的所有变量名列表。", "en": "Return list of all variable names of an instance.", "example": "(instance-keys (gml:self))"},
    "env-find":       {"sig": "(env-find pattern)", "zh": "子串搜索环境绑定，返回 (name . type) 对列表。", "en": "Search env bindings by substring, returns list of (name . type).", "example": '(env-find "struct")  ;=> (("struct-get" . "builtin") ...)'},
    "inspect":        {"sig": "(inspect obj)", "zh": "打印结构体或实例的所有字段名和值。", "en": "Print all field names and values of a struct or instance.", "example": "(inspect (gml:self))"},
}

# ── GML Wrappers (user-facing, from codegen spec) ───────────────
# Skip internal ones: keyboard-*, draw-*, vk-*, display-*, clipboard-*

GML_WRAPPERS: dict[str, HelpEntry] = {
    # Instance variable access
    "gml:variable-instance-get":    {"sig": "(gml:variable-instance-get inst name)", "zh": "读取实例变量。", "en": "Read instance variable."},
    "gml:variable-instance-set":    {"sig": "(gml:variable-instance-set inst name val)", "zh": "设置实例变量。", "en": "Set instance variable."},
    "gml:variable-instance-exists": {"sig": "(gml:variable-instance-exists inst name)", "zh": "检查实例变量是否存在。", "en": "Check if instance variable exists."},

    # Global
    "gml:global":                 {"sig": "(gml:global)", "zh": "返回 global 引用，可用于 struct-keys / inspect 等。", "en": "Return the global scope reference. Usable with struct-keys/inspect.", "example": "(struct-keys (gml:global))"},

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
    "gml:ds-map-find-value": {"sig": "(gml:ds-map-find-value map key)", "zh": "查找 ds_map 中的值。", "en": "Look up value in ds_map."},
    "gml:ds-map-set":        {"sig": "(gml:ds-map-set map key val)", "zh": "设置 ds_map 键值对。", "en": "Set key-value in ds_map."},
    "gml:ds-map-exists":     {"sig": "(gml:ds-map-exists map key)", "zh": "检查 ds_map 中 key 是否存在。", "en": "Check if key exists in ds_map."},
    "gml:ds-map-size":       {"sig": "(gml:ds-map-size map)", "zh": "ds_map 大小。", "en": "Size of ds_map."},
    "gml:ds-map-create":     {"sig": "(gml:ds-map-create)", "zh": "创建 ds_map(需手动 destroy!)。", "en": "Create ds_map (must destroy manually!)."},
    "gml:ds-map-destroy":    {"sig": "(gml:ds-map-destroy map)", "zh": "销毁 ds_map, 释放内存。", "en": "Destroy ds_map, free memory."},

    # ds_list
    "gml:ds-list-create":     {"sig": "(gml:ds-list-create)", "zh": "创建 ds_list(需手动 destroy!)。", "en": "Create ds_list (must destroy manually!)."},
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
    "gml:script-execute":     {"sig": "(gml:script-execute idx arg...)", "zh": "调用脚本(变参)。", "en": "Execute script by index (variadic).", "example": '(gml:script-execute (scr:scr_damage) player 50)'},
    "gml:script-execute-ext": {"sig": "(gml:script-execute-ext idx args-array)", "zh": "调用脚本(数组传参)。", "en": "Execute script with array of args.", "example": '(gml:script-execute-ext (scr:scr_damage) #[player 50])'},
    "gml:script-exists":      {"sig": "(gml:script-exists idx)", "zh": "脚本是否存在。", "en": "Check if script exists."},
    "gml:script-get-name":    {"sig": "(gml:script-get-name idx)", "zh": "脚本索引转名称。", "en": "Script index to name."},

    # Object / sprite info
    "gml:object-get-name":   {"sig": "(gml:object-get-name obj-idx)", "zh": "对象索引转名称。", "en": "Object index to name."},
    "gml:object-get-sprite": {"sig": "(gml:object-get-sprite obj-idx)", "zh": "获取对象默认 sprite。", "en": "Get object's default sprite."},
    "gml:object-get-parent": {"sig": "(gml:object-get-parent obj-idx)", "zh": "获取对象的父对象。", "en": "Get object's parent."},
    "gml:object-is-ancestor":{"sig": "(gml:object-is-ancestor obj-idx parent-idx)", "zh": "检查继承关系。", "en": "Check inheritance."},
    "gml:sprite-get-name":   {"sig": "(gml:sprite-get-name spr-idx)", "zh": "精灵索引转名称。", "en": "Sprite index to name."},
    "gml:sprite-get-number": {"sig": "(gml:sprite-get-number spr-idx)", "zh": "精灵帧数。", "en": "Number of sprite frames."},
    "gml:sprite-get-width":  {"sig": "(gml:sprite-get-width spr-idx)", "zh": "精灵宽度。", "en": "Sprite width."},
    "gml:sprite-get-height": {"sig": "(gml:sprite-get-height spr-idx)", "zh": "精灵高度。", "en": "Sprite height."},
    "gml:object-exists":     {"sig": "(gml:object-exists obj-idx)", "zh": "对象索引是否有效。", "en": "Is object index valid?"},
    "gml:sprite-exists":     {"sig": "(gml:sprite-exists spr-idx)", "zh": "精灵索引是否有效。", "en": "Is sprite index valid?"},
    "gml:room-exists":       {"sig": "(gml:room-exists rm-idx)", "zh": "房间索引是否有效。", "en": "Is room index valid?"},

    # Array
    "gml:array-length": {"sig": "(gml:array-length arr)", "zh": "数组长度。", "en": "Array length."},
    "gml:array-get":    {"sig": "(gml:array-get arr idx)", "zh": "读取数组元素。", "en": "Get array element."},
    "gml:array-set":    {"sig": "(gml:array-set arr idx val)", "zh": "设置数组元素。", "en": "Set array element."},
    "gml:array-push":   {"sig": "(gml:array-push arr val)", "zh": "向数组追加元素。", "en": "Append value to array."},
    "gml:array-create": {"sig": "(gml:array-create n)", "zh": "创建长度为 n 的数组。", "en": "Create array of size n."},
    "gml:array-copy":   {"sig": "(gml:array-copy arr)", "zh": "浅拷贝数组。", "en": "Shallow copy array."},

    # String (GML builtins)
    "gml:string-replace-all": {"sig": "(gml:string-replace-all s old new)", "zh": "替换所有匹配子串。", "en": "Replace all occurrences of old with new."},
    "gml:real":    {"sig": "(gml:real s)", "zh": "字符串转数值(GML real)。", "en": "Parse string to GML real."},
    "gml:string":  {"sig": "(gml:string x)", "zh": "任意值转字符串(GML string)。", "en": "Convert any value to string."},

    # Math (for the gml: prefixed versions users might search)
    "gml:clamp":        {"sig": "(gml:clamp val lo hi)", "zh": "钳制值到范围。", "en": "Clamp value to range."},
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
    "gml:method":        {"sig": "(gml:method inst proc)", "zh": "将 proc 绑定到 inst 上下文。", "en": "Bind proc to instance context."},
    "gml:show-debug-message": {"sig": "(gml:show-debug-message msg)", "zh": "输出到 GML 调试控制台。", "en": "Print to GML debug console."},
}

# ── Aliases (prelude short names → canonical) ───────────────────

ALIASES: dict[str, HelpEntry] = {
    "instance-get":     {"sig": "(instance-get inst name)", "zh": "读取实例变量。gml:variable-instance-get 的别名。", "en": "Read instance variable. Alias for gml:variable-instance-get."},
    "instance-set!":    {"sig": "(instance-set! inst name val)", "zh": "设置实例变量。gml:variable-instance-set 的别名。", "en": "Set instance variable. Alias for gml:variable-instance-set."},
    "instance-exists?": {"sig": "(instance-exists? inst)", "zh": "实例是否存活。gml:instance-exists 的别名。", "en": "Is instance alive? Alias for gml:instance-exists."},
    "global-get":       {"sig": "(global-get name)", "zh": "读取全局变量。gml:variable-global-get 的别名。", "en": "Read global variable. Alias for gml:variable-global-get."},
    "global-set!":      {"sig": "(global-set! name val)", "zh": "设置全局变量。gml:variable-global-set 的别名。", "en": "Set global variable. Alias for gml:variable-global-set."},
    "struct-get":       {"sig": "(struct-get s name)", "zh": "读取结构体字段。gml:variable-struct-get 的别名。", "en": "Read struct field. Alias for gml:variable-struct-get."},
    "struct-set!":      {"sig": "(struct-set! s name val)", "zh": "设置结构体字段。gml:variable-struct-set 的别名。", "en": "Set struct field. Alias for gml:variable-struct-set."},
    "struct-has?":      {"sig": "(struct-has? s name)", "zh": "检查结构体字段。gml:variable-struct-exists 的别名。", "en": "Check struct field. Alias for gml:variable-struct-exists."},
    "array-ref":        {"sig": "(array-ref arr idx)", "zh": "读取数组元素。gml:array-get 的别名。", "en": "Get array element. Alias for gml:array-get."},
    "array-set!":       {"sig": "(array-set! arr idx val)", "zh": "设置数组元素。gml:array-set 的别名。", "en": "Set array element. Alias for gml:array-set."},
    "array-length":     {"sig": "(array-length arr)", "zh": "数组长度。gml:array-length 的别名。", "en": "Array length. Alias for gml:array-length."},
    "array-create":     {"sig": "(array-create n)", "zh": "创建数组。gml:array-create 的别名。", "en": "Create array. Alias for gml:array-create."},

    # Prelude bridge helpers
    "ds-map-keys":   {"sig": "(ds-map-keys map)", "zh": "获取 ds_map 所有键(列表)。", "en": "Get all keys of ds_map as list."},
    "ds-map-values": {"sig": "(ds-map-values map)", "zh": "获取 ds_map 所有值(列表)。", "en": "Get all values of ds_map as list."},
    "ds-map->alist": {"sig": "(ds-map->alist map)", "zh": "ds_map 转关联表。", "en": "Convert ds_map to alist."},
    "alist->ds-map": {"sig": "(alist->ds-map alist)", "zh": "关联表转 ds_map(需手动 destroy!)。", "en": "Create ds_map from alist (must destroy!)."},
    "list->ds-list": {"sig": "(list->ds-list lst)", "zh": "列表转 ds_list(需手动 destroy!)。", "en": "Create ds_list from list (must destroy!)."},
    "struct-keys":   {"sig": "(struct-keys s)", "zh": "获取结构体所有字段名(列表)。", "en": "Get all struct field names as list."},
    "struct-values": {"sig": "(struct-values s)", "zh": "获取结构体所有字段值(列表)。", "en": "Get all struct field values as list."},
    "struct->alist": {"sig": "(struct->alist s)", "zh": "结构体转关联表。", "en": "Convert struct to alist."},

    # Asset discovery (prelude: *xxx* handles + search-names + runtime GML)
    "*objects*":        {"sig": "*objects*", "zh": "所有对象名的 GML 数组(handle)。", "en": "GML array handle of all object names."},
    "*sprites*":        {"sig": "*sprites*", "zh": "所有精灵名的 GML 数组(handle)。", "en": "GML array handle of all sprite names."},
    "*sounds*":         {"sig": "*sounds*", "zh": "所有音效名的 GML 数组(handle)。", "en": "GML array handle of all sound names."},
    "*rooms*":          {"sig": "*rooms*", "zh": "所有房间名的 GML 数组(handle)。", "en": "GML array handle of all room names."},
    "*functions*":      {"sig": "*functions*", "zh": "所有 function 声明名的 GML 数组(handle)。可通过 fn:name 直接引用。", "en": "GML array handle of function(){} declaration names. Reference via fn:name."},
    "*scripts*":        {"sig": "*scripts*", "zh": "所有脚本资源名的 GML 数组(handle)。通过 scr:name 获取 asset index。", "en": "GML array handle of script asset names. Use scr:name to get asset index."},
    "*obj-tree*":       {"sig": "*obj-tree*", "zh": "对象继承树 struct(handle): 父名→子名数组。", "en": "Object tree struct handle: parent name → array of child names."},
    "search-names":     {"sig": '(search-names arr pattern)', "zh": "在 GML 数组中子串搜索(不区分大小写)。", "en": "Substring search in a GML string array (case-insensitive)."},
    "objects":          {"sig": '(objects pattern)', "zh": "搜索对象名(子串匹配)。", "en": "Search object names by substring.", "example": '(objects "enemy")'},
    "sprites":          {"sig": '(sprites pattern)', "zh": "搜索精灵名(子串匹配)。", "en": "Search sprite names by substring.", "example": '(sprites "player")'},
    "sounds":           {"sig": '(sounds pattern)', "zh": "搜索音效名(子串匹配)。", "en": "Search sound names by substring.", "example": '(sounds "hit")'},
    "rooms":            {"sig": '(rooms pattern)', "zh": "搜索房间名(子串匹配)。", "en": "Search room names by substring.", "example": '(rooms "tavern")'},
    "functions":        {"sig": '(functions pattern)', "zh": "搜索 function 声明名(子串匹配)。fn:name 可直接引用。", "en": "Search function declaration names. Use fn:name to reference.", "example": '(functions "damage")'},
    "scripts":          {"sig": '(scripts pattern)', "zh": "搜索脚本资源名(子串匹配)。scr:name 获取 asset index。", "en": "Search script asset names. Use scr:name for asset index.", "example": '(scripts "damage")'},
    "object-parent":    {"sig": "(object-parent name-or-idx)", "zh": "返回父对象名或 #f (运行时GML查询)。", "en": "Return parent object name or #f (runtime GML query).", "example": '(object-parent "o_enemy_goblin")'},
    "object-children":  {"sig": "(object-children name)", "zh": "返回直接子对象名列表(静态元数据)。", "en": "Return list of direct child object names (static metadata)."},
    "object-ancestors": {"sig": "(object-ancestors name-or-idx)", "zh": "返回祖先链(近→远, 运行时GML查询)。", "en": "Return ancestor chain, nearest first (runtime GML query).", "example": '(object-ancestors "o_enemy_goblin")'},
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
    for table in [SPECIAL_FORMS, CORE_BUILTINS, PRELUDE, BRIDGE, GML_WRAPPERS, ALIASES]:
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
