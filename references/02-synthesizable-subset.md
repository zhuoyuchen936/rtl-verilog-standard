# 02 · 可综合子集：什么能写、什么不能写

> 本篇是 `SKILL.md` 铁律 **G**（位宽、运算与可综合性）与 **I**（明确禁止）的展开与论证。
> 出现分歧时以 `SKILL.md` 为准；本篇末尾单列「⚠️ 与主规范的冲突」。
> 标签：`[教材]` = 夏宇闻《Verilog 数字系统设计教程(第4版)》带书页号；`[业界]` = 标准/论文/厂商手册；
> `[工具]` = 本机 WSL 上 **Verilator 5.024 + Yosys 0.33** 实测（命令见 `SKILL.md` 第 2 节）。

## 本篇速览

1. 可综合的只有**门级 + RTL 级**，外加算法级里"离散算术步骤"那一小块；系统级只能进 testbench。`[教材]` p.138
2. 判据一句话：**你写的每一句都要能回答"这对应哪几个门、哪几个触发器"**。答不上来就当它不可综合。
3. V2001 设计模块白名单：`wire/reg/parameter/localparam/genvar` + `assign` + `always` + `if/case/for` + `generate` + `function` + 命名端口例化。名单外的构造先查表再写。
4. 五条硬边界：`initial`、`#延迟`、`fork/join`、`while/repeat/forever`、`wait/force/release/disable`；外加 UDP、`specify`、实数、动态类型、系统任务。
5. **可综合 ≠ 综合出来是对的**。`===`、`casex`、`#1`、`full_case` 都能过综合，但会让 RTL 仿真和门级分岔——本篇每条都有实测。
6. SV 只放行 8 个构造：`logic`、`always_comb/_ff/_latch`、`typedef`、`enum`、packed `struct`/`union`、`package`。`interface` 单列讨论（§4.7），默认不用。

---

## 1. 抽象级别与可综合性分级 `[教材]` 第 9 章 `[通用]`

教材把 Verilog 支持的描述方法分成 5 级，并在 p.130 划界：**系统级、算法级、RTL 级属行为级，门级属结构级**。
p.138 小结给出了本章最关键的可综合性结论：

| 抽象级别 | 归类 | 可综合性（`[教材]` p.138 原文归纳） | 本规范怎么用 |
|---|---|---|---|
| 系统级 (system) | 行为级 | **不可综合**——"目前尚未有综合器能把它转换成标准的逻辑网表，往往只用于系统仿真" | 只允许出现在 testbench / 参考模型 |
| 算法级 (algorithmic) | 行为级 | **部分可综合**——"只有算术运算的离散步骤，如加法和乘法，综合器能把它转换成标准的逻辑网表；而不能综合连续的复杂运算过程" | 只有能写成"每周期一步"的离散步骤才允许 |
| RTL 级 | 行为级 | **可综合** → 标准逻辑网表 | ✅ 主力，99% 的代码在这一级 |
| 门级 (gate-level) | 结构级 | **可综合** → 标准逻辑网表 | 只在时序极端吃紧时用（`SKILL.md` H2） |
| 开关级 (switch-level) | 结构级 | 教材略去（属模拟电路范畴） | ❌ 不写 |

三条必须记住的机理：

1. **综合器产出的是"标准的门级结构网表，而并非真实具体的门级电路"** `[教材]` p.137，真实电路由布局布线工具生成。所以"能综合"只意味着"能映射成网表"，不等于时序收敛、面积可接受。
2. **可综合子集只是完整语法的一个子集，且"各厂商的综合器所支持的可综合 HDL 子集也略有不同"** `[教材]` p.137。因此本篇表格里所有 ⚠️ 行，在你自己的目标工具上实测过再用。
   > 教材同页"可综合子集的国际标准目前尚未最后形成"一句**已过时**：此后 IEEE 1364.1-2002《Verilog RTL 综合子集》发布并被 IEC/IEEE 62142-2005 取代 `[业界]` W04-S1。但调研文件注明该标准正文付费、**只取到 scope 摘要**，故本篇不引用其条款号。
3. **行为仿真通过 ≠ 前端设计完成**：教材 p.134 的流程与 p.139 思考题 9、14 都要求对综合后网表再仿真一次，并解释两者"细微的不同"。这正是本篇存在的意义——大多数 mismatch 是"写了能综合但语义不对等的东西"造成的。

---

## 2. 可综合子集总表

图例：✅ 可综合且推荐 ｜ ⚠️ 条件可综合，读对应说明 ｜ ❌ 不可综合或本规范禁止 ｜ — 该语言无此构造

### 2.1 数据类型 `[通用]`

