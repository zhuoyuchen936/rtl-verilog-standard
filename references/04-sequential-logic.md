# 04 · 时序逻辑：阻塞赋值与非阻塞赋值

> 本篇是 `SKILL.md` 铁律 **C1 / D1 / D2 / D3 / D4 / D5** 的展开与论证，不推翻其中任何一条。
> 一手来源：《Verilog 数字系统设计教程(第 4 版)》夏宇闻 第 14 章（书 p.194-212）；Clifford E. Cummings,
> *"Nonblocking Assignments in Verilog Synthesis, Coding Styles That Kill!"*, SNUG-2000 San Jose, Rev 1.2。
> 教材第 14 章作者自述"是根据国外一篇论文，经过自己的理解编写而成的"（p.194）——**两份材料同源**，
> 所以下文"教材 8 条要点"与"Cummings 8 条 guideline"能逐条对齐。

## 本篇速览

1. **时序块（`@(posedge clk)`）里只写 `<=`；组合块（`@(*)`）里只写 `=`。** 不是风格偏好，是为了让**综合前仿真与综合后仿真一致**。
2. 机理只有一句：**`=` 一步完成（算 RHS + 立刻更新 LHS）；`<=` 两步完成（时间步开始算 RHS，时间步结束才更新 LHS）。**
3. IEEE 标准规定 active events 队列内部**执行顺序不确定**。时序逻辑用 `=`，结果就取决于这个不确定顺序 → 竞争冒险（race condition）。
4. 教材 p.199-202 的移位寄存器 8 连实验：**4 种阻塞写法只有 1 种仿真正确、3 种综合正确；4 种非阻塞写法全部仿真正确、全部综合正确。**
5. 同一 `always` 块混用 `=`/`<=`：作用于不同变量 → 可综合但禁止；作用于**同一变量** → **综合报错**。
6. 一个变量只能被一个 `always` 块赋值；`#0` 一律禁止——它进的是 inactive 队列，根本救不了竞争。

## 1. 先把术语定准

`[教材] p.194-196` `[业界] Cummings §3.0/§4.0` `[通用]`

**RHS** = 赋值号右边的表达式/变量，**LHS** = 左边的（教材 p.194 定义，全章沿用）。
三个符号别搞混：`=` 阻塞赋值 / `<=` 非阻塞赋值 / `==` 相等比较。`if (rst) q <= 1'b0;` 里的 `<=` 是赋值，不是"小于等于"。

| | 阻塞赋值 `=` | 非阻塞赋值 `<=` |
|---|---|---|
| 执行步数 | **一步**：算 RHS 并立刻更新 LHS，其间不允许别的语句干扰（p.195） | **两步**：赋值开始时刻算 RHS，赋值结束时刻才更新 LHS（p.196） |
| 块内后续语句读到 | **新值** | **旧值**（本时间步 LHS 还没更新） |
| 与书写顺序的关系 | 强相关，顺序错 = 功能错 | 无关，"从用户的角度看好像是并行执行的"（p.196） |
| 对应的电路 | "往往与触发沿没有关系，只与输入电平的变化有关系"（p.194） | "往往与触发沿有关系，只有在触发沿时才有可能发生赋值的变化"（p.194） |
| 可用位置 | 过程块内 | **只能对 reg/variable，只能在 `initial`/`always` 等过程块内；不允许用于连续赋值**（p.196） |

```verilog
assign y <= a & b;      // 反例，不要抄：连续赋值不能用非阻塞赋值符
```

教材对"为什么一定要这样做"的正面回答（p.194 原文）：**"这是因为要使综合前仿真和综合后仿真一致的缘故。
如果不按照上面两个要点来编写 Verilog 代码，也有可能综合出正确的逻辑，但前后仿真的结果就会不一致。"**
即：**违规不一定综合错，但会让 RTL 仿真和网表仿真对不上**——而对不上就意味着你的验证结论对流片后的芯片不成立。

## 2. 分层事件队列——所有结论的根

`[教材] p.197-198（14.3 节）` `[业界] Cummings §6.0` `[通用]`

教材 p.197 引 IEEE 1364-1995 §5.3，把**当前仿真时刻**的事件分成 5 个逻辑队列（原文逐条）：

