# 03 · 组合逻辑与锁存器规避

> 本篇是 `SKILL.md` 铁律 **C1~C5**、**G2**、**G5**、**G6** 的展开与论证。铁律以 `SKILL.md` 为准，本篇只解释机理、给边界、给证据。
> 默认基线 **Verilog-2001**；`[SV]` 段落只在项目允许 SystemVerilog 时适用。

---

## 本篇速览

1. **能用 `assign` 就用 `assign`**；必须用过程块时，`[V2001]` 一律 `always @(*)`，`[SV]` 一律 `always_comb`，**任何情况下都不手写敏感表**。
2. **`always @(*)` 与 `always_comb` 的隐式敏感表不等价**：`@(*)` 会把"块内被写、同时又被读"的中间量算进敏感表，`always_comb` **明文排除**它们（IEEE 1364-2005 §9.7.5 vs IEEE 1800 §9.2.2.2.1）。因此"先读后写"的代码在 `@(*)` 下碰巧能跑，换成 `always_comb` 会**静默出错**。
3. **防锁存器的唯一可靠手段是：块首先给本块所有被写对象赋默认值**，再用 `if`/`case` 覆盖。补 `else`、补 `default`、加 `unique`/`priority`、换 `always_comb` —— **都不能替代这一条**。
4. **`casex` 禁用**，`casez` 仅在通配且只写 `?` 时谨慎使用；`case` 各分支位宽必须一致，禁止用 `'bx` 代替 `n'bx`。
5. **`full_case` / `parallel_case` 无条件禁止**——它们只对综合器说话、不对仿真器说话，"最危险的时候正是它生效的时候"。
6. **组合块内禁止环路**（本块赋值的变量在本块中被**先读后写**、或 `assign y = en ? d : y;`）。环路没有稳态，STA 无法分析，ATPG 无法建模。

---

## 1. 组合逻辑的三种写法与优先顺序

### 03-01 能用连续赋值 `assign` 就不要用 `always` `[通用]` `[业界]` lowRISC Style Guide "Prefer assign statements wherever practical." `[教材]` p.183 例 13.4/13.5

`assign` 天然不可能推断锁存器——连续赋值在所有输入组合下都驱动左值，不存在"某条路径没赋值"这回事。它同时省掉了敏感表、`reg` 声明、块首默认赋值这三处出错点。

```verilog
// 正例：三个可直接抄的连续赋值组合逻辑
assign equal  = (a == b);              // 比较，教材 p.183 例 13.4
assign onehot = 8'b1 << sel;           // 3-8 译码，教材 p.183 例 13.5
assign y      = sel ? a : b;           // 二选一，教材 p.185 例 13.7 方案一
```

> 教材 p.183 例 13.5 原文写的是 `assign out = 1'b1<<in;`。按 IEEE 1364-2005 Table 5-22，移位表达式的位宽是**左操作数**的位宽，这里靠连续赋值的上下文位宽才扩到 8 位。**本规范要求写成 `8'b1 << in`**，不依赖上下文倒推（见 `references/07-datapath-and-width.md`）。

真值表式多路译码、指令译码、FSM 次态逻辑用 `always` 块可读性更好；除此之外优先 `assign`。

### 03-02 组合 `always` 块内只用阻塞赋值 `=` `[通用]` `[教材]` p.197 原则(3)、p.146、p.182 `[业界]` lowRISC / Cummings Golden Rules

= 铁律 C1。理由见 `references/04-sequential-logic.md`（分层事件队列）。这里只强调一个容易被忽略的后果：**组合块里用 `<=` 不会立刻报错，也不一定综合成锁存器**，但块内多条语句之间的"顺序生效"关系没了——`tmp <= a & b; y <= tmp | c;` 里的 `y` 拿到的是**上一次**的 `tmp`，仿真出的是一拍延迟，综合出的却是纯组合，典型的仿真-综合不一致。`[工具]` Verilator `COMBDLY` 专查这一类。

### 03-03 组合 `always` 块中被赋值的信号必须声明为 `reg`，但综合出来的**不是**触发器 `[V2001]` `[教材]` p.146-147、p.180 13.4(5)

`reg` 只是"可以在过程块里被赋值"的数据类型标记，与是否推断触发器无关。判断依据是**敏感表有没有 `posedge`/`negedge`**（`[教材]` p.180 13.4(3)：「带有 posedge 或 negedge 关键字的事件表达式表示沿触发的时序逻辑，没有……的表示组合逻辑或电平敏感的锁存器」）。`[SV]` 用 `logic` 代替 `reg`，语义更干净。

---

## 2. 敏感表：`always @(*)` 与 `always_comb` 的真实语义差异

**两者不是"新旧写法"的关系——敏感表的构造规则在标准正文里就不一样。**

### 03-04 禁止手写敏感表 `[通用]` `[业界]` IEEE 1364-2005 §9.7.5；Mills & Cummings SNUG'99 §2.1；lowRISC `[教材]` p.181、p.146-147

IEEE 1364-2005 §9.7.5 *Implicit event_expression list* 原文：

> *"The event_expression list of an event control is a common source of bugs in register transfer level (RTL) simulations. Users tend to forget to add some of the nets or variables read in the timing control statement. This is often found when comparing RTL and gate-level versions of a design."*

机理：**仿真按事件驱动，综合按数据流建锥。** 漏一个信号，仿真器不调度这个进程、输出保持旧值；综合器不看敏感表，照样把它接进组合锥。于是 RTL 仿真通过、门级仿真失败——而这通常要到流程后段才暴露。