| 构造 | V2001 | SV | 结论与理由 |
|---|---|---|---|
| `wire` / `tri` | ✅ | ✅ | 网络型不存值，必须有驱动器；无驱动即高阻 z `[教材]` p.32。`tri` 只用于顶层 pad |
| `reg` | ✅ | ⚠️ 改用 `logic` | **`reg` ≠ 触发器**。`[教材]` p.34 原话："reg 型只表示被定义的信号将用在 always 模块内……并不是说 reg 型信号一定是寄存器或触发器的输出" |
| `logic` | — | ✅ | 单驱动变量，编译器帮你查多驱动 `[业界]` lowRISC |
| `integer` | ⚠️ | ⚠️ | **只用作 for 循环变量与常量计算**。做设计信号会综合成 32 位总线 `[教材]` p.381 可综合(14)、`SKILL.md` D6 |
| `real` / `realtime` / `time` | ❌ | ❌ | 无硬件对应物 `[教材]` p.381 可综合(14) |
| `parameter` / `localparam` | ✅ | ✅ | 由其他 parameter 推导出的量**必须**用 `localparam`，否则外部传参会破坏推导关系 `[教材]` p.71 例 5.16 |
| `genvar` | ✅ | ✅ | 展平后电路里不存在 `[教材]` p.69 |
| `event` + `->` | ❌ | ❌ | 纯仿真同步机制 `[教材]` p.136 |
| reg 数组（memory） | ✅ | ✅ | 见 §3.9；`[教材]` p.34 |
| `bit`/`byte`/`int`/`shortint` | — | ⚠️ | 2 值类型，可综合但丢掉 x 传播能力。本规范只在 `localparam int unsigned` 之类常量计算里用 |
| `typedef` | — | ✅ | §4.4 |
| `enum` | — | ✅ | §4.5 |
| packed `struct` / `union` | — | ✅ | §4.6 |
| unpacked `struct` / 非 packed 数组做端口 | — | ⚠️ | 工具支持差异大，跨工具流程禁用 |
| `string` / `class` / 动态数组 / 队列 / 关联数组 | — | ❌ | 需要运行期内存管理，硅上没有 `SKILL.md` I |
| `interface` | — | ⚠️ | §4.7，本规范默认不用 |

### 2.2 运算符 `[通用]`

| 运算符 | 结论 | 理由 / 实测 |
|---|---|---|
| `+ - *` | ✅ | 综合器映射到加法器/乘法器（或 DSP 硬核） |
| `/` `%` | ⚠️ | **除数是常量（尤其 2 的幂）几乎免费；除数是变量就是一个组合除法器。** `[工具]` yosys 0.33 `synth`：8 位 `a_i / b_i` → **371 个门**；8 位 `a_i / 8'd4` → **0 个门**（被优化成位选）。教材 p.36 另给出语义：整数除法截断小数，取模结果符号取第一个操作数 |
| `**` | ⚠️ | 指数为常量时展开成乘法可综合；变量指数禁止 |
| `> < >= <=` | ✅ | 结果 1 位无符号 `[业界]` IEEE 1364-2005 §5.5.1 |
| `== !=` | ✅ | 操作数含 x/z 时结果为 x `[教材]` p.41 表 4.2 |
| `=== !==` | ❌ | **本规范禁止。** `[工具]` verilator lint 干净、yosys 也照综合不误（`$eqx`，`synth` 后成普通门）——因为综合是 2 值世界，`===` 退化成 `==`；而 RTL 仿真是 4 值的。这是"能综合但仿真/综合不等价"的典型 |
| `&& \|\| !` | ✅ | 多 bit 信号不要直接当布尔用，显式与 0 比较 `[业界]` lowRISC |
| `& \| ^ ~ ^~` | ✅ | 逐位运算；不同位宽会右对齐、高位补 0 `[教材]` p.37 |
| 缩减 `&a` `\|a` `^a` | ✅ | 单目，结果 1 位 `[教材]` p.42 |
| `<< >>` | ✅ | 移出位补 0。**左移不会自动变宽**：左操作数是上下文决定的，宽度由左值定。`4'b1001 << 1` 存进 4 位就是 `4'b0010`（最高位移丢），存进 5 位才是 `5'b10010`。想保留移出的位必须把左值开宽或先显式扩展。右操作数是自定宽度的，见 `07-datapath-and-width.md` R-07-02 `[工具]` Yosys 实测 |
| `<<< >>>` | ⚠️ | 算术右移**只在左操作数为有符号时**成立；part-select 结果是无符号，`s[7:0] >>> 1` 是逻辑右移 `[业界]` W08-15 / IEEE 1364-2005 §5.5.1 |
| `{}` `{n{}}` | ✅ | 重复次数必须是常量表达式 `[教材]` p.42；拼接里**不允许无位宽常量**（LRM 原文 `shall not`）`[业界]` W08-14 |
| `?:` | ✅ | 条件本身自决定位宽，两个分支按 `max` 取宽 `[业界]` IEEE 1364-2005 Table 5-22 |
| `$signed()` `$unsigned()` | ✅ | 只重解释符号，不改位宽 |
| `$clog2()` | ✅ | `$clog2(0) == $clog2(1) == 0`，用它算地址位宽要写 `(D<=1)?1:$clog2(D)` `[业界]` W08-16 / IEEE 1364-2005 §17.11.1 |
| `$bits(<类型名>)` | ⚠️ | `[工具]` **yosys 0.33 语法错误**（`unexpected TOK_USER_TYPE`）；改写成 `$bits(<该类型的变量>)`，或直接把位宽写成 `localparam` |
| `$display` / `$finish` / `$fopen` / `$dumpvars` 等 | ❌ | testbench 专用 `[教材]` p.136、p.91-98 |

### 2.3 过程块与语句 `[通用]`