| # | 队列 | 内含事件 |
|---|------|---------|
| 1 | **动态事件队列**（Cummings 称 *active events*） | ① 阻塞赋值；② **计算非阻塞赋值语句右边的表达式**；③ 连续赋值；④ 执行 `$display`；⑤ 计算原语的输入和输出的变化。**这些事件之间的执行顺序可以随意安排。** |
| 2 | **停止运行的事件队列**（*inactive events*） | `#0` 延时阻塞赋值 |
| 3 | **非阻塞事件队列**（*NBA update*） | **更新非阻塞赋值语句 LHS 的值** |
| 4 | **监控事件队列**（*monitor events*） | `$monitor`、`$strobe` |
| 5 | PLI 队列 | 其他指定的 PLI 命令 |

- **S4-01** `[教材] p.197` `[通用]` 大多数事件由动态事件队列调度，**"而非阻塞赋值语句 LHS 的更新却不由动态事件队列调度"**（p.197 原文）。这是 `<=` 全部"魔力"的来源。
- **S4-02** `[业界] Cummings §6.0` `[通用]` 事件可以被排入任意队列，但**只从 active events 队列被取出执行**；其他队列的事件要先被"激活"提升进 active 队列。
- **S4-03** `[业界] Cummings §2.0` `[教材] p.194-195` `[通用]` **active events 内部无序，就是竞争冒险的定义域**：两条被调度在同一仿真时间步的语句，在标准允许的范围内改变执行顺序会得到不同结果，即 race condition（IEEE 1364 Determinism §5.4.1 / Nondeterminism §5.4.2 / Race conditions §5.5）。教材原话：*"若有两条或两条以上语句准备在同一时刻执行，但由于语句的排列顺序不同（而这种排列顺序的不同是 IEEE Verilog 标准所允许的），却产生了不同的输出结果。这就是造成 Verilog 模块冒险和竞争现象的原因。"*

> ⚠️ **标准版本注记（保留调研文件的存疑标注）**：教材引的是 **IEEE 1364-1995 §5.3**。IEEE 1364-2001/2005 与
> SystemVerilog（IEEE 1800）已把事件区域重划为 Preponed / Active / Inactive / NBA / Observed / Reactive /
> Re-Inactive / Re-NBA / Postponed 等更细的 region（1800 共 17 个），**队列名称与数量与教材所述不同**。
> 教材的概念模型在推理上仍成立，但术语与编号已非最新；**1800 的 region 扩展本规范未取到一手条文印证**。

## 3. 竞争冒险是怎么长出来的：反馈振荡器

`[教材] p.195-196 例 14.1/14.2` `[业界] Cummings Example 1/2` `[通用]`

```verilog
// 反例，不要抄 —— 教材[例 14.1] / Cummings Example 1：阻塞赋值的反馈振荡器
    always @(posedge clk or posedge rst)
      if (rst) y1 = 0;      // reset
      else     y1 = y2;

    always @(posedge clk or posedge rst)
      if (rst) y2 = 1;      // preset
      else     y2 = y1;
```

教材 p.195：若上面那块的有效时钟沿"比下面的 always 块的时钟沿早几个皮秒（由时钟偏差造成）到达，则 y1 和 y2 都会取 1；
而若下面的那个 always 块的有效时钟沿早几个皮秒到达，则 y1 和 y2 都会取 0"。**同一份代码，两种结果，都合法。**

```verilog
// 正例 —— 教材[例 14.2] / Cummings Example 2：同一模块，两块改成非阻塞赋值
module fbosc2 (y1, y2, clk, rst);
    output y1, y2;
    input  clk, rst;
    reg    y1, y2;

    always @(posedge clk or posedge rst)
      if (rst) y1 <= 0;
      else     y1 <= y2;

    always @(posedge clk or posedge rst)
      if (rst) y2 <= 1;
      else     y2 <= y1;
endmodule
```

两块的 RHS 都在时间步开始处求值（读到的都是**上一拍**的 y1/y2），LHS 都在 NBA 队列更新，所以
**y1=1、y2=0 是确定的**，与两块谁先执行无关（p.196）。这正是真实硬件里两个 D 触发器交叉相连的行为。

## 4. 移位寄存器：教材 14.5 的 8 连对比实验

`[教材] p.199-202 例 14.5~14.12` `[业界] Cummings §8.0 Example 5~11` `[通用]`

目标电路：`d → FF → q1 → FF → q2 → FF → q3`（教材图 14.1）。四种阻塞写法：