`[教材]` p.181 用同一现象解释得更直白：「如果在赋值表达式右端引用了敏感电平列表中没有列出的信号，那么在综合时，将会为该没有列出的信号隐含地产生一个透明锁存器。……纯组合逻辑电路不可能做到这一点。」

教材的结论是"把信号列全"，本规范的结论是**"根本不要手写"**——列全是人工纪律，`@(*)` 是编译器保证。教材成书时代 Verilog-1995 没有 `@*`，这属于时代性差异，不是教材有错（教材调研文件 G02 §四 3 自己也标注了）。

```verilog
always @(a)  y = a & b;   // 反例，不要抄：漏了 b，b 变化时 y 不更新
always @(*)  y = a & b;   // 正例（V2001）
```

### 03-05 `always @(*)` 的敏感表排除规则 `[V2001]` `[业界]` IEEE 1364-2005 §9.7.5 逐字

`@*` 把块内**读到**的所有 net/variable 放进敏感表，只排除两类：*"Identifiers that only appear in wait or event expressions"*，以及 *"Identifiers that **only** appear as a hierarchical_variable_identifier in the variable_lvalue of the left-hand side of assignments"*。注意第二条里的 **only**。标准自带的 Example 2：

```verilog
// IEEE 1364-2005 §9.7.5 Example 2 原文（等价敏感表见注释）
always @* begin // equivalent to @(a or b or c or d or tmp1 or tmp2)
    tmp1 = a & b;
    tmp2 = c & d;
    y    = tmp1 | tmp2;
end
```

`tmp1`/`tmp2` 既被写又被读，**不满足 "only appear as lvalue"，因此会被算进敏感表**。

### 03-06 `always_comb` 的敏感表排除规则与 `@*` 不同 `[SV]` `[业界]` IEEE 1800 §9.2.2.2.1 逐字

> *"The implicit sensitivity list of an always_comb includes the expansions of the longest static prefix of each variable or select expression that is read within the block or within any function called within the block **with the following exceptions: a) Any expansion of a variable declared within the block or within any function called within the block; b) Any expression that is also written within the block or within any function called within the block**."*

**b) 条把"块内被写的变量"整个排除出敏感表**——这正是 `@*` 会包含的那一类。

### 03-07 【核心结论】组合块内禁止"先读后写"同一变量 `[通用]`（`[SV]` 下是硬错误，`[V2001]` 下是碰巧能跑）

```verilog
// 反例，不要抄：always_comb 下 a 变化时 c 拿到旧 b，
// 因为 b 被本块写过，不在敏感表里，块不会因 b 变化而重触发
always_comb begin
    c = b;
    b = a;
end

// 正例：按依赖顺序写，先写后读
always_comb begin
    b = a;
    c = b;
end
```

同样的代码换成 `always @(*)`：按 §9.7.5，`b` 在敏感表里，块会被 `b` 的变化二次触发从而收敛到正确值——**"碰巧能跑"**。所以：① 从 `always @(*)` 迁移到 `always_comb` **必须配合回归仿真**，这是最隐蔽的行为变更之一；② 无论哪种写法，**"先写后读"的中间临时量是合法且推荐的**（`@*` 的 Example 2 就是这个模式），被禁的只是**"先读后写"**；③ `[工具]` Verilator `ALWCOMBORDER` 就是查这个。

> `[业界]` 关于"`always_comb begin c=b; b=a; end` 的**综合**结果"，W08 调研明确标注：**仿真侧已由 LRM 逐字印证，综合侧无一手出处**。多数综合工具对这种写法是推锁存器或报 warning，而不是简单按数据流合并。**结论：不要写，不要猜。**

### 03-08 `always_comb` 相对 `@*` 的另外三条差异 `[SV]` `[业界]` IEEE 1800 §9.2.2.2.2（DVCon Weihua Han 逐字引 LRM）

> *"— always_comb automatically executes once at time zero, whereas always @* waits until a change occurs on a signal in the inferred sensitivity list.
> — always_comb is sensitive to changes within the contents of a function, whereas always @* is only sensitive to changes to the arguments of a function."*
>
> *"the variables written on the left-hand side of assignments shall not be written to by any other process."*（例外：*"multiple assignments made to independent elements of a variable are allowed as long as their longest static prefixes do not overlap"*）

三条含义：① **零时刻自触发**，不会出现"仿真开始后输出一直是 X 直到第一次输入变化"；② **穿透函数体**——`always @(*) y = f(x);` 只对实参 `x` 敏感，`f` 内部引用的全局信号变了不会重算，Sutherland 直接称之为 *"a bug with `always @(*)`"*；③ **单一写者**，工具可静态查多驱动。这三条是本规范在 SV 项目中**要求**用 `always_comb` 的理由。

### 03-09 `always_comb` **不是**锁存器防火墙 `[SV]` `[业界]` IEEE 1800 §9.2.2.2.1 措辞；AMD UG901

LRM 的措辞是 *"it is **recommended that** software tools perform additional checks…"* —— 是 `should`，不是 `shall`。工具行为因此各不相同：Vivado 只发 **WARNING**（`[Synth 8-327] inferring latch for variable '<name>'`，Cell Usage 里出现 `LD`），Design Compiler 报 `ELAB-974`。

**防锁存器靠编码纪律（第 3 节）+ 把 lint/综合告警升级为 error，不靠关键字。**

---

## 3. 意外锁存器：所有成因与唯一可靠的规避手法

### 3.1 机理 `[教材]` p.56

原文：「在"always"块内，如果在给定的条件下变量没有赋值，这个变量将保持原值，也就是说会生成一个锁存器。」「Verilog HDL 设计中容易犯的一个通病是……生成了并不想要的锁存器。」