| 构造 | V2001 | SV | 结论与理由 |
|---|---|---|---|
| `assign` 连续赋值 | ✅ | ✅ | 描述组合逻辑最常用的方法 `[教材]` p.28；能用 `assign` 就别写 always `[业界]` lowRISC |
| 门级原语 `and/nand/not/...` | ✅ | ✅ | 结构描述本质是网表，可仿真也可综合 `[教材]` p.133 |
| `always @(*)` / `always @*` | ✅ | ⚠️ 改 `always_comb` | 见 §3.1、§4.2 |
| `always @(posedge clk …)` | ✅ | ⚠️ 改 `always_ff` | 只允许一个时钟沿 `[教材]` p.180 always(4) |
| `always_latch` | — | ⚠️ | 只在**刻意**建 latch 时；`SKILL.md` C1 例外条款 |
| `initial` | ⚠️ `[FPGA]` / ❌ `[ASIC]` | 同左 | 见 §5.1 |
| `if / else` | ✅ | ✅ | 必须有 `else`（或块首默认值）`[教材]` p.57 |
| `case` | ✅ | ✅ | 必须有 `default`；分支位宽必须一致 `[教材]` p.54、p.57 |
| `casez` | ⚠️ | ⚠️ | 只在 case item 里写 `?`；见 §3.3 |
| `casex` | ❌ | ❌ | `SKILL.md` G5；见 §3.3 |
| `case … inside` | — | ⚠️ | 语义最安全，但老工具支持有限；用前实测 |
| `for` | ⚠️ | ⚠️ | 边界必须常量，会被完全展开；见 §3.5 |
| `while` / `repeat` / `forever` | ❌ | ❌ | 循环次数不可静态确定 `SKILL.md` I；`forever` 甚至不能独立于 `initial` 存在 `[教材]` p.60 |
| `fork / join` | ❌ | ❌ | 并行块语义是仿真调度，且天然带竞争 `[教材]` p.64-65 |
| `disable` | ❌ | ❌ | 中止命名块，纯仿真控制流 `[教材]` p.66 |
| `wait` | ❌ | ❌ | 电平敏感等待 `[教材]` p.82 |
| `#延迟`（含 `#0`、`q <= #1 d`） | ❌ | ❌ | 见 §3.7；`[教材]` p.197 原则(8)、p.381 可综合(13) |
| `force/release`、`assign/deassign` | ❌ | ❌ | 过程连续赋值 `SKILL.md` I |
| `task` | ⚠️ | ⚠️ | 见 §3.6 |
| `function` | ✅ | ✅ | 见 §3.6 |
| `generate / endgenerate` | ✅ | ✅ | 见 §3.5 |
| `defparam` | ❌ | ❌ | 用 `#()` 传参代替；`defparam` 主要用途是后仿真反标注 `[教材]` p.31 |
| UDP `primitive` | ❌ | ❌ | 见 §3.8 |
| `specify / endspecify` | ❌ | ❌ | 见 §3.8 |
| 跨模块层次引用（XMR） | ❌ | ❌ | `[业界]` W08-24 明确标注**未取到一手出处**，按工程通识禁止 |
| `` `include `` 模块源文件 | ❌ | ❌ | 教材 p.135 用 `` `include "hardreg.v" `` 引模块，这是当年的做法；现代流程用文件列表，`` `include `` 只留给头文件 |
| `` `define `` 定义设计常量 | ❌ | ❌ | 宏是全局的、会污染命名空间；用 `localparam` `SKILL.md` B5/F2 |

---

## 3. 逐条讲机理

### 3.1 `if` / `case`：latch 是怎么来的 `[通用]`

`[教材]` p.56 的原话最直白：**"在 always 块内，如果在给定的条件下变量没有赋值，这个变量将保持原值，也就是说会生成一个锁存器。"**
"保持原值"这四个字就是 latch 的定义——组合电路做不到记忆，综合器只好插一个电平敏感锁存器。

`[教材]` p.181 补了另一半：敏感表**漏列**信号也会产生透明锁存器，因为"该信号的变化不会立刻引起所赋值的变化，而必须等到敏感电平列表中某一个信号变化时，它的作用才显现出来"。`always @(*)` 从根上消灭了这一类。

`[工具]` 实测（`latch_bad_demo.v`：`if` 无 `else` + `case` 无 `default`）：

- Verilator：`%Warning-LATCH: Latch inferred for signal 'q_o'`，以及 `%Warning-CASEINCOMPLETE`
- Yosys `proc`：`Latch inferred for signal '\y_o'`、`Latch inferred for signal '\q_o'`，两个都变成 `$dlatch`

注意一个细节：**Verilator 对 case 缺 default 报的是 `CASEINCOMPLETE` 而不是 `LATCH`**。别只 grep `LATCH` 就以为干净。

**唯一可靠的防 latch 手段是"块首先给所有输出赋默认值"**，`[业界]` Mills SNUG 2012 §7.0 原话："The only way to fully prevent unintended latches in combinational logic blocks is to assign every output for every condition."；Cummings SNUG Israel 2005 Example 8/9 用 DC 报告实证了：case 本身是 full 的、加了 `full_case` 也没用，只要有输出在某分支没赋值，DC 照样报 latch。

### 3.2 `case` 的位宽与 x/z `[通用]` `[教材]` p.54

教材点名"一个经常犯的错误"：用 `'bx` / `'bz` 代替 `n'bx` / `n'bz`。理由是**不写位宽时 x/z 按机器字长（通常 32 位）扩展**，与控制表达式位宽不符，逐位比较必然失败。这就是 `SKILL.md` G2 的出处。

同页还有两条：每个分支表达式的值**必须互不相同**（否则同一控制值有多种执行方案，语义矛盾，p.54）；执行完一个分支立即跳出，**没有 C 的 fall-through**（p.54）。

### 3.3 `casez` / `casex` / `case inside` `[通用]`

`SKILL.md` G5 禁 `casex`、慎用 `casez`，理由是一手资料四处独立佐证：

- `[业界]` Cummings SNUG'99 Boston："**Do not use casex for synthesizable code.**"；要通配就用 `casez` 且"use `?` characters instead of `z` characters"
- `[业界]` Mills & Cummings SNUG'99："Do not use casex for RTL coding. It is too easy to match a stray unknown signal."
- `[业界]` Mills SNUG 2012 更狠：**"The SystemVerilog casez and casex types of case statements have an inherent simulation/synthesis mismatch."**——即 `casez` 也有固有 mismatch，不是"casez 就安全"