```verilog
// 反例，不要抄 —— [例 14.5] pipeb1 方式#1：塌缩成一级寄存器
    always @(posedge clk) begin
        q1 = d;      // 立刻生效
        q2 = q1;     // 读到的是刚写的新 q1，即 d
        q3 = q2;     // 读到的是刚写的新 q2，即 d
    end
```
教材 p.200：**"在每个时钟上升沿，输入值 d 将无延时地直接输出到 q3……上面的模块实际上被综合成只有一个寄存器的电路（见图 14.2）"**。
**综合器为什么这么处理**：它在时钟块里按"**先写后读 = 组合直通（不推寄存器），先读后写 = 上一拍的值（推寄存器）**"建数据流锥。
`q1`/`q2` 在本块内都是先写后读，于是在 q3 的输入锥里退化成纯连线；又没有别的读者，最终只剩 d 到 q3 的一级触发器。

```verilog
// 反例（可综合但风格禁止），不要抄 —— [例 14.6] pipeb2 方式#2：倒着写"碰巧对"
    always @(posedge clk) begin
        q3 = q2;     // 先读旧 q2
        q2 = q1;
        q1 = d;
    end
```
教材 p.200：**"阻塞赋值的顺序是经过仔细安排的……虽然该模块可被综合成图 14.1 所示的移位寄存器，但不建议使用这种风格的模块来描述时序逻辑。"**
正确性依赖人肉维护的语句顺序——加一级流水、插一条赋值就静默出错。

```verilog
// 反例，不要抄 —— [例 14.7] pipeb3 方式#3：阻塞赋值散在多个 always 块里
    always @(posedge clk) q1 = d;
    always @(posedge clk) q2 = q1;
    always @(posedge clk) q3 = q2;
```
教材 p.201：**"仿真时，这些块的先后顺序是随机的，因此可能会出现错误的结果，这是 Verilog 中的竞争冒险……
但是，这些代码的综合结果却是正确的流水线寄存器。也就是说，前仿真和后仿真的结果可能会不一致。"**
`[例 14.8]` 只是把三个块换个书写顺序，结论相同（p.201）。

四种非阻塞写法——原地把 `=` 换成 `<=`（`[例 14.9]`），打乱语句顺序（`[例 14.10]`），拆到三个 `always` 块（`[例 14.11]`），
再打乱块顺序（`[例 14.12]`）——**四种全部仿真正确、全部综合正确**。原因就是 §1 表格最后两行：
RHS 统一在时间步开始处求值，读到的一律是上一拍的值。教材 p.202 的四条统计结论（原文）：

> （1）4 种阻塞赋值设计方式中有 **1 种**可以保证仿真正确；（2）4 种阻塞赋值设计方式中有 **3 种**可以保证综合正确；
> （3）4 种非阻塞赋值设计方式**全部**可以保证仿真正确；（4）4 种非阻塞赋值设计方式**全部**可以保证综合正确。

- **S4-04** `[教材] p.202-203` `[业界] Cummings Guideline #1` `[通用]` **时序逻辑一律用 `<=`，无论一个还是多个 `always` 块。**
  教材 p.203：*"在描述时序逻辑时，必须养成使用非阻塞赋值的习惯（无论用多个 always 块或单个 always 块描述时）。"*
  即使只有单条赋值的 D 触发器（`[例 14.13]` 用 `=` 也能对），教材仍判定不推荐——*"这种做法将导致使用阻塞赋值的习惯，
  而在较为复杂的有多个 always 块的设计项目中，稍不注意就很可能导致竞争冒险，或者功能错误"*（p.203）。

## 5. 反过来：组合逻辑为什么必须用 `=`

`[教材] p.205-207（14.8 节）` `[业界] Cummings Guideline #3` `[通用]`

```verilog
// 反例，不要抄 —— [例 14.19] ao4：组合逻辑用非阻塞赋值，仿真结果不正确
    always @(a or b or c or d) begin
        tmp1 <= a & b;
        tmp2 <= c & d;
        y    <= tmp1 | tmp2;   // 读到的是"刚进块时"的旧 tmp1/tmp2
    end
```
教材 p.206 机理原文：**"由于非阻塞赋值语句在 LHS 更新前计算 RHS 的值，因此 tmp1 和 tmp2 仍是刚进入该 always 块时的值……
输出 y 反映的是刚进入 always 块时的 tmp1 和 tmp2 的值。"** 把 `tmp1`/`tmp2` 塞进敏感表（`[例 14.20]`）能靠"重复触发"收敛出正确值，
但教材 p.207 判定：**"一个 always 块中有多次参数传递，由此降低了仿真器的性能，只有在没有其他合理方法的情况下才考虑这样做。"**

```verilog
// 正例 —— [例 14.21] ao2：组合逻辑用阻塞赋值，一次传递就得到正确结果
    always @(a or b or c or d) begin
        tmp1 = a & b;
        tmp2 = c & d;
        y    = tmp1 | tmp2;
    end
```