"保持原值"就是记忆，组合逻辑没有记忆，综合器只能插一个电平敏感的透明锁存器把旧值存住。**为什么必须避免**：latch 是电平敏感的，`[ASIC]` STA 要做 time borrowing 分析、扫描链插入困难（latch 不能直接做扫描单元）；`[FPGA]` 上映射成 `LD` 原语，时序难以约束且吃资源。

### 3.2 意外锁存器的成因清单 `[通用]` `[业界]` AMD UG901 Ch.5 "Latches"；Don Mills SNUG 2012；W08 交叉取证

| # | 成因 | 备注 |
|---|------|------|
| 1 | `if` 无 `else` | `[教材]` p.56 图 5.1 |
| 2 | `case` 无 `default` | `[教材]` p.57 图 5.2 |
| 3 | `default` 存在，但**没有给全部输出赋值** | 最常见的漏网之鱼 |
| 4 | 不同分支赋**不同的信号**（A 分支赋 y，B 分支赋 z） | 见 §6 的实证例子 |
| 5 | 只赋了向量的**部分位段**（`y[3:0]=...` 而 `y[7:4]` 没赋）或数组的**部分元素** | |
| 6 | 可能执行 **0 次**的 `for` 循环里才赋值；或循环体内条件赋值、某些迭代不赋 | |
| 7 | 中间临时量**先读后写**（§03-07） | `@*` 与 `always_comb` 行为还不同 |
| 8 | `function` 返回路径不全、函数局部变量赋值不全、`task` 的 output 某些路径未赋 | `[业界]` lowRISC: *"Do not infer a latch inside a function"* |
| 9 | 提前退出（`return` / `disable`）跳过了后面的赋值 | |
| 10 | 通配 `case`（`casez`/`casex`）所有 item 都不匹配 | 含 case 表达式为 X 的情形 |
| 11 | FSM 次态只在"要跳转"时赋值，保持时不赋 | 解法就是 `next_state = state;` |
| 12 | 敏感表漏项（手写敏感表时） | `[教材]` p.181 |

**两个常被误判、其实不是锁存器的情形**（`[业界]` W08 交叉取证确认这两条 Codex 判断正确）：

- `generate` 里的 `if` 没有 `else` → 产生的是**未驱动的 net**，不是锁存器（症状是悬空线，不是 `LD`）。
- 时序块里的 `if (en) q <= d;` → 这是**带使能的触发器**，完全正确、完全推荐（也是综合器插 ICG 的标准模式），**不是**锁存器。

### 3.3 【核心】唯一可靠的规避手法：块首先给所有被写对象赋默认值 `[通用]` `[业界]` Don Mills SNUG 2012 §7.0；Cummings SNUG 2005 Example 9 `[教材]` p.184 例 13.6 encoder1

Mills 的原话：*"The only way to fully prevent unintended latches in combinational logic blocks is to assign every output for every condition."* `[教材]` p.184 例 13.6 encoder1 用的就是这个手法——进 `for` 循环之前先写 `out = 0; none_on = 1;`。

```verilog
// 正例：完整可综合。防锁存器骨架 —— 块首默认值 + case 只写偏离项
`default_nettype none

module comb_skeleton (
    input  wire [1:0] sel,
    input  wire [7:0] a,
    input  wire [7:0] b,
    output reg  [7:0] y,
    output reg        valid
);

    always @(*) begin
        // 1) 先把本块写的每一个对象都赋默认值（含临时量、向量全部位）
        y     = 8'd0;
        valid = 1'b0;
        // 2) 再用条件覆盖；块内不得"先读后写"同一变量
        case (sel)
            2'b00:   begin y = a;       valid = 1'b1; end
            2'b01:   begin y = b;       valid = 1'b1; end
            2'b10:   begin y = a & b;   valid = 1'b1; end
            default: ;   // 用默认值即可（default 必写，见 §4.5）
        endcase
    end

endmodule

`default_nettype wire
```

对照 `[教材]` p.146 的比较器写法（if 逐条配 else），两者都对；**默认赋值法在输出多、分支多时可靠得多**——它把"N 个输出 × M 条分支 = N×M 个检查点"压缩成"N 个默认赋值"。

### 3.4 有意的 latch 怎么写 `[通用]`

本规范默认**不允许**设计中出现 latch（`[业界]` lowRISC *"The use of latches is discouraged - use flip-flops when possible."*）。**唯一被普遍接受的例外是时钟门控单元（ICG）内部的使能锁存器**，而那应当由综合工具插入或使用已验证的库单元/原语，不是手写（见 `references/06-clock-reset-cdc.md`）。若项目确实必须显式建模 latch：`[SV]` 用 `always_latch`（意图声明 + 工具检查，里面没有 latch 时 DC 报 `ELAB-975`）；`[V2001]` 只能用不完整的 `always @(*)`，**必须在紧邻注释里写明"这是有意的 latch 及理由"**，并在 lint 里最小范围豁免。

> `[教材]` p.180 13.3(4) 建议「为电平敏感的锁存器建模，使用连续赋值语句是最简单的方法」（即 `assign q = en ? d : q;`）。这条偏旧，且需与教材自己 p.180 13.4(2)「不推荐用一个 always 块既表示透明锁存器又同时表示组合逻辑」合起来读。**本规范不采用该写法**——它在 lint/综合工具眼里是一条组合环路（见 §7），会同时触发 latch 和 loop 两类告警，掩盖真正的问题。

### 3.5 把工具变成守门员 `[工具]` `[业界]`

