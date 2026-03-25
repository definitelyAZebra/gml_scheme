# GML Scheme REPL 快速指南

> 面向有编程经验但不了解 Scheme 的 Stoneshard 玩家/模组开发者。

## 目录

- [什么是这个 REPL？](#什么是这个-repl)
- [5 分钟入门](#5-分钟入门)
- [Scheme 语法速成](#scheme-语法速成)
- [数据类型](#数据类型)
- [变量与函数](#变量与函数)
- [控制流](#控制流)
- [列表 — Scheme 的核心数据结构](#列表--scheme-的核心数据结构)
- [高阶函数](#高阶函数)
- [字符串操作](#字符串操作)
- [与游戏互动 — Bridge API](#与游戏互动--bridge-api)
- [资产搜索](#资产搜索)
- [Pretty Printer 与调试](#pretty-printer-与调试)
- [线程宏 (Threading Macros)](#线程宏-threading-macros)
- [REPL 技巧](#repl-技巧)
- [实战示例](#实战示例)
- [Cheatsheet](#cheatsheet)
- [常见陷阱](#常见陷阱)

---

## 什么是这个 REPL？

这是一个嵌入在 Stoneshard 游戏内的 **Scheme 语言解释器 + 交互式终端 (REPL)**。你可以在游戏运行时：

- 实时读取/修改玩家属性（HP、力量、金币等）
- 查看敌人数据、搜索游戏资产
- 测试数值公式、批量修改变量
- 用管道式操作组合复杂的查询

按 **F1** 打开/关闭 REPL。输入表达式后按 **Enter** 执行。使用 **Tab** 补全函数名。

---

## 5 分钟入门

```scheme
;; 1. 基本算术 — 前缀表达式：(操作符 参数1 参数2 ...)
(+ 1 2 3)           ;=> 6
(* 5 (+ 2 3))       ;=> 25
(/ 100 3)           ;=> 33.33...

;; 2. 定义变量
(define hp 100)
hp                   ;=> 100

;; 3. 定义函数
(define (double x) (* x 2))
(double 21)          ;=> 42

;; 4. 获取玩家实例
(define player (gml:instance-find (gml:asset-get-index "o_player") 0))

;; 5. 读取玩家属性
(instance-get player "hp")       ;=> 当前HP
(instance-get player "STR")      ;=> 力量值

;; 6. 修改玩家属性
(instance-set! player "hp" 999)

;; 7. 搜索游戏对象
(search-objects "wolf")          ;=> ("o_wolf" "o_wolf_alpha" ...)
```

**就这样！** 你已经掌握了 80% 的日常用法。下面深入学习每个部分。

---

## Scheme 语法速成

### 核心规则：一切都是 `(函数 参数 ...)`

| 你习惯的写法 (GML/JS/Python) | Scheme 写法 | 说明 |
|------|------|------|
| `1 + 2` | `(+ 1 2)` | 前缀表达式 |
| `max(a, b)` | `(max a b)` | 函数调用 |
| `a > 0 && b < 10` | `(and (> a 0) (< b 10))` | 逻辑运算 |
| `x = 42` | `(define x 42)` | 变量定义 |
| `x = x + 1` | `(set! x (+ x 1))` | 变量修改 |
| `if (x > 0) "yes" else "no"` | `(if (> x 0) "yes" "no")` | 条件 |
| `// 注释` | `; 注释` | 注释用分号 |
| `true / false` | `#t / #f` | 布尔值 |
| `null / undefined` | `'()` (空列表) | 空值 |

### 括号 = 调用

在 Scheme 里 **括号不只是分组**，它代表"执行"。`(f x)` 意思是"调用 f，参数为 x"。

```scheme
;; ✅ 调用 + 函数
(+ 1 2)       ;=> 3

;; ❌ 不要这样写 — 这是试图把 1 当函数调用
(1 + 2)       ;=> 错误！
```

---

## 数据类型

| 类型 | 示例 | 对应 GML |
|------|------|----------|
| 数值 | `42`, `3.14`, `-1` | `real` |
| 字符串 | `"hello"`, `"o_player"` | `string` |
| 布尔 | `#t`, `#f` | `true`, `false` |
| 符号 | `'foo`, `'hp` | 无（类似枚举名） |
| 列表 | `'(1 2 3)`, `(list "a" "b")` | 无（用 array 模拟） |
| 空列表 | `'()` | 无 |
| void | — | `undefined` |
| GML handle | 实例 ID、数组、struct | 实例/数组/struct |

### 类型检查

```scheme
(number? 42)         ;=> #t
(string? "hello")    ;=> #t
(list? '(1 2))       ;=> #t
(null? '())          ;=> #t
(boolean? #f)        ;=> #t
(array? some-arr)    ;=> #t (GML array)
(struct? some-st)    ;=> #t (GML struct)
```

---

## 变量与函数

### 定义变量

```scheme
(define x 42)
(define name "Stoneshard")
(define pi 3.14159)
```

### 修改变量

```scheme
(set! x 100)          ; x 从 42 变为 100
```

> 💡 `!` 结尾表示"有副作用"（修改了什么东西），这是 Scheme 的命名惯例。

### 定义函数

```scheme
;; 方式一：完整写法
(define (greet name)
  (string-append "Hello, " name "!"))

(greet "Verren")     ;=> "Hello, Verren!"

;; 方式二：lambda（匿名函数）
(define greet
  (lambda (name)
    (string-append "Hello, " name "!")))
```

### 局部变量 (let)

```scheme
;; let — 所有绑定同时生效
(let ((x 10) (y 20))
  (+ x y))           ;=> 30

;; let* — 绑定顺序生效（后面的可以引用前面的）
(let* ((x 10) (y (* x 2)))
  (+ x y))           ;=> 30
```

### 多参数和可变参数

```scheme
;; 固定参数
(define (add a b) (+ a b))

;; 可变参数：. rest 收集剩余参数为列表
(define (sum . nums)
  (foldl + 0 nums))

(sum 1 2 3 4 5)      ;=> 15
```

---

## 控制流

### if — 二选一

```scheme
(if (> hp 0)
  "alive"
  "dead")
```

> **注意**：`if` 有且只有两个分支。如果不需要 else，用 `when`。

### when / unless — 单分支

```scheme
(when (> hp 0)
  (display "still alive!"))

(unless (> hp 0)
  (display "game over"))
```

### cond — 多条件（类似 if/else if/else）

```scheme
(cond
  ((< hp 25)  "critical")
  ((< hp 50)  "wounded")
  ((< hp 75)  "hurt")
  (else       "healthy"))
```

### and / or — 短路逻辑

```scheme
(and (> x 0) (< x 100))    ; 两个都为真才为真
(or  (= x 0) (= x 1))     ; 任一为真就为真
```

### 循环 — 命名 let（Scheme 的 for 循环）

Scheme 没有 `for` / `while`，但命名 `let` 是等价的：

```scheme
;; GML 的 for (var i = 0; i < 5; i++) show_debug_message(i);
;; 在 Scheme 中：
(let loop ((i 0))
  (when (< i 5)
    (display i) (newline)
    (loop (+ i 1))))
```

读作："定义一个叫 loop 的递归函数，初始 i=0，每次 i+1，直到 i=5"。

### do — 传统循环

```scheme
(do ((i 0 (+ i 1)))        ; (变量 初值 每步更新)
    ((= i 5) "done")       ; (终止条件 返回值)
  (display i))              ; 循环体
```

---

## 列表 — Scheme 的核心数据结构

列表是 Scheme 世界的 Array。它是由 `cons` 对（pair）链接而成的链表。

### 创建列表

```scheme
'(1 2 3)              ; 引用语法（常量列表）
(list 1 2 3)          ; 使用 list 函数构建
(cons 1 (cons 2 '())) ; 底层构造：=> (1 2)
```

### 访问元素

```scheme
(car '(1 2 3))        ;=> 1         (第一个元素，相当于 arr[0])
(cdr '(1 2 3))        ;=> (2 3)     (除第一个外的剩余部分)
(cadr '(1 2 3))       ;=> 2         (car of cdr，第二个元素)
(list-ref '(1 2 3) 2) ;=> 3         (按索引, 0-based)
(last '(1 2 3))       ;=> 3         (最后一个)
(length '(1 2 3))     ;=> 3         (长度)
```

### 常用操作

```scheme
(append '(1 2) '(3 4))     ;=> (1 2 3 4)
(reverse '(1 2 3))         ;=> (3 2 1)
(take '(1 2 3 4 5) 3)      ;=> (1 2 3)
(drop '(1 2 3 4 5) 2)      ;=> (3 4 5)
(flatten '((1 2) (3 (4)))) ;=> (1 2 3 4)
(sort '(3 1 2) <)           ;=> (1 2 3)
(range 0 5)                 ;=> (0 1 2 3 4)
(iota 5)                    ;=> (0 1 2 3 4)
(zip '(a b c) '(1 2 3))    ;=> ((a 1) (b 2) (c 3))
```

---

## 高阶函数

高阶函数 = 把函数当参数传来传去。这是 Scheme 最大的威力。

### map — 对每个元素应用函数

```scheme
(map (lambda (x) (* x x)) '(1 2 3 4 5))
;=> (1 4 9 16 25)

; 等价于 GML:
; var _result = [];
; for (var _i = 0; _i < 5; _i++)
;   array_push(_result, _list[_i] * _list[_i]);
```

### filter — 筛选元素

```scheme
(filter (lambda (x) (> x 3)) '(1 2 3 4 5))
;=> (4 5)
```

### for-each — 对每个元素执行操作（不收集结果）

```scheme
(for-each
  (lambda (name) (display name) (newline))
  '("STR" "AGI" "PRC"))
```

### foldl — 累积（reduce）

```scheme
;; 求和
(foldl + 0 '(1 2 3 4 5))    ;=> 15

;; 求最大值
(foldl max 0 '(3 1 4 1 5))  ;=> 5

;; 拼接字符串
(foldl string-append "" '("a" "b" "c"))  ;=> "abc"
```

### find / any / every / count

```scheme
(find even? '(1 3 4 5))       ;=> 4     (第一个偶数)
(any even? '(1 3 5))          ;=> #f    (有偶数吗？没有)
(every positive? '(1 2 3))    ;=> #t    (全是正数？是)
(count even? '(1 2 3 4))      ;=> 2     (偶数有几个)
```

### partition — 分为两组

```scheme
(partition even? '(1 2 3 4 5))
;=> ((2 4) . (1 3 5))    ; (匹配的 . 不匹配的)
```

### compose — 组合函数

```scheme
(define abs-floor (compose floor abs))
(abs-floor -3.7)    ;=> 3
```

---

## 字符串操作

```scheme
(string-length "hello")              ;=> 5
(string-append "Stone" "shard")      ;=> "Stoneshard"
(string-contains? "o_player" "play") ;=> #t
(substring "abcdef" 2 4)             ;=> "cd"  (0-based)
(string-upcase "hello")              ;=> "HELLO"
(string-downcase "HELLO")            ;=> "hello"
(string-split "a,b,c" ",")          ;=> ("a" "b" "c")
(string-join '("a" "b" "c") ", ")   ;=> "a, b, c"
(string->number "42")               ;=> 42
(number->string 3.14)               ;=> "3.14"
```

---

## 与游戏互动 — Bridge API

这是 REPL 最核心的功能——实时操作游戏运行时状态。

### 获取玩家

```scheme
;; 获取 o_player 的第一个实例
(define player (gml:instance-find (gml:asset-get-index "o_player") 0))
```

### 读写实例变量

```scheme
;; 读
(instance-get player "hp")
(instance-get player "STR")
(instance-get player "x")
(instance-get player "y")

;; 写
(instance-set! player "hp" 999)
(instance-set! player "STR" 30)

;; 检查变量是否存在
(gml:variable-instance-exists player "some_var")

;; 实例是否还活着
(instance-exists? player)

;; 查看实例的所有变量名
(instance-keys player)
```

### 读写全局变量

```scheme
(global-get "hunger_count")
(global-set! "hunger_count" 0)
(gml:variable-global-exists "thirsty_count")
```

### Struct 操作

```scheme
;; 创建
(define s (struct "name" "sword" "damage" 15))

;; 读写
(struct-get s "name")         ;=> "sword"
(struct-set! s "damage" 20)

;; 检查
(struct-has? s "name")        ;=> #t

;; 枚举
(struct-keys s)               ;=> ("name" "damage")
(struct-values s)             ;=> ("sword" 20)
(struct->alist s)             ;=> (("name" . "sword") ("damage" . 20))
```

### Array 操作

```scheme
(define arr (array 10 20 30))
(array-length arr)            ;=> 3
(array-ref arr 0)             ;=> 10
(array-set! arr 0 99)
(array->list arr)             ;=> (99 20 30)
(list->array '(1 2 3))       ;=> GML array
```

### 查找实例

```scheme
;; 获取某种对象的实例数量
(gml:instance-number (gml:asset-get-index "o_enemy"))

;; 获取所有 o_enemy 实例列表
(instances-of "o_enemy")

;; 按索引获取第 N 个实例
(gml:instance-find (gml:asset-get-index "o_enemy") 0)
```

### 当前房间

```scheme
(gml:room)                         ;=> 房间索引
(gml:room-get-name (gml:room))     ;=> "r_Osbrook" 等
```

---

## 资产搜索

REPL 内置了游戏全部资产名的搜索功能（基于 `scm_data/*.json`）。

### search-* 系列

输入部分名称，返回所有匹配的资产名（大小写不敏感）：

```scheme
;; 搜索对象
(search-objects "player")
;=> ("o_player" "o_player_AI" "o_player_chest" "o_player_corpse"
;    "o_player_observer" "o_player_SimpleNPC" "o_player_speech_emitter")

(search-objects "wolf")
;=> ("o_wolf" "o_wolf_alpha" "o_wolf_dire" ...)

(search-objects "sword")
;=> ("o_sword_..." ...)

;; 搜索声音
(search-sounds "thunder")
;=> ("snd_amb_weather_thunder_1" "snd_amb_weather_thunder_2" ...)

;; 搜索房间
(search-rooms "osbrook")
;=> ("r_Osbrook" "r_OsbrookInside_..." ...)

;; 搜索精灵
(search-sprites "wolf")
;=> ("s_wolf_..." ...)

;; 搜索脚本
(search-scripts "damage")
;=> ("scr_damage_..." ...)

;; 搜索内置函数
(search-functions "cursor")
;=> ("native_cursor_add_from_buffer" "native_cursor_set" ...)
```

### 对象继承树

```scheme
;; 查看某个对象的直接子类
(object-children "c_human")
;=> ("o_bandit_1h" "o_bandit_2h" "o_guard" ...)

;; 查看某个对象的祖先链
(object-ancestors "o_player")
;=> ("c_human" "c_hit_parent" ...)

;; 查看父类
(object-parent "o_player")
;=> "c_human"
```

---

## Pretty Printer 与调试

### pp — 通用 pretty print

对复杂数据自动格式化输出（字段排序、对齐、深度限制）：

```scheme
(pp some-struct)     ; 结构体漂亮打印
(pp some-array)      ; 数组漂亮打印
(pp '(1 2 3))        ; 列表打印
```

### probe — 智能类型探测

当你不确定一个值的类型（特别是数字可能是实例 ID、ds_map ID 等）：

```scheme
(probe player)       ; 自动检测是实例，打印所有字段
(probe some-number)  ; 自动探测 ds_map / ds_list / instance
```

### 专用 pretty printer

```scheme
(pp-instance player)      ; 打印实例的所有变量
(pp-struct my-struct)     ; 打印 struct
(pp-array my-array)       ; 打印 GML array
(pp-ds-map map-id)        ; 打印 ds_map
(pp-ds-list list-id)      ; 打印 ds_list
```

### 控制输出量

```scheme
(set! *pp-max-items* 20)     ; 最多显示 20 项（默认 9999）
(set! *pp-max-depth* 4)      ; 最大递归深度（默认 8）
```

### apropos — 搜索可用函数

在环境中搜索匹配的绑定名：

```scheme
(apropos "string")    ; 列出所有包含 "string" 的函数
(apropos "instance")  ; 列出所有包含 "instance" 的函数
```

### debug-log

输出到 GML 调试控制台（不是 REPL 屏幕）：

```scheme
(log "player hp = " (instance-get player "hp"))
; 输出: [scm] player hp = 42
```

---

## 线程宏 (Threading Macros)

当你需要 **链式调用** 多个函数时，每层嵌套越来越难读。线程宏解决这个问题。

### `->` 线程优先（Thread First）

把结果插入为下一个表达式的 **第一个** 参数：

```scheme
;; 不用线程宏 — 从内往外读，很痛苦：
(length (filter (lambda (x) (> x 3)) (map abs '(-5 2 -1 4 -3))))

;; 用 -> 线程宏 — 从上往下读，像管道：
(-> '(-5 2 -1 4 -3)
    (map abs)
    (filter (lambda (x) (> x 3)))
    (length))
;=> 2
```

### `->>` 线程末尾（Thread Last）

把结果插入为 **最后一个** 参数（适用于列表操作，因为列表总是最后一个参数）：

```scheme
(->> '(1 2 3 4 5)
     (filter odd?)
     (map (lambda (x) (* x x)))
     (foldl + 0))
;=> 35   ; 1² + 3² + 5²
```

### `some->` 安全线程

遇到 `noone` (-4) 时自动短路（适合链式实例操作）：

```scheme
;; 如果任何一步返回 noone，直接返回 noone，不会报错
(some-> "o_player"
        (gml:asset-get-index)
        (gml:instance-find 0)
        (instance-get "hp"))
```

---

## REPL 技巧

| 快捷键 | 功能 |
|--------|------|
| **F1** | 打开/关闭 REPL |
| **Tab** | 自动补全（Bash 风格） |
| **F3** | 全屏模糊搜索 |
| **↑ / ↓** | 浏览历史记录 |
| **Enter** | 执行当前行 |
| **Esc** | 关闭补全弹窗 |

### 内置帮助

```scheme
(help "map")          ; 查看 map 函数的用法
(help "define")       ; 查看 define 语法
(help "instance-get") ; 查看 instance-get 用法
(apropos "sort")      ; 搜索所有名字包含 sort 的绑定
```

---

## 实战示例

### 示例 1：查看玩家所有属性

```scheme
(define player (gml:instance-find (gml:asset-get-index "o_player") 0))
(pp-instance player)
```

### 示例 2：回满血

```scheme
(define player (gml:instance-find (gml:asset-get-index "o_player") 0))
(let ((max-hp (instance-get player "HP_max")))
  (instance-set! player "hp" max-hp)
  (display (string-append "HP restored to " (number->string max-hp))))
```

### 示例 3：列出当前房间所有特定属性

```scheme
(define player (gml:instance-find (gml:asset-get-index "o_player") 0))

(for-each
  (lambda (attr)
    (when (gml:variable-instance-exists player attr)
      (display (string-append
        attr ": " (number->string (instance-get player attr)) "\n"))))
  '("STR" "AGI" "PRC" "VIT" "WIL" "hp" "mp"))
```

### 示例 4：统计房间内的敌人

```scheme
(let ((enemies (instances-of "o_enemy")))
  (display (string-append
    "Room: " (gml:room-get-name (gml:room)) "\n"
    "Enemy count: " (number->string (length enemies)) "\n"))
  (for-each
    (lambda (e)
      (let ((name (gml:object-get-name
                    (instance-get e "object_index")))
            (hp   (instance-get e "hp")))
        (display (string-append
          "  " name " — HP: " (number->string hp) "\n"))))
    enemies))
```

### 示例 5：搜索所有包含 "troll" 的对象并查看继承树

```scheme
(for-each
  (lambda (name)
    (let ((parents (object-ancestors name)))
      (display name)
      (when (not (null? parents))
        (display " ← ")
        (display (string-join parents " ← ")))
      (newline)))
  (search-objects "troll"))
```

### 示例 6：用管道搜索敌人并按 HP 排序

```scheme
(->> (instances-of "o_enemy")
     (map (lambda (e)
            (cons (gml:object-get-name (instance-get e "object_index"))
                  (instance-get e "hp"))))
     (sort (lambda (a b) (> (cdr a) (cdr b))))
     (for-each (lambda (pair)
       (display (string-append
         (car pair) ": " (number->string (cdr pair)) "\n")))))
```

### 示例 7：修改全局变量

```scheme
;; 读取饥饿和口渴计数
(display (string-append
  "Hunger: " (number->string (global-get "hunger_count")) "\n"
  "Thirst: " (number->string (global-get "thirsty_count")) "\n"))

;; 重置饥饿
(global-set! "hunger_count" 0)
```

### 示例 8：批量测试属性对伤害的影响

```scheme
(define player (gml:instance-find (gml:asset-get-index "o_player") 0))
(define original-str (instance-get player "STR"))

(for-each
  (lambda (str-val)
    (instance-set! player "STR" str-val)
    (display (string-append
      "STR=" (number->string str-val)
      " → Melee Damage Bonus=" (number->string (instance-get player "Melee_Damage_Bonus"))
      "\n")))
  '(10 15 20 25 30))

;; 改回原值
(instance-set! player "STR" original-str)
```

### 示例 9：ds_map 读取

```scheme
;; 如果你拿到一个 ds_map ID（例如从全局变量获取）
(define m (global-get "__dialogue_script_store"))
(when (ds-map? m)
  (display (string-append "Keys: " (number->string (gml:ds-map-size m)) "\n"))
  (pp-ds-map m))
```

### 示例 10：构造并操作 Scheme 数据

```scheme
;; 关联列表（key-value 的 Scheme 方式）
(define inventory '(("sword" . 1) ("potion" . 5) ("arrow" . 20)))

;; 查找
(assoc "potion" inventory)        ;=> ("potion" . 5)
(cdr (assoc "potion" inventory))  ;=> 5

;; 过滤数量 > 2 的
(filter (lambda (item) (> (cdr item) 2)) inventory)
;=> (("potion" . 5) ("arrow" . 20))
```

---

## Cheatsheet

### 算术

| 表达式 | 结果 | 说明 |
|--------|------|------|
| `(+ 1 2 3)` | `6` | 加法（多参数） |
| `(- 10 3)` | `7` | 减法 |
| `(- 5)` | `-5` | 取负 |
| `(* 2 3 4)` | `24` | 乘法 |
| `(/ 10 3)` | `3.33` | 除法 |
| `(modulo 10 3)` | `1` | 取余 |
| `(min 3 7)` | `3` | 最小值 |
| `(max 3 7)` | `7` | 最大值 |
| `(abs -5)` | `5` | 绝对值 |
| `(floor 3.7)` | `3` | 向下取整 |
| `(ceiling 3.2)` | `4` | 向上取整 |
| `(round 3.5)` | `4` | 四舍五入 |
| `(sqrt 16)` | `4` | 平方根 |
| `(expt 2 10)` | `1024` | 幂运算 |
| `(clamp 5 0 3)` | `3` | 钳制 |
| `(random 100)` | `0~99.99` | 随机数 |
| `(irandom 100)` | `0~100` | 随机整数 |
| `(lerp 0 100 0.5)` | `50` | 线性插值 |

### 比较（支持链式）

| 表达式 | 结果 |
|--------|------|
| `(= 1 1)` | `#t` |
| `(< 1 2 3)` | `#t` |
| `(> 3 2 1)` | `#t` |
| `(<= 1 1 2)` | `#t` |
| `(>= 3 3 2)` | `#t` |

### 谓词（类型检查 / 判断）

| 表达式 | 说明 |
|--------|------|
| `(null? x)` | 是空列表？ |
| `(pair? x)` | 是 pair/列表节点？ |
| `(list? x)` | 是正规列表？ |
| `(number? x)` | 是数值？ |
| `(string? x)` | 是字符串？ |
| `(boolean? x)` | 是布尔？ |
| `(symbol? x)` | 是符号？ |
| `(zero? x)` | 是零？ |
| `(positive? x)` | 是正数？ |
| `(negative? x)` | 是负数？ |
| `(even? x)` | 是偶数？ |
| `(odd? x)` | 是奇数？ |
| `(integer? x)` | 是整数？ |
| `(procedure? x)` | 是函数？ |
| `(equal? a b)` | 结构相等（深比较） |
| `(eq? a b)` | 引用相等 |

### 列表操作

| 表达式 | 结果 | 说明 |
|--------|------|------|
| `(list 1 2 3)` | `(1 2 3)` | 创建列表 |
| `(cons 0 '(1 2))` | `(0 1 2)` | 头部添加 |
| `(car '(1 2 3))` | `1` | 第一个 |
| `(cdr '(1 2 3))` | `(2 3)` | 除第一个 |
| `(length '(1 2))` | `2` | 长度 |
| `(reverse '(1 2 3))` | `(3 2 1)` | 反转 |
| `(append '(1) '(2 3))` | `(1 2 3)` | 拼接 |
| `(list-ref '(a b c) 1)` | `b` | 按索引 |
| `(last '(1 2 3))` | `3` | 最后 |
| `(take '(1 2 3 4) 2)` | `(1 2)` | 取前 N |
| `(drop '(1 2 3 4) 2)` | `(3 4)` | 丢前 N |
| `(sort '(3 1 2) <)` | `(1 2 3)` | 排序 |
| `(range 0 5)` | `(0 1 2 3 4)` | 范围 |
| `(iota 5)` | `(0 1 2 3 4)` | 同上 |
| `(zip '(a b) '(1 2))` | `((a 1) (b 2))` | 配对 |
| `(flatten '((1) (2 3)))` | `(1 2 3)` | 展平 |

### 高阶函数

| 表达式 | 结果 | 说明 |
|--------|------|------|
| `(map f lst)` | 新列表 | 映射 |
| `(filter pred lst)` | 子列表 | 筛选 |
| `(remove pred lst)` | 子列表 | filter 的反面 |
| `(for-each f lst)` | void | 遍历（副作用） |
| `(foldl f init lst)` | 累积值 | 左折叠 |
| `(find pred lst)` | 元素/`#f` | 第一个匹配 |
| `(any pred lst)` | `#t/#f` | 存在？ |
| `(every pred lst)` | `#t/#f` | 全部？ |
| `(count pred lst)` | 数值 | 计数 |
| `(partition pred lst)` | `(yes . no)` | 分组 |
| `(apply f lst)` | 结果 | 展开参数调用 |

### 字符串

| 表达式 | 结果 |
|--------|------|
| `(string-length "hi")` | `2` |
| `(string-append "a" "b")` | `"ab"` |
| `(string-contains? "abc" "bc")` | `#t` |
| `(substring "abcde" 1 3)` | `"bc"` |
| `(string-upcase "hi")` | `"HI"` |
| `(string-downcase "HI")` | `"hi"` |
| `(string-split "a,b" ",")` | `("a" "b")` |
| `(string-join '("a" "b") ",")` | `"a,b"` |
| `(string->number "42")` | `42` |
| `(number->string 42)` | `"42"` |
| `(string-empty? "")` | `#t` |

### Bridge API（游戏交互）

| 操作 | 代码 |
|------|------|
| 获取玩家 | `(define p (gml:instance-find (gml:asset-get-index "o_player") 0))` |
| 读实例变量 | `(instance-get p "hp")` |
| 写实例变量 | `(instance-set! p "hp" 100)` |
| 读全局变量 | `(global-get "hunger_count")` |
| 写全局变量 | `(global-set! "hunger_count" 0)` |
| 实例存在？ | `(instance-exists? p)` |
| 变量存在？ | `(gml:variable-instance-exists p "var")` |
| 同类实例列表 | `(instances-of "o_enemy")` |
| 实例数量 | `(gml:instance-number (gml:asset-get-index "o_enemy"))` |
| 当前房间名 | `(gml:room-get-name (gml:room))` |
| 对象名 | `(gml:object-get-name obj-index)` |
| 资产索引 | `(gml:asset-get-index "o_player")` |

### Struct / Array

| 操作 | 代码 |
|------|------|
| 创建 struct | `(struct "k1" v1 "k2" v2)` |
| 读 struct | `(struct-get s "key")` |
| 写 struct | `(struct-set! s "key" val)` |
| struct 键列表 | `(struct-keys s)` |
| struct→alist | `(struct->alist s)` |
| 创建 array | `(array 1 2 3)` |
| 读 array | `(array-ref arr i)` |
| 写 array | `(array-set! arr i val)` |
| array→list | `(array->list arr)` |
| list→array | `(list->array lst)` |

### 搜索

| 操作 | 代码 |
|------|------|
| 搜索对象 | `(search-objects "pattern")` |
| 搜索精灵 | `(search-sprites "pattern")` |
| 搜索声音 | `(search-sounds "pattern")` |
| 搜索房间 | `(search-rooms "pattern")` |
| 搜索脚本 | `(search-scripts "pattern")` |
| 搜索函数 | `(search-functions "pattern")` |
| 子对象 | `(object-children "c_human")` |
| 祖先链 | `(object-ancestors "o_player")` |
| 父对象 | `(object-parent "o_player")` |

### 调试

| 操作 | 代码 |
|------|------|
| pretty print | `(pp obj)` |
| 智能探测 | `(probe obj)` |
| 实例详情 | `(pp-instance id)` |
| 搜索绑定 | `(apropos "pattern")` |
| 帮助 | `(help "函数名")` |
| 日志 | `(log "msg" val)` |

### 特殊形式速查

| 形式 | 用法 | 类似 GML |
|------|------|----------|
| `define` | `(define x 42)` | `var x = 42` |
| `define` (函数) | `(define (f x) body)` | `function f(x) { body }` |
| `lambda` | `(lambda (x) (* x 2))` | `function(x) { return x*2 }` |
| `if` | `(if test then else)` | `test ? then : else` |
| `cond` | `(cond (t1 e1) ... (else e))` | `if/else if/else` |
| `when` | `(when test body)` | `if (test) { body }` |
| `unless` | `(unless test body)` | `if (!test) { body }` |
| `let` | `(let ((x 1)) body)` | `{ var x = 1; body }` |
| `begin` | `(begin e1 e2 e3)` | `{ e1; e2; e3; }` |
| `set!` | `(set! x 10)` | `x = 10` |
| `and` | `(and a b)` | `a && b` |
| `or` | `(or a b)` | <code>a &#124;&#124; b</code> |
| `quote` | `'(1 2 3)` | 字面量 |
| `do` | `(do ((i 0 (+ i 1))) ...)` | `for (var i=0; ...)` |
| `define-macro` | `(define-macro (m ...) ...)` | 编译时代码变换 |
| `->` | `(-> x (f) (g))` | `g(f(x))` |
| `->>` | `(->> x (f) (g))` | `g(f(x))` (末尾) |

---

## 常见陷阱

### 1. 括号代表调用
```scheme
;; ❌ 数字不能当函数
(1 + 2)     ; Error!

;; ✅
(+ 1 2)     ; => 3
```

### 2. if 必须有两个分支
```scheme
;; ❌ 缺少 else 分支（结果不确定）
(if (> x 0) "yes")

;; ✅ 不需要 else 时用 when
(when (> x 0) "yes")
```

### 3. 引用 vs 调用
```scheme
;; '(1 2 3) 是数据（引用，不求值）
'(+ 1 2)     ;=> (+ 1 2)  — 一个包含符号 + 和数字的列表

;; (1 2 3) 是调用（会尝试执行）
(+ 1 2)      ;=> 3
```

### 4. 递归深度
GML 调用栈约 256 帧。对于大列表的循环，永远用**尾递归**（让递归调用在函数最后）：
```scheme
;; ✅ 尾递归 — loop 是尾调用
(let loop ((i 0) (sum 0))
  (if (= i 1000) sum
    (loop (+ i 1) (+ sum i))))

;; ❌ 非尾递归 — + 是尾调用，递归不是
(define (bad-sum n)
  (if (= n 0) 0
    (+ n (bad-sum (- n 1)))))  ; 大 n 会栈溢出
```

### 5. ds_map/ds_list 需要手动销毁
```scheme
;; ds_map 和 ds_list 是 GML 资源，需要手动释放
(define m (gml:ds-map-create))
;; ... 使用 m ...
(gml:ds-map-destroy m)  ; 不要忘记！

;; Scheme 的 list 不需要手动管理，优先使用 list
```

### 6. 函数名带 `!` 和 `?` 的含义
- `?` 结尾 = 谓词，返回 `#t` 或 `#f`（如 `null?`, `even?`）
- `!` 结尾 = 有副作用，修改了参数（如 `set!`, `instance-set!`）

---

## 附录：scm_data 资产名示例

以下列举部分游戏内实际资产名，可用于 `search-*` 和 `gml:asset-get-index`：

### 常用对象 (objects)

```
o_player                    — 玩家
o_enemy                     — 敌人基类
o_NPC                       — NPC 基类
o_chest                     — 宝箱
o_player_chest              — 玩家储物箱
o_container                 — 可搜索容器
o_modificators              — buff/debuff
```

### 常用全局变量 (globals)

```
HP / MP                     — 全局 HP/MP 引用
AllDamage                   — 伤害统计
hunger_count                — 饥饿计数
thirsty_count               — 口渴计数
UI_is_on                    — UI 是否激活
Osbrook                     — Osbrook 相关状态
TurnDelay                   — 回合延迟
```

### 部分房间 (rooms)

```
r_Osbrook                   — Osbrook 主区域
r_Brynn_01                  — Brynn 第一区
r_AbadonedVillage           — 废弃村庄
CATACOMBS_TEMPLATE          — 地下墓穴模板
CAVE_TEMPLATE               — 洞穴模板
FORTRESS_TEMPLATE           — 堡垒模板
```

### 部分声音 (sounds)

```
snd_amb_weather_thunder_*   — 雷声
snd_amb_weather_rain_*      — 雨声
snd_arcane_bolt_*           — 奥术箭
snd_alert_search            — 警报
```

> 使用 `(search-* "关键词")` 来发现更多！