- **S4-05** `[教材] p.207 原则 3` `[业界] Cummings Guideline #3` `[通用]` 组合 `always` 块内只用 `=`。
  **敏感表要现代化**：教材全章用 `always @(a or b or c or d)`，本规范按 `SKILL.md` C2 写 `always @(*)`（`[V2001]`）
  或 `always_comb`（`[SV]`）；两者敏感表语义**并不完全等价**（`always_comb` 会把"块内被写的变量"排除出隐式敏感表，
  `@*` 不会），差异见 `references/03-combinational-logic.md`。

## 6. 带反馈的时序逻辑：LFSR

`[教材] p.203-205（14.7 节）` `[通用]`

反馈回路是"仔细安排阻塞赋值顺序"这条退路的终点站——**它安排不出来**。

```verilog
// 反例，不要抄 —— [例 14.15] lfsrb1：用阻塞赋值，实际不具有 LFSR 功能
    always @(posedge clk or negedge pre_n)
      if (!pre_n) begin q3 = 1'b1; q2 = 1'b1; q1 = 1'b1; end
      else        begin
          q3 = q2;
          q2 = n1;      // n1 = q1 ^ q3（连续赋值）
          q1 = q3;      // 拿到的已是刚被改写的新 q3 → 反馈链断了
      end
```
教材 p.204：**"除非使用中间暂存变量，否则用[例 14.15]所示的赋值是不可能实现反馈逻辑的。"**

```verilog
// 正例 —— [例 14.17] lfsrn1：同样结构改成非阻塞赋值，功能正确且可综合
module lfsrn1 (q3, clk, pre_n);
    output q3;
    input  clk, pre_n;
    reg    q3, q2, q1;
    wire   n1;

    assign n1 = q1 ^ q3;

    always @(posedge clk or negedge pre_n)
      if (!pre_n) begin q3 <= 1'b1; q2 <= 1'b1; q1 <= 1'b1; end
      else        begin q3 <= q2;   q2 <= n1;   q1 <= q3;   end
endmodule
```

教材另给了"把多条赋值凑成单行拼接等式"的写法（`[例 14.16]` `{q3,q2,q1} = {q2,(q1^q3),q3};`），功能确实正确
（拼接的 RHS 一次性求值），但教材 p.204 明确：**"如果逻辑再复杂一些，单行等式是难以编写和调试的。这种方法一般不推荐使用。"**
本规范：**禁止用拼接式阻塞赋值来"绕过"非阻塞赋值。**

## 7. 同一个 `always` 块里混用 `=` 和 `<=`

`[教材] p.208-209（14.10 节）` `[业界] Cummings Guideline #5` `[通用]` → `SKILL.md` **D2**

**(a) 作用于不同变量 —— 语法合法、仿真与综合都对，但本规范禁止。**
```verilog
// 反例（可综合但禁止），不要抄 —— [例 14.24] ba_nba2
    always @(posedge clk or negedge rst_n) begin: ff
      reg tmp;                       // 命名块内的局部 reg
      if (!rst_n) q <= 1'b0;
      else begin
            tmp = a & b;             // 阻塞
            q  <= tmp;               // 非阻塞
          end
    end
```
教材 p.208：*"可以得到正确的仿真和综合结果，因为阻塞赋值和非阻塞赋值操作的不是同一个变量。虽然这种方法是可行的，但并不建议使用。"*
Cummings 同样注明这是**规范层面**的限制，IEEE 标准并不禁止混用。本规范禁止的理由是可审查性——
审查者无法一眼确认"两种赋值确实没落到同一个变量上"，而这个判断错一次就是 (b)。

**(b) 作用于同一变量 —— 仿真"通常正确"，但综合报错。**
```verilog
// 反例，不要抄 —— [例 14.25] ba_nba6
    always @(posedge clk or negedge rst_n)
      if (!rst_n) q = 1'b0;          // 对 q 阻塞赋值
      else begin
            tmp = a & b;
            q  <= tmp;               // 又对 q 非阻塞赋值
          end
```
教材 p.209：**"在仿真时，其结果通常是正确的，但是综合时会出错，因为对同一变量既进行阻塞赋值，又进行了非阻塞赋值。"**
机理：综合工具无法为同一变量同时建立"立即更新"和"时钟沿更新"两套语义。**这是最危险的一类：仿真放行，综合才拦下来。**