| 工具 | 规则 / 告警 | 处置 |
|---|---|---|
| Verilator | `LATCH`、`ALWCOMBORDER`、`COMBDLY`、`CASEINCOMPLETE`、`CASEX`、`CASEWITHX`、`CASEOVERLAP`、`UNOPTFLAT`、`MULTIDRIVEN` | 一律视为 error |
| Yosys | `proc` + `check`（`scripts/rtl_lint.py` 已集成） | 报出真实推断的 latch / 多驱动 / 组合环路 |
| `[FPGA]` Vivado | `WARNING: [Synth 8-327] inferring latch for variable '<name>'`；Cell Usage 出现 `LD` | CI 里 grep，命中即 fail |
| `[ASIC]` Design Compiler | `ELAB-974`（always_comb 里有 latch）、`ELAB-976`（always_ff 里没有 FF） | 视为 error |

`[工具]` **本篇代码经 Verilator 5.024 `--lint-only -Wall` 与 Yosys `proc; opt; check -assert` 实测**，两条值得记住的行为差异：① Verilator 对漏赋值报 `%Warning-LATCH: Latch inferred for signal 'q' (not all control paths of combinational always assign a value)`；② **Yosys 对 `always_comb`（SV）里推断出的 latch 直接报 `ERROR: Latch inferred ... from always_comb process` 并中止**，而对 `[V2001]` 的 `always @(*)` 只打印一条信息并照常生成 `$dlatch` 单元、`check -assert` 也不失败。**所以 V2001 项目更不能只靠 Yosys，Verilator 的 `LATCH` 必须开。**

**豁免必须最小范围 + 写明理由**（`SKILL.md` §2 的姿势），绝不在命令行上整类关掉。

---

## 4. `case` / `casez` / `casex`

### 4.1 三者的比较真值 + 【核心不对称】 `[教材]` p.55 表 5.1 `[业界]` AMD UG901 Ch.9 逐字 vs IEEE 1364-2005 §9.5.1

`case` 只做对应位全等比较；`casez` 把 `z`（含 `?`）当通配；`casex` 把 `z` 和 `x` 都当通配。**关键在于：仿真侧的通配是对称的**——不只是 case item 里的 `?`/`x` 通配，**控制表达式一侧的 `x`/`z` 同样会去匹配任意分支**（IEEE 1364-2005 §9.5.1）。而综合侧不是，UG901 原文只管**分支项**：*"casez treats all z values **in any bit position of the branch alternative** as a don't care. casex treats all x and z values **in any bit position of the branch alternative** as a don't care."*

**这条不对称就是 casex/casez 仿真-综合不一致的根。** Mills SNUG 2012 因此断言：*"The SystemVerilog casez and casex types of case statements have an **inherent simulation/synthesis mismatch**."*

### 4.2 `casex` 禁用 `[通用]` = 铁律 G5 `[业界]` Cummings SNUG'99 Boston / SNUG 2005；Mills & Cummings SNUG'99；Mills SNUG 2012；lowRISC —— 四处独立一手出处

Cummings 1999：*"**Do not use casex for synthesizable code.**"*；Mills & Cummings：*"Do not use casex for RTL coding. It is too easy to match a stray unknown signal."*；Cummings 2005：*"To date, I have not found a good safe usage for the casex statement in either RTL, behavioral or testbench coding so my current guideline is: **Do not use the casex statement.**"*

具体危害：一个未初始化或存在竞争的 `opcode` 上的 X，可以"命中"任意一条合法指令分支，仿真结果凭空变得合法，而综合出的电路没有这个行为。

> `[教材]` p.55-56（例 5.4）把 casez/casex 作为"处理不必关心情况"的推荐手段并给出 `casex` + 掩码示例，**未提及综合层面的风险**（教材调研文件 B10 §四 已客观标注这一分歧）。本规范采纳业界立场：**禁用 `casex`**。

### 4.3 `casez` 谨慎使用，通配符只写 `?` `[V2001]` = 铁律 G5 `[业界]` Cummings SNUG'99 Boston 逐字

> *"When coding a case statement with \"don't cares,\" use a casez statement and **use \"?\" characters instead of \"z\" characters** in the case items"*；*"**Use casez sparingly and cautiously** for RTL coding since it is possible to match a stray tri-state signal."*

`?` 与 `z` 在 `casez` 里语义相同，但 `?` 明确表达"我要通配"，`z` 会被读成"我在比较高阻"。用 `casez` 时必须清楚：控制表达式里出现 `z` 也会乱匹配——只是"意外产生 Z"比"意外产生 X"难得多，所以 `casez` 比 `casex` 安全一个量级，**而不是绝对安全**。

```verilog
// 正例（V2001）：地址段译码。三个分支项互不重叠 —— 通配只用来"忽略低位"，不制造优先级
always @(*) begin
    cs_rom = 1'b0;               // 块首默认值：防锁存器
    cs_ram = 1'b0;
    cs_io  = 1'b0;
    casez (addr[15:12])
        4'b00??: cs_rom = 1'b1;  // 0x0xxx-0x3xxx
        4'b01??: cs_ram = 1'b1;  // 0x4xxx-0x7xxx
        4'b1???: cs_io  = 1'b1;  // 0x8xxx-0xFxxx
        default: ;
    endcase
end
```

> `[工具]` **实测教训**：本节初稿用的是 `casez (req) 2'b1?: ... 2'b?1: ...` 优先级仲裁器，`req==2'b11` 时两个分支项都匹配，Verilator 直接报 `CASEOVERLAP`。这恰好印证 §4.6——**有意的优先级不要写成重叠的 case 项**。`casez` 只用于"忽略某些位"的**互斥**译码。

`[SV]` 有 `case ... inside` 的项目应优先用它：wildcard **只作用于 case item**，控制表达式里的 X/Z 不被屏蔽、会落到 `default` 被捕获——这正是 `casez` 缺的那一半安全性。使用前确认综合工具版本支持。