机理（`[业界]` W08-07 给出的关键不对称）：IEEE 1364 §9.5.1 的**仿真**语义里，**case 表达式一侧的 x/z 也参与通配匹配**；而 Vivado 综合手册 UG901 描述的只是"branch alternative 里的 x/z 当 don't care"。两边对同一段代码的理解不同，这就是 mismatch 的根。

教材 p.55 表 5.1 给了三者的真值表，并把 casez/casex 作为"处理不必关心情况"的推荐手段——**教材未提及综合层面的风险**，本规范按业界一手资料收紧。

**本规范做法**：优先普通 `case`；有意的优先级用 `if-else` 链（见下）；确需通配且只能用 V2001，才用 `casez` + `?`，并在块前加断言检查选择子不含 x。

### 3.4 有意的优先级：写 `if-else` 链，不要靠 case 分支重叠 `[通用]`

`[业界]` Cummings SNUG'99 §4.7："Code all intentional priority encoders using if-else-if statements."
理由有两层：① Verilog 的 case 允许 item 重叠，重叠时按书写顺序取第一个匹配，于是**隐式**生成优先级链——不可读，也是 `parallel_case` 改变功能的温床；② 优先级链是串行 MUX 级联，深度 = 分支数，关键路径远长于一层并行 MUX。

`[教材]` p.185 例 13.7 引言从正面说了同一件事："如果条件语句（case 或 if-else）中分支条件是互斥的话，综合器能自动地生成并行的多路器。"

**正例**（已过 `rtl_lint.py`：verilator 0 警告 + yosys `check` 通过）：

```verilog
// 组合逻辑标准骨架：先赋默认值，再用条件覆盖
always @(*) begin
    data_o  = {WIDTH{1'b0}};        // 先赋默认值 —— 防 latch 最可靠的手段
    valid_o = 1'b0;
    case (sel_i)
        2'b00: begin data_o = data_i;                    valid_o = 1'b1; end
        2'b01: begin data_o = ~data_i;                   valid_o = 1'b1; end
        2'b10: begin data_o = {data_i[WIDTH-2:0], 1'b0}; valid_o = 1'b1; end
        default: ;                  // 三个分支之外用默认值
    endcase
end

// 有意的优先级编码器：用 if-else 链表达
always @(*) begin
    gnt_o = 2'd0;
    if      (req_i[3]) gnt_o = 2'd3;
    else if (req_i[2]) gnt_o = 2'd2;
    else if (req_i[1]) gnt_o = 2'd1;
    else if (req_i[0]) gnt_o = 2'd0;
end
```

### 3.5 `for` 与 `generate`：它们是"复制粘贴"，不是循环 `[通用]`

综合器把 `for` **完全展开**成 N 份并行硬件。所以：

- 边界必须是常量（`SKILL.md` G7）。`[教材]` p.381 可综合(15) 的原话只是提醒——"仔细检查代码中使用动态指针、循环声明或算术运算的部分，这类代码综合后会生成大量的门且很难优化"——**没有直接规定边界必须为常量**，此处按现代综合器的实际限制收紧，与 `SKILL.md` 一致。
- 循环变量用 `integer` 是可以的：它在展开后不存在，不是设计信号，因此不与 `SKILL.md` D6 冲突。
- `[教材]` p.74 明确：**Verilog 不支持 `i++`**，必须写 `i = i + 1`。
- `[教材]` p.75 思考题 9 的经典误解：把 `for` 放进 `always @(posedge clk)` **并不会**让每次迭代占一个时钟周期——整个循环在同一仿真时刻零延迟展开完。要按节拍推进只能在 testbench 里写 `@(posedge clk)`。
- 块内声明局部变量时，`begin` 必须命名 `[教材]` p.182 例 13.3 原注释："此处 begin-end 块必须有一模块名，因为块中定义了局部变量"。

**`generate` 同理**：`[教材]` p.69 说得很清楚——"在仿真开始之前，仿真器会对生成块中的代码进行确立(展平)"，`genvar` "在确立后的仿真代码中……是不存在的"。三条硬约束：循环生成块**必须命名**（否则无法层次引用 `xor_loop[k].g1`，波形查看、断言绑定、SDF 反标全依赖这个名字，`[教材]` p.69）；**同一个 genvar 不能用于相互嵌套的循环生成**（p.69）；**任务和函数声明不能出现在循环生成当中**（p.67）。

条件生成最容易踩的坑是**漏赋值**：`generate if` 少写一个 `else` 分支，得到的是**悬空网线**（未驱动），而不是 latch——工具报的是 `UNDRIVEN` 一类告警，别照着 latch 去查。下面这段两个分支都驱动了 `data_o`，已过 `rtl_lint.py`：

```verilog
genvar g;
generate
    for (g = 0; g < N; g = g + 1) begin : xor_loop     // 块必须命名
        assign xor_o[g] = a_i[g] ^ b_i[g];
    end
endgenerate

generate
    if (STAGE == 0) begin : g_bypass
        assign data_o = b_i;
    end else begin : g_pipe
        reg [N-1:0] pipe_r [0:STAGE-1];
        integer j;
        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                for (j = 0; j < STAGE; j = j + 1) pipe_r[j] <= {N{1'b0}};
            end else begin
                pipe_r[0] <= b_i;
                for (j = 1; j < STAGE; j = j + 1) pipe_r[j] <= pipe_r[j-1];
            end
        end
        assign data_o = pipe_r[STAGE-1];
    end
endgenerate
```

### 3.6 `task` 与 `function` `[通用]`

**`function` 可综合**，但必须守住 `[教材]` p.85 的 4 条规则：