> 相关但不同 `[教材] p.211-212 误解 3` `[通用]`：**同一 `always` 块内对同一变量多次非阻塞赋值是合法的**，语义是
> "最后一次赋值决定该变量的值"（last-assignment-wins）。这正是"块首先赋默认值、后面用 `if/case` 覆盖"能成立的依据。

## 8. 多个 `always` 块驱动同一个变量

`[教材] p.209-210（14.11 节）原则 6` `[业界] Cummings Guideline #6` `[通用]` → `SKILL.md` **D3**

```verilog
// 反例，不要抄 —— [例 14.26] badcode1：即使全用非阻塞赋值，一样是竞争冒险
    always @(posedge clk or negedge rst_n)
      if (!rst_n) q <= 1'b0;
      else        q <= d1;

    always @(posedge clk or negedge rst_n)   // 同一个 q，第二个驱动源
      if (!rst_n) q <= 1'b0;
      else        q <= d2;
```

- 仿真侧：两块执行顺序随机 → **"即使使用非阻塞赋值也可能产生竞争冒险"**（p.209）。`<=` 在这里救不了你：
  它消除的是"同一时间步读到新值还是旧值"的不确定，消除不了"两条 NBA 更新写同一个 LHS，谁最后写"的不确定。
- 综合侧：教材 p.209-210 抄录了 Synopsys 原始告警 `Warning: In design 'badcode1', there is 1 multiple-driver net with unknown wired-logic type.`
  忽略它继续编译，会**"产生两个触发器输出到一个两输入与门。其综合级前仿真与综合后仿真的结果不完全一致"**（p.210）。

- **S4-06** `[教材] p.210 原则 6` `[业界] Cummings Guideline #6` `[通用]` **一个变量只允许在一个 `always` 块里被赋值。**
  需要"多处影响同一个寄存器"时，正确做法是把各路条件收进**同一个** `always` 块的 `if-else if` 优先级链，
  或先在组合块里算出唯一的 `_d` 信号再由唯一的时序块打拍。
- **S4-07** `[教材] p.180/p.380` `[通用]` → `SKILL.md` **D4** 每个时序 `always` 块**只由一个时钟沿触发**；
  敏感表里只允许"一个时钟沿 + 至多一个异步复位沿"。`always @(posedge clk_a or posedge clk_b)` 综合不成任何单一触发器。

## 9. `#0` 为什么被一票否决

`[教材] p.198 / p.210-212（误解 2、原则 8）` `[业界] Cummings Guideline #8 / §6.0` `[通用]` → `SKILL.md` **D5 / I**

1. **它不可综合。** 教材 p.195：**"一般可综合的阻塞赋值操作在 RHS 不能设定有延迟（即使是零延迟也不允许）"**；RHS 上加延迟"会阻止赋值语句的执行……这种赋值语句是不可综合的"。
2. **它救不了竞争。** 教材 p.198：采用 `#0` 是因为"有些对 Verilog 理解不够深入的设计人员希望在两个不同的程序块中给同一个变量赋值，他们企图在同一个仿真时刻，通过稍加延时赋值来消除 Verilog 可能产生的竞争冒险。**这样做实际上会产生问题**"。Cummings §6.0 称之为 *"flawed practice"*，并称他不知道有任何一种情况是 `#0` 无法被更好、更高效的编码风格替代的。
3. **它的行为和大多数人以为的不一样。** 教材 p.210 误解 2 原文：*误解："#0 延时把赋值强制到仿真时间步的末尾"。* **事实是：`#0` 只把事件加入停止运行（inactive）事件队列，仍排在 NBA 更新之前**。教材 p.211 实测输出 `0ns: #0 : a=0 b=1`，而同一时刻 `$strobe` 打的是 `a=1 b=0`。你以为推到了最后，其实只推了半步。

```verilog
#0 a = b;              // 反例，不要抄：妄图用 #0 消除两个块对同一变量赋值的竞争
y = #5 a;              // 反例，不要抄：RHS 带延迟，不可综合
```

**配套的仿真侧一条** `[教材] p.210-211 原则 7` `[业界] Cummings Guideline #7`：`$display` 在 active 队列、位于 NBA 更新**之前**，
看到的是旧值；`$strobe`/`$monitor` 在监控队列，该时间步所有赋值完成之后执行。教材 `[例 14.27]` 实测输出：
`$display: a = 0` / `$monitor: a = 1` / `$strobe : a = 1`。

- **S4-08** `[教材] p.211 原则 7` `[通用]` `[SV]` **观察用 `<=` 赋值的变量，用 `$strobe`（或 `$monitor`），不要用 `$display`。**
  常见误判"我的时序逻辑不工作"，实际只是 `$display` 打了旧值。