### 4.4 `case` 各分支表达式位宽必须相同；禁止 `'bx` 代替 `n'bx` `[通用]` = 铁律 G2 `[教材]` p.54 (7)(4)

> 「case 语句的所有表达式值的位宽必须相等……一个经常犯的错误是用 `'bx`，`'bz` 来替代 `n'bx`，`n'bz`，这样写是不对的，因为信号 x，z 的默认宽度是机器的字节宽度，通常是 32 位。」

```verilog
// 反例，不要抄：sel 是 2 位，'bx 却是 32 位，对应位比较必然失败
case (sel)  'bx: y = 8'd0;  endcase
// 位宽写对了，但可综合 RTL 里根本不该有 x 分支项（见下面的工具实测）
case (sel) 2'bxx: y = 8'd0; endcase
```

> `[工具]` **实测**：`case` 的分支项里写 `2'bxx`，Verilator 报 `CASEWITHX`（*"Use of x/? constant in case statement"*）。教材这条规则的**有效部分是"位宽必须一致"**；至于 x/z 分支项本身，在可综合 RTL 里一律不要写——普通 `case` 里的 `n'bx` 只在控制表达式**真的是 X** 时才匹配，纯属仿真行为，综合器没有对应物。要通配请按 §4.3 用 `casez` + `?`。

同源要求：p.54 (4)「每一个 case 分项的分支表达式的值必须互不相同」——分支重叠时同一控制值有多种执行方案（见 §4.6）。

### 4.5 组合块里的 `case` 必须有 `default` `[通用]` = 铁律 C4 `[教材]` p.57 `[业界]` lowRISC 逐字

`[教材]` p.57 的黄金原则：「如果用到 if 语句，最好写上 else 项；如果用 case 语句，最好写上 default 项。」lowRISC 给出的理由比"防漏分支"深一层：

> *"a `default:` statement is **always** included in order to avoid accidental inference of latches, even if all cases are covered. In simulation, a case expression that evaluates to `X` will not match any case and will behave as a latch, leading to different behavior than synthesis if no default is specified."*

即：**即使所有 2ⁿ 种二进制组合都写全了**，仿真时控制表达式取 X 会不匹配任何 item → 保持旧值 → 行为等同 latch，而综合器不知道 X。所以 `default` 必须写，哪怕是空语句。`[教材]` p.147 的 8 选 1 多路器把 8 种编码全列举、没写 `default`，功能上不推锁存器，**但按此理由本规范仍要求补上**（教材调研文件 B08 §四 9 已标注）。

**本规范用了两道保险**：块首默认赋值（防漏赋）+ `default: ;`（防 X 不匹配）。**两者不可互相替代。**

### 4.6 有意的优先级用 `if-else-if`，并行译码才用 `case` `[通用]` `[业界]` Cummings SNUG'99 Boston §4.7 / SNUG 2005 §14；lowRISC `[教材]` p.185 例 13.7 引言

`[教材]` p.185：「如果条件语句（case 或 if-else）中分支条件是互斥的话，综合器能自动地生成并行的多路器。」Cummings 的两条 Guideline：*"Code all intentional priority encoders using if-else-if statements."* / *"Case statements can be used to create tabular coded parallel logic … when a truth-table-like structure makes the Verilog code more concise and readable."*

机理：Verilog 允许 case item 重叠，重叠时按书写顺序取第一个匹配——**隐式生成一条优先级链**。优先级链是串行 MUX 级联，深度 = 分支数；并行译码只有一层 MUX。隐式优先级既伤可读性、又伤关键路径，还是 `parallel_case` 改变功能的温床。`[工具]` Verilator `CASEOVERLAP` 可机械地发现重叠 case item。

```verilog
// 正例：优先级仲裁器写成 if-else-if，优先级一目了然，且不触发 CASEOVERLAP
always @(*) begin
    gnt = 2'b00;                       // 块首默认值
    if      (req[1]) gnt = 2'b10;      // req[1] 优先
    else if (req[0]) gnt = 2'b01;
end
```

---

## 5. `full_case` / `parallel_case` 为什么无条件禁用

### 03-10 任何形式的 `full_case` / `parallel_case` 都禁止 `[通用]` = 铁律 G6 `[业界]` Cummings SNUG 1999 Boston（Voted Best Paper 1st Place）全文；lowRISC；AMD UG901 Ch.9

论文摘要与结论逐字：

> *"The popular myth … is that these Verilog directives always make designs smaller, faster and latch-free. **This is false!** … These switches can also change the functionality of a design causing a mismatch between pre-synthesis and post-synthesis simulation, which if not discovered during gate-level simulations will cause an ASIC to be taped out with design problems."*
> ***"\"full_case\" and \"parallel_case\" directives are most dangerous when they work!** It is better to code a full and parallel case statement than it is to use directives."*

**为什么"生效的时候最危险"**：这两个 pragma 只对综合器说话、不对仿真器说话，等于**故意**让两边看到不同的设计。`parallel_case`——Cummings Example 6 是一个 `casez(irq)` 优先级中断编码器，加上它之后 *"will simulate like a priority encoder but will infer non-priority encoder logic when synthesized."*，DC 只给一条 Warning 就放行；`full_case`——把未列出的输入组合交给综合器当 don't care 自由优化，而仿真器保持原值（latch 行为）。