1. 定义中**不能包含任何时间控制**（`#`、`@`、`wait`）——这正是它能映射为纯组合逻辑的原因；
2. 不能启动 task；
3. 至少一个输入参数；
4. 必须给与函数同名的内部变量赋值作为返回值。

两个高频坑：**忘记写返回位宽 → 默认只有 1 位，高位被截掉** `[教材]` p.85；**普通 function 不能递归、并发调用结果不确定**（局部变量是静态分配的）`[教材]` p.88。需要递归/重入要用 `automatic`，但综合支持要查工具手册。

**`task` 谨慎**：教材 p.83 允许 task 有 `inout`，p.182 例 13.3 甚至在组合 always 里调用带 `inout` 的 `sort2`。但调研文件自己标注了风险：`[业界]` W04 §四 U-注 指出含 `inout` 参数的 task 在很多现代综合器中支持有限甚至不可综合，静态 task 在多次调用时还有变量共享隐患。**本规范：设计模块里只用 `function`，不用 `task`**；带时间控制的 task（如 `[教材]` p.84 例 6.9 交通灯，教材自己说"只是一个行为模块，不能综合成电路网表"）只出现在 testbench。

### 3.7 `initial`、延迟、`fork/join` `[通用]`

- `initial` 只在 0 时刻执行一次，对应不了任何持续存在的硬件 `[教材]` p.79。它的正当用途是 testbench 的初始化与激励。
- **延迟**：`[工具]` 实测把 `q_o <= #1 r;` 交给两个工具，结果完全相反——
  - Verilator `--lint-only -Wall`：**直接报错** `%Error-NEEDTIMINGOPT`
  - Yosys：**静默忽略延迟**，照样生成两个触发器
  这就是"综合丢掉延迟、仿真保留延迟"的 pre/post-synthesis mismatch。`[业界]` lowRISC 的措辞是："All forms of `#delay`, including `#0`, are not permitted."
- `fork/join`：`[教材]` p.64-65 说明并行块内语句"执行的顺序是由各自语句内延迟或事件控制决定的"，且"如果两条语句在同一时刻对同一个变量产生影响，那么将会引起隐含的竞争"。这是仿真调度概念，没有硬件对应物。

### 3.8 UDP 与 `specify` `[通用]`

**UDP**（`primitive … endprimitive`）是查真值表的基本元件建模手段，`[教材]` p.137-138 给了 6 条硬约束：只能有一个输出且必须是端口表第一项；最多 10 个输入；所有端口必须是标量（1 位）；真值表里只允许 0/1/X，**不允许 z**；只有输出可以是 reg；`initial` 只能赋 0/1/X。

关键在教材 p.138 的角色划分：**"对于数字系统的设计人员来说，只要了解 UDP 的作用就可以了；而对微电子行业的基本逻辑元器件设计工程师，必须深入了解 UDP 的描述。"** ——UDP 属于**库单元建模**，不属于系统设计。`SKILL.md` I 禁止它出现在设计 RTL 里，与教材的角色划分一致。

**`specify` 块**同理：它描述的是单元的路径延迟/时序检查（setup/hold），是库和 SDF 反标的载体，不是设计描述。

### 3.9 memory（reg 数组） `[通用]`

`[教材]` p.34 定义 `reg [n-1:0] mem [m-1:0];`，并强调两点：**Verilog 中没有多维数组**；**存储器不能整体赋值**（`mema = 0;` 非法，必须 `mema[3] = 0;`）。

> ⚠️ **教材同一页自相矛盾**：先写"对存储器进行地址索引的表达式必须是常数表达式"，随后又写"进行寻址的地址索引可以是表达式……例如可以用一个加法计数器来做 RAM 的地址索引"。按后一句执行（这也是 IEEE 语义与全部工程实践）。前一句照实记录，不予采信。

RAM/ROM 推断的具体写法（读写端口数、是否带输出寄存器、FPGA BRAM vs ASIC 编译宏）见 `references/09-memory-and-primitives.md`。

---

## 4. SystemVerilog 可综合子集 `[SV]`

本规范的默认基线是 Verilog-2001（见 `SKILL.md` 开头「适用标签」一段）。用 SV 时**只放行下面这些构造**，且每一条都要先在目标综合器上确认。

### 4.1 `logic` —— 替代 `reg`/`wire`，但它不是万能的

`[业界]` lowRISC："`logic` is preferred over `reg` and `wire`"。价值在于它是**变量**、只能有一个驱动源，让编译器/lint 替你查多驱动。

⚠️ 一个容易被忽略的语义变化 `[业界]` Mills SNUG 2012 §6.0：**SV-2005 里 `logic` 是 type，SV-2009 起是 value set**；`input logic` 会被推断成 `input wire logic`（net，可多驱动），要变量得写 `input var logic`。Mills 本人对此的评价是 "YUCK!"。所以"`logic` 保证单驱动"这个说法对**内部信号**成立，对**输入端口**不成立。

### 4.2 `always_comb` vs `always @*` —— 敏感表语义**真的不同**

这是从 V2001 迁移到 SV 时最隐蔽的行为变更，`[业界]` W08-02 用两份 LRM 原文逐字印证：

- **IEEE 1800**：`always_comb` 的隐式敏感表排除 "**Any expression that is also written within the block**"
- **IEEE 1364-2005 §9.7.5**：`@*` 只排除"仅作为左值出现"的标识符，并给出 Example 2 —— `always @*` 里 `tmp1 = a & b; tmp2 = c & d; y = tmp1|tmp2;` 的注释明写 "equivalent to `@(a or b or c or d or tmp1 or tmp2)`"，即 **`@*` 会把 tmp1/tmp2 算进敏感表，`always_comb` 不会**。