> 同一机理的另一个演示（教材 14.4 节 p.198-199 / Cummings §7.0）：`always @(clk) #10 clk = ~clk;` **不能**自触发
> （阻塞赋值立刻更新 clk，块回到 `@(clk)` 时已错过跳变）；换成 `<=` 就能自触发（LHS 更新排在 NBA 队列，
> 此时 `@(clk)` 已重新挂上敏感）。两份材料都强调：**`osc2` 能自振荡，但不推荐用作 testbench 的时钟源。**

## 10. 教材 8 条要点 ↔ Cummings 8 条 guideline ↔ 本规范铁律

`[教材] p.197（14.2 节）、p.212（小结）` `[业界] Cummings §5.0` `[通用]`

教材 p.196 节首：**"在编写 Verilog 代码时必须牢记这 8 个要点，才能在综合布局布线后的仿真中避免出现冒险竞争现象。"**

| # | 教材要点（p.197 / p.212 原文） | Cummings Guideline（§5.0 原文） | 对应 `SKILL.md` |
|---|---|---|---|
| 1 | 时序电路建模时，用非阻塞赋值。 | `When modeling sequential logic, use nonblocking assignments.` | **D1** |
| 2 | 锁存器电路建模时，用非阻塞赋值。 | `When modeling latches, use nonblocking assignments.` | 见 §13 分歧 D-B（本规范默认禁止 latch） |
| 3 | 用 always 块建立组合逻辑模型时，用阻塞赋值。 | `When modeling combinational logic with an always block, use blocking assignments.` | **C1** |
| 4 | 在同一个 always 块中建立时序和组合逻辑电路时，用非阻塞赋值。 | `When modeling both sequential and combinational logic within the same always block, use nonblocking assignments.` | **D1**（该块由时钟沿触发，整体算时序块） |
| 5 | 在同一个 always 块中不要既用非阻塞赋值又用阻塞赋值。 | `Do not mix blocking and nonblocking assignments in the same always block.` | **D2** |
| 6 | 不要在一个以上的 always 块中为同一个变量赋值。 | `Do not make assignments to the same variable from more than one always block.` | **D3** |
| 7 | 用 `$strobe` 系统任务来显示用非阻塞赋值的变量值。 | `Use $strobe to display values that have been assigned using nonblocking assignments.` | `references/10-testbench.md` |
| 8 | 在赋值时不要使用 `#0` 延迟。 | `Do not make assignments using #0 delays.` | **D5 / I** |

教材 p.212 结论：*"遵循以上原则，有助于正确的编写可综合硬件，并且可以消除 90%～100% 在仿真时可能产生的竞争冒险现象。"*
> ⚠️ 调研文件已标注：这个 "90%～100%" 是作者转引自 Cummings 论文的**经验性论断，非严格量化结论**，本规范原样保留标注。

## 11. 可直接抄的时序块骨架

`[教材] p.203/p.207-208` `[业界] lowRISC / Cummings` `[V2001]`