**禁止范围包括三种写法**：`// synopsys full_case parallel_case`、`// synthesis full_case parallel_case`、以及 IEEE 1364.1-2002 的属性式 `(* synthesis, full_case, parallel_case *)`。Cummings 2005 §15.2：*"the evil and flawed nature … still exist. The attribute method for adding directives did not correct the fundamental problems."* **"工具不认识所以无害"也是错的**：`[业界]` AMD UG901 v2025.1 Ch.9 至今仍列出 `// synthesis parallel_case full_case`——**它是活的，会真的改变综合结果**；DC 同样响应。

**关于"one-hot FSM 例外"**：Cummings 1998/1999 承认唯一例外是独热编码 FSM（*"only use full_case parallel_case to optimize onehot FSM designs"*）；lowRISC **不接受**这个例外。Cummings 2005 自己的调和方案是用 `unique case` 拿到等价的综合优化、同时获得仿真断言，让例外变得不必要。**本规范取消例外：一律禁止。**

**替代方案**：需要"完整"就补 `default`（并按 §3.3 在 case 前给全默认值）；需要"并行"就把 case 项写成真正互斥的。

---

## 6. `unique` / `priority` 为什么救不了锁存器

### 03-11 `unique`/`priority` 是 pragma 的安全替代，但**不能**消除所有意外锁存器 `[SV]` `[业界]` Don Mills SNUG 2012 §4.1b/§4.2b 逐字；Cummings SNUG 2005 §10 Myth/Truth

**它们好在哪**：相比 pragma 的**根本**改进是——它们同时是**仿真期断言**，违反时仿真器报 run-time error，综合器也做同样假设，**仿真与综合看到的是同一份信息**。这就是 pragma 缺的那一半。

**它们救不了什么**。Cummings 2005 §10 的 Myth/Truth：*"**Truth**: The `full_case` directive and now the SystemVerilog `priority` and `unique` case-statement and if-statement modifiers **only remove latches from a case statement for missing case items or incomplete if-else-if statements**."* Mills SNUG 2012 说得更狠：*"Many designers are led to believe that unique case and priority case solve their latch issues … **This is simply not so.** These constructs come close, but do not cover all the conditions where latches can inadvertently be generated."*

```systemverilog
// 反例，不要抄（Mills SNUG 2012 Example 4.2b 原文）：
// 即使 state 严格独热、unique 不报任何违规，仍然会推出锁存器 ——
// 因为 nextstate1 和 nextstate2 都没有在每条分支上被赋值
always_comb
  unique case (1'b1)
    state[0]: nextstate1 = 3'b010;
    state[1]: nextstate2 = 3'b100;
    state[2]: nextstate1 = 3'b001;
  endcase

// 反例，不要抄（Cummings SNUG 2005 Example 8 等价）：case 本身是 full 的，
// 加 unique / full_case 都没用，DC 仍报 3 个 Latch
always_comb
  unique casez (addr)
    2'b10: {mce1_n, mce0_n} = 2'b10;
    2'b11: {mce1_n, mce0_n} = 2'b01;
    2'b0?:          rce_n   = 1'b0;
  endcase

// 正例（Cummings SNUG 2005 Example 9）：case 前统一默认赋值，latch 消失
always_comb begin
  {mce1_n, mce0_n, rce_n} = 3'b111;   // 默认：全不选中
  unique casez (addr)
    2'b10:   {mce1_n, mce0_n} = 2'b10;
    2'b11:   {mce1_n, mce0_n} = 2'b01;
    2'b0?:            rce_n   = 1'b0;
    default: ;
  endcase
end
```

**机理（本节关键）**：`unique`/`priority` 的检查对象是 **case-item 集合**（够不够 full、互不互斥）；锁存器推断的判据是 **"某个输出在某条可达路径上未被赋值"**。**两者正交**，所以前者不可能覆盖后者。`[工具]` 上面两个反例已实测：Yosys 对第二个反例直接报 `ERROR: Latch inferred for signal '\bad_cummings.\mce0_n' from always_comb process`；正例则报 `No latch inferred`。

**要不要给所有 case 都加 `unique`——业界有分歧**：lowRISC 主张一律加（*"creates simulation assertions that can catch certain mistakes"*，前提是项目有完整 DV 环境、断言失败被当作收益）；Cummings SNUG 2005 反对一律加（*"There are still some efficient coding styles that do not define all possible testing conditions…"*，取值域天然不满时会刷 run-time error 淹没真问题）；Mills 认为有价值但被高估。

**本规范的取舍**：`[SV]` 项目中，取值域受控且可断言的场景（状态、操作码）加 `unique` + `ASSERT_KNOWN`；取值域天然不满的场景用普通 `case` + `default`。`[V2001]` 项目没有这两个关键字，只有块首默认赋值这一条路——这反而说明了它才是根本手段。

---

## 7. 组合环路

### 03-12 组合块内不得存在反馈环路 `[通用]` = 铁律 C5 `[教材]` p.180-181 13.4(6) `[业界]` Verilator `UNOPTFLAT`；Cummings SNUG 2003 §10

`[教材]` p.180 原文：「always 块中应该避免组合反馈回路。……如果在设计中存在综合器认为不是电平敏感锁存器的组合回路时，综合器会发出**错误**信息（例如设计中有异步状态机时）。」注意这里的区分：**漏赋值 → warning（插锁存器）；真组合环 → 直接报 error**。

```verilog
// 反例，不要抄：连续赋值构成的环（既是 latch 又是 loop）
assign q = en ? d : q;

// 反例，不要抄：过程块内先读后写构成的环
always @(*) begin
    y = y + a;          // y 依赖自己
end

// 反例，不要抄：跨语句构成的环（教材 p.181 原例的变体）
always @(*) begin
    e = d & a & b;
    d = e | c;          // d 依赖 e，e 依赖 d
end
```