后果：`always_comb begin c = b; b = a; end` 这种**先读后写**的写法，在 `always @*` 下"碰巧能跑"，换成 `always_comb` 后 `a` 变化时 `c` 拿到旧 `b`，且块不会因 `b` 变化而重触发——**静默出错**。

`SKILL.md` C5 的措辞（"任何变量必须先赋值后使用，禁止在赋值之前读取本块将要写的变量"）已经堵死了这个坑；本节是它的论证。迁移老代码到 `always_comb` 必须配回归仿真。

`always_comb` 还有三条 `always @*` 没有的语义 `[业界]` IEEE 1800 §9.2.2.2.2（W08-03、W04-03 均逐字引用）：零时刻自动执行一次；对**函数体内部**引用的信号也敏感（`@*` 只对函数实参敏感，Sutherland 直接称之为 `always @(*)` 的 "a bug"）；左值不得被其他进程写。

⚠️ **`always_comb` 不是锁存器防火墙**：`[业界]` W08-10 指出 LRM 用的是 "it is **recommended that** software tools perform additional checks"——非强制。Vivado 只发 WARNING（Synth 8-327）不报错。防 latch 仍然靠 §3.1 的编码纪律 + 把 lint 告警升级为 error。

### 4.3 `always_ff` / `always_latch`

`always_ff` 声明"这里应该出综合出触发器"，`always_latch` 声明"这里我**故意**要 latch"。价值是工具能反查意图，`[业界]` Sutherland SNUG SV 2013 给了 Design Compiler 的确切告警号：`always_comb` 里出 latch → `ELAB-974`；`always_latch` 里没有 latch → `ELAB-975`；`always_ff` 里没有触发器 → `ELAB-976`。

`always_latch` 在本规范里只有一个合法场景：时钟门控单元的行为模型（`[业界]` OpenTitan `prim_clock_gating.sv` 就是 `always_latch`），而它在 ASIC 流程中会被库里的 ICG 标准单元替换掉。

### 4.4 `typedef` ✅

纯编译期构造，展开后不存在。用它给状态类型、总线拍类型命名，可综合性无争议。约束：类型定义放 `package` 或 `.svh` 里，一处定义多处引用，不要在每个模块里各写一份。

### 4.5 `enum` ✅ —— 但编码权在谁手里要想清楚

`[业界]` lowRISC："State machines use an enum to define states"；`[业界]` Cummings SNUG 1998："make state assignments using parameters with symbolic state names"。用 `enum` 的好处是编码（binary / gray / one-hot）成为综合脚本里的一个开关，而不是写死在 RTL 里。

⚠️ 反面：`[业界]` W08 D-07 指出 Vivado 支持 `fsm_encoding` / `fsm_extract` 属性，即**综合工具会自行重编码**，除非显式关掉。安全关键设计必须把这一点写进约束，否则 formal 的状态映射和你以为的编码对不上。

### 4.6 packed `struct` / `union` ✅

packed 聚合类型在硬件上就是一根按字段切分的总线，可综合性无争议，且比手工 `[31:24]` 位切片安全得多。约束：

- **只用 packed**。unpacked struct / 非 packed 数组做端口，各工具支持差异大。
- 复位时写 `beat_q <= '0;`（`'0` 是 SV 的 fill literal，随上下文宽度填 0），不要逐字段赋。
- 别把 packed struct 当"可以省位宽检查"的借口——赋值两侧位宽仍然必须相等（`SKILL.md` G3）。

### 4.7 `package` ⚠️ / `interface` ⚠️

**`package`**：本规范**允许**，用来放 `typedef` / `localparam` / 可综合 `function`。三条实测约束 `[工具]`：

1. **package 单独成文件，文件名 == package 名**。否则 Verilator 报 `DECLFILENAME: Filename 'x' does not match PACKAGE name: 'x_pkg'`（这与 `SKILL.md` A2 是同一条规则的延伸）。
2. **Yosys 0.33 不接受模块头 import**（`module m import pkg::*; (...)` → `syntax error, unexpected TOK_ID`），**也不接受模块体内的 `import pkg::*;`**（→ `unexpected TOK_PACKAGESEP`）。可移植写法是**全限定名** `pkg::NAME`，两个工具都过。
3. **Yosys 0.33 不支持 `$bits(<类型名>)`**；把位宽写成 `localparam` 由字段宽度推出来即可。

**`interface`**：`SKILL.md` H1 已经禁止 `.*`，而 interface 的主要卖点恰恰是"少写连线"。综合器对 `modport`、`interface` 内含 `always` 块的支持差异很大，`[业界]` Sutherland 的 SV 可综合子集论文（W04-S7）正是因为"IEEE 没有定义可综合子集"而写的。**本规范默认：跨模块边界用显式端口 + packed struct，不用 interface。** 项目要用必须先做工具实测并在 `references/14-disputes.md` 登记。

### 4.8 `unique` / `priority` ⚠️ —— 不是银弹

`[业界]` Mills SNUG 2012 §4.2b 用实例证明：`unique case` 下如果每个输出没有在所有分支被赋值，**"no violation reports are generated, yet latches will be modeled"**。原因是正交的：`unique`/`priority` 检查的是 **case item 集合**的互斥/完整性，latch 推断看的是**某输出在某可达路径未被赋值**。

业界对"要不要到处加"本身有分歧：lowRISC 要求一律 `unique case`（把仿真断言失败当收益）；Cummings SNUG Israel 2005 明确反对全加（"取值域天然不满"的高效写法会被刷屏 run-time error）。本规范取舍：**取值域受控且可断言的场景（状态、操作码）加 `unique`；其余用普通 `case` + `default`。无论哪种都不能省掉块首默认赋值。**