```verilog
`default_nettype none
// 三级流水移位寄存器：异步低有效复位 + 时钟使能
module shift3 #(
    parameter integer WIDTH = 8
) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire             en,
    input  wire [WIDTH-1:0] d,
    output wire [WIDTH-1:0] q
);
    reg [WIDTH-1:0] q1, q2, q3;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            q1 <= {WIDTH{1'b0}};
            q2 <= {WIDTH{1'b0}};
            q3 <= {WIDTH{1'b0}};
        end
        else if (en) begin
            q1 <= d;            // 全部非阻塞，三条语句顺序随便写
            q2 <= q1;
            q3 <= q2;
        end
    end

    assign q = q3;
endmodule
`default_nettype wire
```

组合与时序拆开写（教材 `[例 14.23]` 的现代形式，本规范默认风格），以及"时序 + 组合同块"
（教材原则 4 允许，`[例 14.22]` 的形式）——整块统一 `<=`：

```verilog
    always @(*)                                    // 组合块：只用 =
        sum_d = {1'b0, a} + {1'b0, b};             // 显式扩位保进位

    always @(posedge clk or negedge rst_n)         // 时序块：只用 <=
        if (!rst_n) sum_q <= {(WIDTH+1){1'b0}};
        else        sum_q <= sum_d;

    always @(posedge clk or negedge rst_n)         // 同块混写：整块 <=
        if      (!rst_n) cnt <= 4'd0;
        else if (clr)    cnt <= 4'd0;
        else if (en)     cnt <= cnt + 4'd1;        // 加法是组合，但整块是时序块
```

## 12. FPGA 与 ASIC 的差异

阻塞/非阻塞的**语义规则本身与目标工艺无关**——教材 8 条、Cummings 8 条在 FPGA 与 ASIC 上一字不改。
但下面几处与时序逻辑直接相关的实践，两边做法是**相反的**：

| 议题 | `[FPGA]` | `[ASIC]` | 为什么相反 / 出处 |
|---|---|---|---|
| 未复位的流水线寄存器怎么获得初值 | **可以**靠声明初值 `reg [3:0] p = 4'b1011;`，Vivado 写成寄存器 `INIT` 属性，**在全局复位/上电时生效，与本地复位无关** | **禁止依赖**：普通标准单元触发器没有对应上电行为，上电值不确定 | 配置比特流本身就能初始化触发器，ASIC 没有"配置阶段"。`[业界]` AMD UG901 v2025.1 Ch.9 "Initial Values"（逐字） |
| 刻意建模 latch（教材原则 2 的适用面） | 多数 FPGA 规范**直接禁止**：映射为 `LD` 单元、时序不可预测，Vivado 报 `[Synth 8-327]` | 库与 STA 流程**可以**支持 latch 并做 time borrowing | FPGA 无 latch 专用资源且难做 STA。`[业界]` UG901 Ch.5（逐字）；**ASIC 侧调研未取到一手出处，标注 ❓ 未经一手资料印证** |
| 复位风格（决定时序块敏感表怎么写） | 倾向**同步复位**：UG901 逐字 *"Do not asynchronously set or reset registers."* | 倾向**异步复位 + 同步释放**：lowRISC/OpenTitan 逐字 *"Resets are active-low and asynchronous."* | 异步复位在 FPGA 会阻断 BRAM/DSP/SRL 推断、吃掉 control set；ASIC 需要上电确定态。详见 `references/06-clock-reset-cdc.md` |
| 违规后的兜底 | 多数流程**不做**完整门级仿真，阻塞赋值引入的竞争容易一路溜到板上才暴露 | 通常有带 SDF 的 GLS，能在流片前抓到一部分前后仿真不一致 | 流程差异。**本规范的工程判断，调研文件中无一手出处** |

**结论不变**：正因为 FPGA 侧缺少 GLS 这层兜底，FPGA 工程师**更没有**理由在时序逻辑里用阻塞赋值。

## 13. 有分歧的地方（如实呈现）

**D-A：混合块 vs 拆块。** 教材/Cummings 的原则 4 明确允许"时序和组合写在同一个 `always` 块中"，只要统一 `<=`（p.207-208 `[例 14.22]`）；
而现代主流是把两者拆成两个块（组合 `=`、时序 `<=`），即教材自己也给出的 `[例 14.23]`，二/三段式状态机与 `_d`/`_q` 命名体系都建立在拆块之上
（调研文件 B04 存疑节已指出这一点）。**本规范取舍：默认拆块**；只有当"组合部分"退化成一两个运算符（计数器 `+1`、`a ^ b`）时才允许同块，
此时整块必须统一 `<=`。两种做法都不违反 D1/D2。

**D-B：刻意建模 latch 时用哪种赋值。** 教材原则 2 / Cummings Guideline #2 都要求 **latch 用 `<=`**；而 `SKILL.md` C1 说
"组合 `always` 块内只用 `=`"，latch 恰恰写在电平敏感的 `always` 块里。**本规范取舍**：latch **默认禁止**
（C3、`references/03-combinational-logic.md`）；确有必要（极少数低功耗/面积场景，且仅 `[ASIC]`）时按原则 2 用 `<=`，
并加最小范围 lint 豁免与理由注释。这一边界建议写进 C1，见文末冲突节。

**D-C：testbench 里的时钟与复位赋值。** Cummings 复位论文（SNUG Boston 2003 §7.4）Guideline 原文是
`In general, change the testbench reset signal on the inactive clock edge using blocking assignments.`
——即在**时钟非有效沿、用阻塞赋值**改复位；而同一论文 Example 9 又对**时刻 0 的第一次赋值**用非阻塞（`clk <= 0; rst_n <= 0;`），
让复位在时刻 0 的 NBA 区域才更新，强制所有过程块先于复位断言变为活动。两者不矛盾：**时刻 0 用 `<=`，之后在非有效沿用 `=`**。
（调研文件 W02 该条目的标题与其引用的 Guideline 原文措辞不一致，此处以论文 Guideline 原文 + Example 9 为准。）
testbench 的时钟发生器 `always #(CLK_PERIOD/2) clk = ~clk;` 用阻塞赋值是常规做法，按 `SKILL.md` §2 做最小范围 lint 豁免 `[工具]`。

**D-D：量化说法。** "消除 90%～100% 竞争冒险"（教材 p.212）是经验论断，不要当成可验收指标。

**取证完整性的如实说明**：Cummings 该篇论文的官方发布页（`sunburst-design.com/papers/` → 301 → `paradigm-works.com/papers/`）
调研时**未能取到**（域名被安全策略拦截），正文取自 MIT 6.375 课程站镜像 PDF（页眉保留 "SNUG San Jose 2000 / Rev 1.2"，可作一手使用）；
另一份调研文件 W08 独立复核时**未取到**该论文正文、仅确认书目。两份调研取证状态不同，本篇以 W02 取到的正文为准。

## 本篇检查清单

- [ ] 每个 `always @(posedge ...)` 块里**只有 `<=`**，一个 `=` 都没有。
- [ ] 每个 `always @(*)` / `always_comb` 块里**只有 `=`**，一个 `<=` 都没有。
- [ ] 没有任何一个 `always` 块同时出现 `=` 和 `<=`（即使作用于不同变量）。
- [ ] 每个被赋值的变量**只被一个** `always` 块赋值（grep 变量名，确认只有一处作为左值）。
- [ ] 时序块敏感表里只有"一个时钟沿"（外加至多一个异步复位沿），没有第二个时钟。
- [ ] 可综合代码里没有 `#` 延迟，尤其没有 `#0`；testbench 的延迟与设计代码物理隔离。
- [ ] 没有 `assign` 配 `<=`；没有用拼接式阻塞赋值（`{a,b,c} = {...}`）"绕过"非阻塞赋值。
- [ ] 流水线/移位寄存器里，各级之间没有出现"本块内先写后读"的变量。
- [ ] 需要观察 `<=` 赋值结果的地方用的是 `$strobe`/`$monitor`，不是 `$display`。
- [ ] 若组合与时序写在同一个时钟块里，该块**整体统一** `<=`，且组合部分不超过一两个运算符。
- [ ] `[FPGA]` 若依赖声明初值/`INIT` 给未复位寄存器定初值，文件头已注明 "FPGA-only"；`[ASIC]` 未依赖任何声明初值。
- [ ] `python3 scripts/rtl_lint.py --top <top> --synth <file>.v` 输出 `通过 ✔`（Yosys 的多驱动检查是 D3 的机器兜底）。

## ⚠️ 与主规范的冲突

本篇未发现与 `SKILL.md` 的**实质**冲突。以下 3 处是边界不清或措辞精度问题，提请上层裁决：

1. **C1 的适用边界没有排除刻意建模的 latch。** C1 写"组合 `always` 块内**只用**阻塞赋值 `=`"，而教材原则 2 与
   Cummings Guideline #2 都要求 **latch 用 `<=`**；latch 正是写在电平敏感的 `always` 块里，字面上属于"组合 `always` 块"。
   建议 C1 改为"**组合逻辑（非 latch）** `always` 块内只用 `=`；刻意建模 latch 时按原则 2 用 `<=`，需最小范围 lint 豁免 + 理由注释"。
   否则规范在"latch 该用哪种赋值"上对模型是沉默的，而教材/业界对此有明确答案。

2. **D3 的"非法"措辞过强。** D3 写"多块赋同一变量是非法的"。准确说法是：对 `reg`，**IEEE Verilog 语法并不禁止**
   （教材 `[例 14.26]` 能编译能仿真），它是**综合层面的多驱动错误 + 仿真层面的竞争冒险**。同理 D2（混用 `=`/`<=`）——
   Cummings 与教材 p.208 都注明"Verilog 语法并没有禁止"，这是**编码规范**层面的限制。建议改为
   "**规范严禁；语法上不报错，靠 lint/综合兜底**"，以免模型据此推断"编译器会替我拦住"。

3. **D5 与 testbench 的边界。** D5/I 禁止 `#` 延迟，但 testbench 必然要用 `#`（时钟发生器、激励节拍），
   且 Cummings 要求 testbench 复位在**非有效沿用阻塞赋值**、**时刻 0 用非阻塞赋值**。建议在 D5 后补一句
   "本条针对可综合 RTL；testbench 的赋值与延迟风格见 `references/10-testbench.md`"，否则模型可能把 D5 套到 testbench 上，
   写出没有延迟的时钟发生器。