**危害**：组合环没有确定稳态（可能振荡，也可能锁死），**STA 无法给出时序路径**，**ATPG 无法建模**——`[ASIC]` `[业界]` Cummings SNUG 2003 §10 把 *"asynchronous combinational feedback loops"* 列为必须被 test mode 屏蔽的"非可测逻辑"。

**"看起来像环、其实不是环"的两种情形**（不要误伤）：① `next_state = state;` —— `state` 是**另一个（时序）块**的寄存器输出，环被触发器打断了，这是合法且必需的组合反馈；② `y = a; ... y = b;` —— 同一变量被多次**写**、没有被读，只是覆盖。

`[工具]` Verilator 用 `UNOPTFLAT` 暴露环形依赖，`ALWCOMBORDER` 是轻量前哨；`scripts/rtl_lint.py` 的 `yosys proc+check` 直接报组合环路。

### 03-13 一个变量只能在一个 `always` 块里被赋值 `[通用]` = 铁律 D3 `[教材]` p.181 13.4(2)(1)

> 「对一个寄存器型（reg）和整型（integer）变量给定位的赋值，只允许在一个 always 块内进行，如在另一个 always 块中也对其赋值，这是非法的。」

组合逻辑同样受这条约束：把一个组合输出拆到两个 `always @(*)` 里赋值，仿真结果取决于块的调度顺序（IEEE 不规定），综合器行为在不同工具间也不一致（报错 / 只取一个 / 生成短路网表）。`[工具]` Verilator `MULTIDRIVEN`；`[SV]` `always_comb` 由 LRM §9.2.2.2 明文禁止（*"shall not be written to by any other process"*），工具可静态查出。

---

## 8. `[FPGA]` 与 `[ASIC]` 的差异

组合逻辑这一章**绝大部分规则两边完全一致**（锁存器规避、敏感表、casex 禁用、pragma 禁用都通用），真正有差异的只有两处：

| 议题 | `[FPGA]` | `[ASIC]` | 出处 / 为什么 |
|---|---|---|---|
| latch 可接受度 | **直接禁止**：映射为 `LD` 原语，时序不可预测、吃资源 | 库与 STA 流程**可以**支持 latch 并做 time borrowing，少数场合有意使用 | `[业界]` AMD UG901（`LD` + Synth 8-327）；ASIC 侧 W08 调研标注**无一手出处**，仅方向性说法 |
| 内部三态 vs MUX | 综合器**自动**把内部 BUFT 转成 LUT 逻辑（UG901 逐字），写了也没用 | **禁止**：上电/复位释放窗口有总线竞争，瞬时短路电流可能伤器件，ATPG 还要额外竞争向量 | 结论相同（都用 MUX），**原因相反**：FPGA 是"没有这个资源"，ASIC 是"有资源但危险" |

**共同点**：`full_case`/`parallel_case` 在 **Vivado 和 DC 上都是活的 pragma**，两边都会真的改变综合结果——所以两边都禁。

---

## 9. 本篇涉及的分歧，以及本规范的取舍

| # | 议题 | 各方立场 | 本规范取舍 |
|---|---|---|---|
| D-1 | `always @(*)` vs `always_comb` | lowRISC：一律 `always_comb`；保留派：老工具链 / 混合语言流程，且 `@*` **没有**"块内被写变量被排除"这个坑 | **这不是新旧之争，是语义差异**。`[SV]` 项目用 `always_comb`；`[V2001]` 用 `always @(*)`。**迁移必须配回归仿真**（§03-07） |
| D-2 | 组合块里能不能赋 `X` | lowRISC：*"RTL must not assert `X` to indicate 'don't care' to synthesis in any case."*；Mills SNUG 2012：*"Propagating X is a better solution than inferring a latch"*；`[教材]` p.177/p.181：赋 `'bx` 让综合器当无关状态、电路最简洁 | 分歧根源是**验证方法学**：有强 SVA/formal 的团队能"全定义 + 断言非法态"，没有的团队靠 `default: 'x` 在仿真里暴露非法态。**本规范默认取消除派**（赋确定值 + 断言），理由与 `SKILL.md` F 节"默认显式回安全态"一致；细节见 `references/14-disputes.md` |
| D-3 | `case` 一定要写 `default` 吗 | lowRISC：无条件必须；Cummings：语言层面 optional；Mills：`default` 可能用"看起来合法的兜底值"掩盖非法输入 | **必须写**。可调和写法：case 前给全默认值 + `default: ;` + 对选择子加 `$isunknown` 断言——既无锁存器，又不用兜底值掩盖非法输入 |
| D-4 | `casez` 能不能用 | Cummings/Mills：可用但要谨慎；Mills 2012：`casez` 也有**固有** sim/synth mismatch，据此有人主张一并禁 | 与 `SKILL.md` G5 一致：**`casex` 禁，`casez` 仅在明确知道自己在做什么时使用**，且只写 `?`。`[SV]` 优先 `case ... inside` |
| D-5 | `default` 赋 `'bx` 还是赋安全值 | `[教材]` p.177：赋 `'bx`，否则综合前后仿真不一致（真实硬件上电状态不确定，而仿真会立刻进 default 走到 state1）；安全关键设计：显式回 IDLE | `SKILL.md` F 节已裁决：**默认显式回安全态**。教材的顾虑（仿真-综合初态不一致）用"复位必须把状态机拉到 IDLE"来解决，而不是靠赋 X |

---

## 本篇检查清单

写完 / 审查任何一段组合逻辑，逐条勾：