### 4.9 SV 正例（已过 `rtl_lint.py --sv`：verilator 0 警告 + yosys `check` 通过）

```systemverilog
// 文件 synth_sv_demo_pkg.sv —— package 单独成文件，文件名 == package 名
package synth_sv_demo_pkg;
    localparam int unsigned PAYLOAD_W = 8;
    localparam int unsigned BEAT_W    = PAYLOAD_W + 1;
    typedef enum logic [1:0] { ST_IDLE = 2'b00, ST_RUN = 2'b01, ST_DONE = 2'b10 } state_e;
    typedef struct packed { logic [PAYLOAD_W-1:0] payload; logic last; } beat_t;
endpackage
```

```systemverilog
// 文件 synth_sv_demo.sv
module synth_sv_demo (
    input  logic clk,
    input  logic rst_n,
    input  logic start_i,
    input  logic done_i,
    input  logic [synth_sv_demo_pkg::PAYLOAD_W-1:0] payload_i,
    output logic [synth_sv_demo_pkg::BEAT_W-1:0]    beat_o,
    output logic busy_o
);
    // 用 pkg:: 全限定名，不写 import —— Yosys 0.33 不接受 import（见 §4.7）
    synth_sv_demo_pkg::state_e state_q, state_d;
    synth_sv_demo_pkg::beat_t  beat_q,  beat_d;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q <= synth_sv_demo_pkg::ST_IDLE;
            beat_q  <= '0;
        end else begin
            state_q <= state_d;
            beat_q  <= beat_d;
        end
    end

    always_comb begin
        state_d = state_q;      // 次态默认保持：来自寄存器的组合反馈，不是 latch
        beat_d  = beat_q;
        busy_o  = 1'b0;
        case (state_q)
            synth_sv_demo_pkg::ST_IDLE:
                if (start_i) begin
                    beat_d.payload = payload_i;
                    beat_d.last    = 1'b0;
                    state_d        = synth_sv_demo_pkg::ST_RUN;
                end
            synth_sv_demo_pkg::ST_RUN: begin
                busy_o = 1'b1;
                if (done_i) begin
                    beat_d.last = 1'b1;
                    state_d     = synth_sv_demo_pkg::ST_DONE;
                end
            end
            synth_sv_demo_pkg::ST_DONE: state_d = synth_sv_demo_pkg::ST_IDLE;
            default:                    state_d = synth_sv_demo_pkg::ST_IDLE;
        endcase
    end

    assign beat_o = beat_q;
endmodule
```

---

## 5. `[FPGA]` 与 `[ASIC]` 做法相反的地方

### 5.1 `initial` 与声明初值 —— **这是本篇最大的一处分道扬镳**

| | `[FPGA]` | `[ASIC]` |
|---|---|---|
| 结论 | 可用，会进 bitstream | **禁止依赖** |
| 一手依据 | AMD UG901 v2025.1 Ch.9 逐字："When you assign a register as an initial value in a declaration, **Vivado synthesis sets this value on the output of the register at global reset or power up.** … The value is carried in the Verilog file as an **INIT attribute** on the register. **The value is independent of any local reset.**" | 普通标准单元触发器**没有上电确定值**，硅上没有对应机制 |

`[工具]` 本机实测印证了这个机制：`initial q_o = 1'b0;` 被 Yosys 的 `PROC_INIT` pass 抽成寄存器的 **init 属性**（日志：`Set init value: \q_o = 1'0`），Verilator lint 完全干净——即"工具不会拦你"。

**为什么相反**：FPGA 的配置比特流本来就要把每个触发器的初态写进去，白送；ASIC 上要做到同样的事得付出一个复位网络的代价，所以只能靠复位。

**本规范做法**：可移植 RTL 不依赖声明初值；FPGA-only 的模块可以用，但**必须在文件头注明 "FPGA-only, relies on bitstream INIT"**，与 `SKILL.md` I 的"`initial` 禁止（`[FPGA]` 例外见 references）"对齐。

### 5.2 latch

| | `[FPGA]` | `[ASIC]` |
|---|---|---|
| 结论 | 直接禁 | 也禁，但理由不同 |
| 理由 | 映射成 `LD` 单元，时序不可预测、吃 LUT；Vivado 报 `WARNING: [Synth 8-327] inferring latch for variable '<name>'`（`[业界]` UG901 Ch.5 逐字） | 库和 STA 能支持 latch（time borrowing），但**扫描链插入困难**（latch 不能直接做扫描单元）`[业界]` lowRISC + Verilator `LATCH` 定义 |

可执行化：`[业界]` W08-25 建议 CI 里 grep `Synth 8-327`，命中即 fail；Cell Usage 出现 `LD` 且不在白名单内即 fail。

### 5.3 三态与 `inout`

| | `[FPGA]` | `[ASIC]` |
|---|---|---|
| 内部三态 | 综合器**自动转成 LUT 逻辑**——UG901 逐字："An inferred BUFT is converted automatically to logic realized in LUTs by Vivado synthesis." | **强制禁止**：上电/复位释放窗口内多驱动器同时使能会发生总线竞争，瞬时短路电流可能损伤器件；ATPG 还要额外生成竞争检查向量 `[业界]` Cummings SNUG 2003 §4.3 |

两边结论一致（`SKILL.md` H4：顶层之外不要出现 `inout`/三态），但**代价不同**：FPGA 是"白白浪费资源"，ASIC 是"可能烧片"。

### 5.4 除法器、乘法器与复位