- [ ] 能用 `assign` 的地方没有滥用 `always` 块
- [ ] 组合块的敏感表是 `always @(*)`（`[SV]`：`always_comb`），**没有一处手写敏感表**
- [ ] 组合块内**只有阻塞赋值 `=`**，没有 `<=`，没有 `#` 延迟
- [ ] 块首给**本块所有被写对象**（含输出、临时量、向量全部位、数组元素）赋了默认值
- [ ] 每个 `case` 都有 `default`（哪怕是 `default: ;`）；每个 `if` 都有 `else`，或已由块首默认值覆盖
- [ ] `case` 各分支表达式**位宽一致**、**互不重叠**；没有裸 `'bx` / `'bz`
- [ ] 没有 `casex`；用了 `casez` 的地方通配符是 `?` 而不是 `z`，且注释写清了为什么必须通配
- [ ] 代码里搜不到 `full_case` / `parallel_case`（三种写法都搜：`// synopsys`、`// synthesis`、`(* ... *)`）；也没有依赖 `unique` / `priority` 来"消锁存器"
- [ ] 组合块内没有**先读后写**同一变量；没有 `assign y = en ? d : y;` 这类环路；每个组合输出**只在一个** `always` 块 / 一条 `assign` 里被赋值
- [ ] 有意的优先级用 `if-else-if` 写；真值表式并行译码才用 `case`
- [ ] 设计中不存在 latch（ICG 内部使能锁存器除外，且必须由工具插入或用已验证原语）
- [ ] `python3 scripts/rtl_lint.py --top <顶层> --synth <文件>.v` 输出 `通过 ✔`（Verilator `LATCH`/`ALWCOMBORDER`/`CASEINCOMPLETE`/`UNOPTFLAT` 零告警，Yosys `check` 无 latch / 无组合环路）
- [ ] `[FPGA]` 综合报告里没有 `Synth 8-327`，Cell Usage 里没有未在白名单内的 `LD`
- [ ] `[ASIC]` 综合报告里没有 `ELAB-974`

---

## ⚠️ 与主规范的冲突

目前**没有发现实质性冲突**——本篇所有结论都与 `SKILL.md` 的 C1~C5、G2、G5、G6 一致。

> **状态更新（2026-08-12）：下面第 1、2 条已裁决并落实到 `SKILL.md`，保留为修订记录，不要再按"建议"栏改一遍。**

**1. 铁律 C5 的字面表述会误伤合法写法 —— ✅ 已采纳并改完**

`SKILL.md` C5 **原**文：「组合块里不能有反馈：**本块赋值的变量不得在本块中被读作输入**」。按字面读，`tmp = a & b; y = tmp | c;` 这种"先写后读的中间临时量"会被判违规——但它是 IEEE 1364-2005 §9.7.5 Example 2 亲自给出的标准写法，也是可读性最好的组合逻辑分解方式，不应禁止。真正要禁的是**"先读后写"**（读到的是上一次的值 → 环路/收敛依赖）。

✅ **`SKILL.md` C5 现已改为**：「组合块里不能有**组合反馈**：任何变量必须先赋值后使用，禁止在赋值之前读取本块将要写的变量」，并在表下加了措辞说明（指出教材 p.380 可综合(7) 的原话更严，本规范按精确含义执行）。本篇 §03-07 与 §7 与之一致，无需再改。

**2. 铁律 C 表的教材页码引用疑似串位 —— ✅ 已核对并改完（不是串位，是同页两份清单）**

`SKILL.md` 中 C2 与 B4 曾同引「p.380 (5)」、C3 与 B3 同引「p.380 (6)」、E1 与 A2 同引「p.380 (2)」。
✅ **核对扫描页后确认**：书 p.380 上**同时印着两份各自从 (1) 开始编号的清单**——
「1. 语汇代码的编写标准」(1)~(8) 与「2. 可综合代码的编写标准」(1)~(11)（续到 p.381 的 (12)~(15)）。
所以两边引用**都是对的**，只是指代不清。`SKILL.md` 现已统一改为 `p.380 语汇(N)` / `p.380 可综合(N)`。
详见 `13-xiayuwen-source.md` §9.1。以下是本篇能独立确证的组合逻辑侧出处，仍然有效：我能确证的组合逻辑侧出处是：敏感表完整性 → **p.181（13.4 "1. always 块" (6) 补充解释）**、p.59、p.146-147；漏赋值出锁存器 → **p.56 图 5.1 / p.57 图 5.2 / p.180-181 13.4(6)**；if 配 else、case 配 default → **p.57**；组合反馈回路 → **p.180-181 13.4(6)**；一个 reg 只在一个 always 块内赋值 → **p.181 13.4 "2. 赋值" (1)**。

**3. 教材与本规范在 `casez`/`casex` 和 `default: 'bx` 上立场相反（已按分歧处理，非冲突）**

`[教材]` p.55-56 把 `casez`/`casex` 作为"处理不必关心情况"的推荐手段并给出 `casex` 示例（例 5.4），p.177/p.181 推荐 `default: state = 'bx`。这两点与 `SKILL.md` G5、F 节的裁决相反。**教材成书时代未涉及仿真-综合不一致的系统性论述**（教材调研文件 B10/G01 的"存疑/过时"节已客观标注）。本篇按 `SKILL.md` 的裁决书写，并在 §4.2 / §9 D-2 / §9 D-5 中把教材立场原样呈现，不隐去。这属于"已裁决的分歧"，不需要上层再处理，此处仅备案。

**另需上层注意的一处取证限度**：`[ASIC]` 侧"库和 STA 流程可以有意利用 latch 做 time borrowing"这条（本篇 §8 表格），W08 调研明确标注**无一手出处**，仅为方向性说法。本篇已保留该标注，请勿在后续文档中把它升级为确定结论。