`[FPGA]` 乘法优先落到 DSP 硬核，除法一般调 IP 或写多周期迭代；`[ASIC]` 乘除交给综合器算子库（DesignWare 之类）选架构。两边共同的红线是 §2.2 那个实测数字：**8 位变量除数在 yosys 默认流程下是 371 个门，常量 2 的幂除数是 0 个门**。写除法前先问"除数是不是常量"。

> ⚠️ 资源共享（把互斥使用的乘法器合并）的具体规则，`[业界]` W04 §四 U3 明确标注**未取到任何一手出处**。本规范不写规则，只写做法：用目标工具的 `report_resources` 实测，不要当作可移植规则。

复位策略上两边同样相反（Xilinx 倾向同步、lowRISC/ASIC 主流异步低有效 + 同步释放），且一手资料自己改过口（Cummings/Mills 2002 推荐异步 → 2003 加入 Golson 后转为中立，原话 "almost become a religious issue"）。这属于 `references/06-clock-reset-cdc.md`，本篇只强调它**不是可综合性问题**——两种写法都可综合，区别只在敏感表（`SKILL.md` E2）。

---

## 6. 本篇检查清单

写完一个设计模块，逐项打勾：

- [ ] 模块里没有 `initial`、`#延迟`、`fork/join`、`while/repeat/forever`、`wait`、`force/release`、`disable`、`assign/deassign`
- [ ] 没有 `$display`/`$finish`/`$fopen`/`$dumpvars` 等系统任务（`$signed`/`$clog2`/`$bits` 除外）
- [ ] 没有 UDP（`primitive`）、`specify` 块、`defparam`、跨模块层次引用
- [ ] 没有 `real`/`realtime`/`time`；`integer` 只出现在 for 循环变量和常量计算里
- [ ] 没有 `===` / `!==`（它能过综合，但和仿真不等价）
- [ ] 没有 `casex`；用了 `casez` 的地方只在 case item 里写 `?`，并且能说清为什么必须通配
- [ ] 每个 `case` 有 `default`，每个 `if` 有 `else`（或块首已赋默认值）
- [ ] 组合 always 块**块首给所有被写对象赋了默认值**——包括临时量、结构体字段、向量全位
- [ ] 组合块里没有"先读后写"同一变量（这在 `always @*` 与 `always_comb` 下语义不同）
- [ ] 所有 `for` 的边界是常量；块内声明局部变量的 `begin` 都命名了
- [ ] `function` 写了返回位宽、至少一个输入、没有任何时间控制；设计模块里没有 `task`
- [ ] `generate` 的每个分支都驱动了同一批输出（条件生成漏赋值得到的是**悬空网线**，不是 latch）
- [ ] 除法/取模的除数是常量；否则已经确认过门数代价
- [ ] `[SV]` package 单独成文件、文件名 == package 名；跨 package 引用用全限定名而非 `import`
- [ ] `[SV]` 只用了 packed struct/union；没有 `interface`、`class`、队列、动态数组、`string`
- [ ] `[FPGA]` 若依赖声明初值/`initial`，文件头已注明 "FPGA-only, relies on bitstream INIT"
- [ ] `python3 scripts/rtl_lint.py --top <top> --synth <file>` 输出 `通过 ✔`

---

## 7. ⚠️ 与主规范的冲突

**没有发现实质性冲突。** 本篇所有条目与 `SKILL.md` 铁律一致。以下三点是**措辞可能被误读的地方**，提请上层裁决是否要在 `SKILL.md` 里补一句：

1. **`SKILL.md` D6「不要用 `integer` / `time` 做设计信号」**与 for 循环变量必须是 `integer`/`reg` 的现实。本篇 §3.5 的解释是"循环变量在展开后不存在，不是设计信号，故不冲突"。若上层认可，建议 D6 补一个括注：「（for 循环变量不在此列）」。

2. **`SKILL.md` C1 例外条款要求刻意建 latch 时用 `<=`**（依据 `[教材]` p.197 原则(2) + Cummings Guideline #2），而 `[教材]` p.180 13.3(4) 说的是「如果要为电平敏感的锁存器建模，使用**连续赋值语句**是最简单的方法」。**这是教材内部两处建议不一致**，不是 SKILL.md 的错。现代主流做法是第三种：`always_latch` + 显式注明意图。建议在 `references/03-combinational-logic.md` 里三种写法并列，`SKILL.md` 不动。

3. **`SKILL.md` G5「`casez` 仅在明确知道自己在做什么时使用」偏宽松**：`[业界]` Mills SNUG 2012 的原话是 `casez` **也有固有 sim/synth mismatch**，据此有人主张 `casez` 一并禁掉。本篇按 SKILL.md 保留了"谨慎使用"，但把机理和反对意见写清了（§3.3）。若上层想收紧成"V2001 也禁 casez，通配一律用 if-else 链"，本篇不需要改结构，只改 §3.3 结论一句。

另外记录两处**教材自身的问题**（不影响 SKILL.md）：

- `[教材]` p.34 同一页先说"对存储器进行地址索引的表达式必须是常数表达式"，随后又说地址可以用计数器——**自相矛盾**，本篇按后者执行（§3.9）。
- `[教材]` p.67 把「parameter、localparam、端口声明、指定块」列为**不允许出现在 generate 范围**的模块项。`[工具]` 实测：`localparam` 写在 `generate for` 块内，**Verilator 5.024 与 Yosys 0.33 都接受并正确展开**（探针 `probe_genlp.v`：lint 0 警告、yosys `check` 通过）。教材这条黑名单相对当代工具过严，本篇未收录该禁令；教材 p.67 中确实成立的一条——**任务和函数声明不能出现在循环生成当中**——已收在 §3.5。
