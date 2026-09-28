# 14 · 业界分歧与本规范的取舍

这份文件收录的都是**真实存在、有一手资料支撑、且双方都有道理**的争议。它存在的理由是：
主规范 `SKILL.md` 的铁律只给结论，而结论在某些议题上是有**适用边界**的。
知道边界在哪，才能在规范没覆盖到的场合做对决定；不知道边界，就只会照抄。

**读法**：每条按「议题 / 各方立场与出处 / 各自适用条件 / 本规范的取舍与理由 / 什么情况下应当偏离默认」四段写。
凡出现 `[未经一手资料印证]` 的标注，是调研阶段就没拿到一手出处的说法，本篇原样保留该标注，不做加强。

---

## 本篇速览

1. **复位**：ASIC 默认异步低有效 + 同步释放；FPGA 默认同步复位（AMD）或同步化异步复位（Intel）。**唯一无分歧的是：只要用异步复位，就必须同步释放。**
2. **数据通路复位**：AMD 说"别加"，lowRISC 说"全加"——这不是风格之争，是器件有没有上电初值的物理差异。本规范：**控制路径必复位，数据路径可豁免但要满足三个前提**。
3. **`full_case` / `parallel_case`**：无条件禁止（含 one-hot FSM 那个历史例外）。SV 用 `unique`/`priority`，但它们**不是**消 latch 的手段。
4. **`case default` 赋 `x` 还是确定值**：本规范默认**赋确定值**；只有"纯组合译码器 + 无形式验证/门级仿真需求 + 面积吃紧"三条同时成立才允许赋 `x`。
5. **`always @*` 与 `always_comb` 敏感表语义真的不同**（LRM 明文），迁移会静默改变行为——这是本篇技术含量最高的一条。
6. **FSM 编码**：不在 RTL 里写死，用符号名 + 综合脚本变量；FPGA 倾向 one-hot，ASIC 倾向二进制。
7. **lint 豁免**：自有代码内联，第三方/生成代码用集中 waiver 文件；全局 `-Wno-XXX` 双方都反对。

---

## 议题索引

| # | 议题 | 本规范默认 | 适用范围 |
|---|------|-----------|---------|
| D01 | 同步复位 vs 异步复位 vs 同步化异步复位 | ASIC 异步低有效+同步释放；FPGA 同步复位 | `[通用]` |
| D02 | 数据通路要不要复位（AMD vs lowRISC 直接对立） | 控制必复位，数据路径条件豁免 | `[通用]` |
| D03 | 复位与时钟使能的优先级（AMD vs Intel 硬件语义相反） | reset 写在 enable 之前 | `[FPGA]` |
| D04 | 复位极性：低有效 `rst_n` vs 器件偏好的高有效 | 模块接口 `rst_n`，边界转一次极性 | `[通用]` |
| D05 | `full_case` / `parallel_case` | 无条件禁止 | `[通用]` |
| D06 | `case` 的 `default` 赋 `x` 还是确定值 | 赋确定值 | `[通用]` |
| D07 | X 传播：主动传播 vs 主动消除（含 `casex`/`casez`） | 消除派 + 断言；禁 `casex` | `[通用]` |
| D08 | `unique` / `priority` 该不该到处加 | 取值域受控处加，其余不加 | `[SV]` |
| D09 | `case` 一定要写 `default` 吗 | 必须写 | `[通用]` |
| D10 | 独热 vs 二进制/格雷编码 | 不在 RTL 写死编码 | `[通用]` |
| D11 | `always @*` vs `always_comb` 敏感表语义 | 两者都禁"先读后写" | `[V2001]` `[SV]` |
| D12 | `initial` 初值 / `reg x = 0;` | ASIC 禁止依赖；FPGA 允许声明初值且必须同时写显式复位 | `[通用]` |
| D13 | 存储器：RTL 推断 vs IP 生成 vs 例化原语 | 优先推断 | `[通用]` |
| D14 | 门控时钟：FPGA 转 CE vs ASIC 插 ICG | RTL 一律写 `if (en)`，不手写门控 | `[通用]` |
| D15 | lint waiver 内联注释 vs 集中文件 | 自有代码内联，第三方集中 | `[工具]` |
| D16 | 带复位与不带复位的触发器能否同块 | 不能同块 | `[ASIC]` |
| D17 | 两段式 vs 三段式 FSM | 三段式（见 `05-fsm.md`） | `[通用]` |

---

## D01 · 同步复位 vs 异步复位 vs 同步化异步复位

### 各方立场与出处

| 立场 | 主张 | 出处 |
|---|---|---|
| **Cummings/Mills 2002** | 推荐异步复位 | `[业界]` SNUG San Jose 2002（正文未取到，仅书目）**[未经一手资料印证]** |
| **Cummings/Mills/Golson 2003** | **转为中立**：原文承认"两种方法都能在实际设计中有效使用"，并称这几乎成了宗教之争 | `[业界]` *Asynchronous & Synchronous Reset Design Techniques — Part Deux*, SNUG Boston 2003 Rev 1.3 §4.2（全文已取得） |
| **RMM（转引）** | 推荐同步复位，理由是更适合 cycle-based 仿真器 | `[业界]` 经 SNUG 2003 §4.2 转引；**RMM 原文未取到，[未经一手资料印证]** |
| **lowRISC / OpenTitan** | 全芯片异步、低有效，直接接标准单元的异步复位端 | `[业界]` lowRISC *Verilog Coding Style Guide* |
| **AMD/Xilinx** | *"Do not asynchronously set or reset registers."* 必须复位时用同步复位 | `[业界]` UG901 v2025.1 Ch.5 p.86；UG949 v2023.1 Ch.3 p.51 |
| **Intel/Altera** | **同步化异步复位是设计 FPGA 电路时的首选**（异步断言 + 同步释放） | `[业界]` Quartus Prime SE UG-20175 §1.4.1.3 p.30–31 |
| **教材** | 状态机应该有一个异步或同步复位端，以便通电时把电路复位到有效状态（不选边） | `[教材]` p.177 |

### 分歧的本质

**不是"哪个对"，而是"目标器件的触发器复位端连到哪里"**：

- AMD：同步复位可被综合器搬到 D 端（control set remapping），有优化自由度；异步复位钉死在专用 CLR 引脚，且 DSP48 / BRAM 内部寄存器**只有同步复位**——一旦写异步复位，流水级就吸收不进硬核。UG949 给的实测：16×16 三级流水乘法器改异步复位后，多花约 65 个寄存器 + 32 个 LUT。
- Intel：`aclr` 走 LAB 专用线、不进数据路径，异步断言几乎零代价；同步复位反而要占数据路径或 LAB 的 `synclr`。
- ASIC：上电触发器为 X，没有配置比特流给初值，**必须**显式复位才能脱离 X 态。

SNUG 2003 §4.2/§5.3/§8.2 给出的逐维对比（可直接当决策表用）：

| 维度 | 同步复位占优 | 异步复位占优 |
|---|---|---|
| 触发器面积 | 优（复位并进 D 端逻辑），但论文提醒组合部分门数会涨，总收益未必显著 | 劣（需带复位脚的单元） |
| 数据路径时序 | 劣（复位进 D 端组合逻辑） | 优（数据路径"保证干净"） |
| 无时钟时能否复位 | 不能 | 能。门控时钟省电时时钟可能与复位同时关掉，*"Only an asynchronous reset will work in this situation"* |
| 毛刺 | 时钟起滤波作用 | 任何满足最小脉宽的毛刺都会复位 |
| 内部条件产生的复位 | 论文推荐同步（能滤掉时钟间的逻辑方程毛刺） | 需额外处理 |
| DFT | 简单 | 需 scan 旁路/屏蔽 |
| FPGA | 劣（同步复位会吃掉 LUT 输入） | 优（FPGA 无内部 scan，DFT 顾虑不存在） |

### 本规范的取舍

- `[ASIC]` **默认异步低有效复位 + 复位同步器（异步断言、同步释放）**，与 `SKILL.md` E4 一致。每个时钟域一套独立同步器与复位树。
- `[FPGA]` **AMD 器件默认同步复位**；**Intel 器件默认同步化异步复位**。两者在模块内部的写法差别只在敏感表（`SKILL.md` §1.E 已给对照）。
- `[通用]` **无论选哪种，异步复位都必须同步释放**（AMD UG949 与 Intel UG-20175 在这一点上完全一致，没有分歧）；同步复位必须保证脉宽跨越至少一个有效时钟沿。
- 复位方式**必须写进模块头注释**，不允许"读代码猜"。

### 什么情况下应当偏离默认

1. 同一份 RTL 要同时喂 AMD 与 Intel → 统一走"外部复位同步器 + 模块内部只用同步复位"，牺牲 Intel 侧的一点效率换可移植性。
2. 同一份 RTL 要同时喂 FPGA 与 ASIC → **必须写显式复位**，不能依赖 FPGA 的配置初值（见 D12）。
3. 设计里有门控时钟且要求"时钟停了也能复位" → 只能用异步复位。

---

## D02 · 数据通路要不要复位（AMD 与 lowRISC 直接对立）

### 各方立场与出处

| 立场 | 主张 | 出处 |
|---|---|---|
| **AMD/Xilinx（不加派）** | 逐个评估每个时序块是否真的需要复位，**不要默认加上**；控制通路通常需要，**数据通路（流水级、延迟线、算子级寄存器）通常不需要**；"避免任何可能的 operational set/reset" | `[业界]` UG949 v2023.1 Ch.3 p.50；UG901 v2025.1 Ch.5 p.86 |
| **lowRISC / OpenTitan（全加派）** | 全芯片所有复位统一定义为低有效异步，绑到标准单元的异步复位端 | `[业界]` lowRISC *Verilog Coding Style Guide* |
| **Cummings 2003（折中）** | *"in general, every flip-flop in an ASIC should be resetable"*，但高速流水线上**可以**去掉部分触发器的复位，前提是复位有效期有**预定的时钟数**把设计冲刷进已知态 | `[业界]` SNUG Boston 2003 §2.0 |
| **Intel（另一种折中）** | 带异步复位的寄存器后接若干 **follower registers**，follower 本身不复位，靠若干周期冲刷出初态 | `[业界]` Quartus SE UG-20175 §1.4.1.2 Fig.19 |
| **教材** | "所有内部寄存器都应当是可以复位的"（作为可综合代码标准之一） | `[教材]` p.380 可综合(11) |

### 为什么会对立

AMD 的三条机理（都在 UG949 Ch.3）：
1. **控制集爆炸**——复位是控制集的一部分，低扇出复位会让一个 slice 里另外 7 个寄存器无法打包；
2. **阻断硬核吸收**——BRAM/DSP48 内部寄存器只有同步复位、DSP48 只有 reset 没有 set，数组上误加复位会让本可推成 1 块 BRAM 的存储退化成几千个 FF；SRL16/SRL32 原语**根本没有 set/reset 端口**，给移位寄存器写复位会逼综合器在 SRL 外补逻辑，或干脆退化成 N 个 FF；
3. **扇出与布线**——复位网络扇出巨大。

lowRISC 的机理正相反：ASIC 触发器上电为 X，任何**能影响控制决策**的未复位寄存器都可能让芯片停在非法态且永不自恢复。

**所以这不是风格偏好，是"器件有没有上电初值"这一条物理差异导致的。**

### 本规范的取舍

**控制路径（状态机状态、握手 valid/ready、计数器的使能与清零、任何被别人当条件读的信号）一律复位。数据路径流水寄存器允许不复位，但必须同时满足三个前提**（来自 SNUG 2003 §2.0）：

1. 该寄存器纯粹搬运数据，不参与任何控制决策；
2. 复位有效周期数 ≥ 流水线深度，保证释放后管道被冲刷干净；
3. 伴随的 `valid`/`enable` 控制位**必须**复位，用它屏蔽未初始化的数据。

这与 `SKILL.md` E3「所有内部状态寄存器必须可复位（流水线/同步寄存器可例外）」一致——E3 的"例外"就是这三个前提。

```verilog
// 正例：控制位复位，数据不复位（FPGA 与 ASIC 都成立的写法）
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) vld_pipe <= 3'b000;                 // 控制：必须复位
    else        vld_pipe <= {vld_pipe[1:0], in_vld};
end

always @(posedge clk) begin                          // 数据：不复位
    d0 <= din;
    d1 <= d0;
    d2 <= d1;
end
```

### 什么情况下应当偏离默认

- 目标是 AMD FPGA 且大量使用 DSP48 / BRAM / SRL → 数据通路**必须**去掉复位，否则硬核吸收失败，这是量级上的代价而不是几个 LUT。
- 目标是安全关键（ISO 26262 / DO-254）→ 放弃上面的豁免，所有触发器一律复位，用面积换可诊断性。
- 不确定某个寄存器算控制还是数据 → 按控制处理（复位），错在保守一侧。

---

## D03 · 复位与时钟使能的优先级：AMD 与 Intel 硬件语义相反

### 各方立场与出处

| 厂商 | 硬件优先级 | 推荐的 RTL 写法 | 出处 |
|---|---|---|---|
| **AMD/Xilinx** | **set/reset 优先于 clock enable**（所有寄存器，无论同步异步）。原文：*"all registers are built to have set/reset take precedence over clock enable"* | `if (rst) ... else if (ce) ...` | `[业界]` UG949 v2023.1 Ch.3 p.56 |
| **Intel/Altera** | `aclr > aload > **ena** > sclr > sload > data`，即 **clock enable 优先于同步清零** | `if (ena) begin if (sclr) ... else ... end` | `[业界]` Quartus SE UG-20175 §2.5.2 p.69–70 |

Intel 在文档里主动点名了这个差异：*"The priority order for secondary control signals in Intel FPGA devices differs from the order for other vendors' FPGA devices."*

### 各自适用条件与后果

写错优先级**不会导致功能错误**——综合器会用逻辑模拟出你描述的语义。代价在 QoR 与约束上：

- **AMD 侧写成 CE 优先**：FDRE 原语的 `R` 天生优先于 `CE`，工具只能在 D 端插 MUX 模拟，多一层 LUT，并把复位逼进数据路径。
- **Intel 侧写成 sclr 优先**：Quartus 会用寄存器数据输入端**模拟** clock enable，后果是**再也套不上 `Clock Enable Multicycle` 约束**（实际没走寄存器的 CE 端口），对 CE 的赋值会产生意外结果。

**两边无法同时最优**——这是本篇里最"硬"的一处厂商差异。

### 本规范的取舍

`[FPGA]` **默认按 AMD 语义写：复位分支写在最前，使能分支写在其后。** 理由有三：
(a) 这也是 `SKILL.md` §1.E 复位模板的形状，与全规范一致；
(b) `if (rst) ... else if (ce) ...` 的读法与"复位优先"的直觉一致，审查成本低；
(c) 本规范的默认复位策略（D01）在 FPGA 上是同步复位，同步复位本来就允许被工具重映射。

```verilog
// 正例（AMD 语义，本规范默认）
always @(posedge clk) begin
    if (rst)     q <= 8'd0;      // 复位在前
    else if (ce) q <= d;         // 使能在后
end
```

```verilog
// 反例，不要抄：CE 优先于 reset，与 AMD FDRE 硬件语义相反
always @(posedge clk) begin
    if (ce) begin
        if (rst) q <= 8'd0;
        else     q <= d;
    end
end
```

### 什么情况下应当偏离默认

- 目标器件是 Intel/Altera **且**该寄存器组确实需要 `Clock Enable Multicycle` 约束 → 改按 Intel 语义写（`ena` 在外层），并在模块头注释里写明"本模块按 Intel 二级控制信号优先级编码，移植到 AMD 需复核"。
- 同一份代码要喂两家 → 采用调研给出的规避法：**需要 CE 的大位宽通路上不写同步复位（靠上游复位或初值），需要同步复位的地方不写 CE**，从根上绕开优先级冲突。

---

## D04 · 复位极性：低有效 `rst_n` vs 器件偏好的高有效

### 各方立场与出处

- **高有效派** `[FPGA]`：AMD 要求控制输入（CE/S/R）**必须描述成 active-High**，写成低有效会插 LUT1 反相器；更糟的是**同一信号的高有效版和低有效版会形成两个不同的控制集**，直接翻倍控制集数量（`[业界]` UG901 v2025.1 Ch.5 p.86；UG949 v2023.1 p.60 / p.265）。
- **低有效派** `[ASIC]`：lowRISC/OpenTitan 全芯片统一 `rst_n` 低有效异步（`[业界]` lowRISC Style Guide）；标准单元库的异步复位端通常就是低有效。
- 本规范 `SKILL.md` B1 已定：复位名 `rst_n`（低有效）或 `rst`（高有效），**低有效必须带 `_n` 后缀**。

### 本规范的取舍

**模块接口按 `SKILL.md` B1 命名；如果目标是 AMD FPGA，在模块边界统一转一次极性，模块内部只使用一种极性。** 绝不允许"模块 A 用 `!rst_n`、模块 B 用 `rst`、两者由同一物理复位驱动"——那会综合出两棵复位树、两组控制集。

```verilog
// 顶层统一转极性，内部全高有效（AMD 友好）
wire rst = ~rst_n;
always @(posedge clk) begin
    if (rst)     q <= 8'd0;
    else if (ce) q <= d;
end
```

### 什么情况下应当偏离默认

ASIC 流程、或与既有 IP 的复位极性冲突时，保持 `rst_n` 贯穿全设计即可，不要为了"照顾 FPGA"在中途反复转极性。**极性只在一处翻转**是这条规则的实质。

---

## D05 · `full_case` / `parallel_case`

### 各方立场与出处

| 立场 | 主张 | 出处 |
|---|---|---|
| **AMD UG901 属性章（中性）** | 中性描述：`FULL_CASE` 表示所有可能值都已给出、工具不再为其它值造逻辑；`PARALLEL_CASE` 强制建成并行结构。**因为会改变设计的逻辑行为，只能写在 RTL 里** | `[业界]` UG901 v2025.1 p.60, p.67 |
| **AMD UG901 Verilog 章（推荐用）** | 在 "Avoiding Priority Processing" 一节**主动建议**用 `(* parallel_case *)` 避免 case 按优先级求值 | `[业界]` UG901 v2025.1 Ch.9 p.263 |
| **Intel（明确警告）** | `full_case` 是"仅综合"属性，**会导致仿真不匹配**——仿真工具仍会把未指定情形当作锁存器 | `[业界]` Quartus SE UG-20175 §2.5.3.1 p.72 |
| **Cummings 1999（反对）** | *"do not use 'full_case parallel_case' directives with any Verilog case statements"*；名句：*"'full_case' and 'parallel_case' directives are most dangerous when they work!"* | `[业界]` *"full_case parallel_case", the Evil Twins of Verilog Synthesis*, SNUG Boston 1999 Rev 1.1（获最佳论文一等奖，全文已取得） |
| **Cummings 1999/1998（唯一例外）** | *"only use full_case parallel_case to optimize onehot FSM designs"*——one-hot FSM 下所有非法编码本来就是 don't care | `[业界]` SNUG 1999 §5.0；SNUG 1998 |
| **lowRISC（不接受例外）** | *"Never use either the `full_case` or `parallel_case` pragmas."* 无条件禁止 | `[业界]` lowRISC Style Guide |

### 机理（为什么"生效的时候最危险"）

这两个 pragma 只对综合器说话、不对仿真器说话，等于**故意让两边看到不同的设计**：

- `parallel_case`：Cummings 的 `casez(irq)` 优先级中断编码器例子——加上之后 *"will simulate like a priority encoder but will infer non-priority encoder logic when synthesized"*，而 Design Compiler 只给一条 Warning 就放行。
- `full_case`：把未列出的输入组合交给综合器当 don't care 优化，而仿真器保持原值（即 latch 行为）。
- 属性写法（IEEE 1364.1-2002 的 `(* synthesis, full_case *)`）并没有解决本质问题：*"the evil and flawed nature of the … 'evil twins' still exist."*（SNUG 2005 §15.2）

### 本规范的取舍

**无条件禁止，包括注释式 `// synopsys full_case parallel_case`、Synplicity 式 `// synthesis ...`、以及属性式 `(* full_case *)`。** 与 `SKILL.md` G6 一致。

**one-hot FSM 那个例外本规范也不采纳**，理由：
1. 它诞生于没有 `unique`/`priority` 的 pragma 时代，SNUG 2005 的调和方案已经让它变得不必要；
2. 本规范 D10 的取舍是"不在 RTL 里写死编码"——编码由综合脚本决定，那么"selector 一定是 one-hot"这个前提在 RTL 层面根本不成立；
3. 它把一个只在特定编码下成立的假设，藏进了一个综合器与仿真器看法不一致的注释里。

**想要并行译码的正确做法**：把 selector 显式解码成二进制（或用互斥的 `case` 分支），让工具自然生成并行结构；`[SV]` 用 `unique case`（见 D08）。

### 什么情况下应当偏离默认

没有。如果综合报告说某个 case 没有被识别为并行、关键路径因此变长，正确动作是**改 RTL 结构**，不是加 pragma。

---

## D06 · `case` 的 `default` 赋 `x` 还是确定值

### 各方立场与出处

| 立场 | 主张 | 出处 |
|---|---|---|
| **面积派（Intel）** | 为获得最好的逻辑优化，把 `default` / 最后的 `ELSE` 赋 **don't care（X）** 而不是逻辑值。量化例证：Stratix 上某 3 路选择例子，省掉最后 `ELSE` 要 6 个 LE，写了只要 3 个；把 `ELSE` 赋 `1` 而不是 `X`，LE 数还会略多 | `[业界]` Quartus SE UG-20175 §2.5.3.1 p.72、§2.6.5.4 p.87–88 |
| **面积派（Mills）** | `default : out = 'x;` 后注：*"Propagating X is a better solution than inferring a latch"* | `[业界]` Don Mills, *Yet Another Latch and Gotchas Paper*, SNUG 2012 §2.1 |
| **X 安全派（lowRISC）** | *"RTL must not assert `X` to indicate 'don't care' to synthesis in any case."* 替代方案是全定义 + SVA 断言 | `[业界]` lowRISC Style Guide |
| **教材（面积派）** | `case` 最后必须写 `default` 并把状态变量设为 `'bx`，等于告知综合器所有状态已指定，可删除多余译码电路；并称把 default 设为确定状态会导致综合前后仿真不一致 | `[教材]` p.177、p.181 13.4-2(2)、例 13.2（p.182） |
| **教材（安全态派）** | 同一本书 p.171 又写"以确保回到 Idle 状态"；p.177 自身也留了例外条款："在有多余状态的情况下，可以通过综合指令将默认状态设置为某一确定的有效状态……否则会引起死锁" | `[教材]` p.171、p.177 |

> **注意**：教材在这一点上**自己前后不一致**，`references/13-xiayuwen-source.md` §8.4 已记录该冲突。本规范必须选边。

### 技术分歧点

`X` 在两侧的语义**不可能同时正确**：

- 仿真中 `X` 是**悲观**的（一律传播），综合中 `X` 是**乐观**的（当 don't care 自由优化）。同一个 `default: y = 1'bx;` 综合后是"某个确定值"，仿真中是"未知值"，两者**永远不等价**。
- 更细的一层：`if (x)` 在 RTL 仿真中会**乐观**地走 `else` 分支，而门级网表中同一条件产生确定的 0/1 → 出现"RTL 仿真通过、门级仿真失败"或反过来。
- 反方向：`X` 在算术/位运算中**悲观**扩散，会把一个小问题染成一整条通路的未知，掩盖真实 bug。

### 本规范的取舍

**默认赋确定值**（状态机回安全态 IDLE，数据输出回全 0 或某个合法值），与 `SKILL.md` §1.F 的结论一致。理由：

1. 本规范把"仿真与综合看到同一份设计"当作最高优先级（`SKILL.md` 开篇那句话）；`X` 赋值天然违背它。
2. 教材 p.177 反对"回确定值"的理由是"仿真启动时输入全不定 → 立即进 default → 状态被设成 state1，掩盖了真实硬件上电状态不确定"。**这个顾虑本规范用 testbench 里显式的复位序列来解决**（见 `references/10-testbench.md`），而不是靠在 RTL 里撒 `X`。
3. 教材 p.177 自己的例外条款（多余状态可能死锁）恰恰指向"回安全态"。
4. 面积收益（Intel 的例子是 3 LE vs 略多于 3 LE）与"一个只在门级或硅上暴露的功能差异"不成比例。

**分两档管理**（这是不选边的实操路径，也是本规范允许的偏离边界）：

| 档 | 对象 | 允许 `X`？ |
|---|---|---|
| 严格档 | 状态机次态、跨模块接口、任何带 `valid` 语义的信号、任何会被别的模块当条件读的信号 | **禁止** |
| 宽松档 | 纯组合译码器的数据输出，且该模块不进形式验证/门级仿真，且面积确实吃紧 | 允许，但必须在同一行注释写明理由 |

```verilog
// 正例（本规范默认）：块首赋确定默认值，default 留空
always @(*) begin
    y = 8'd0;                 // 确定的安全默认值
    case (sel)
        2'b00: y = a;
        2'b01: y = b;
        2'b10: y = c;
        default: ;            // 用默认值
    endcase
end
```

```verilog
// 反例，不要抄（除非落在上表"宽松档"且写了理由）
always @(*) begin
    case (sel)
        2'b00: y = a;
        2'b01: y = b;
        2'b10: y = c;
        default: y = 8'hxx;   // 综合当 don't care，仿真当未知 —— 两边永远不等价
    endcase
end
```

> 顺带一条无分歧的硬规则：真要写 `x`，也必须写全位宽 `8'hxx` / `1'bx`，不能写裸 `'bx`——`x`/`z` 的默认宽度是机器字长（通常 32 位）。教材 p.54 点名这是"一个经常犯的错误"（`SKILL.md` G2）。

### 什么情况下应当偏离默认

只有"纯组合译码器 + 无形式验证/门级仿真需求 + 面积经实测确实是瓶颈"三条**同时**成立。任何一条不成立就回默认。

---

## D07 · X 传播：主动传播（悲观）vs 主动消除（乐观），以及 `casex` / `casez`

### 各方立场与出处

| 立场 | 主张 | 出处 |
|---|---|---|
| **消除派** | RTL 里不出现 `X`，用 SVA 断言暴露非法条件：*"rather than assign and propagate `X` values, designs should fully define all signal values and make extensive use of SVAs"*；并要求所有模块输出加 `ASSERT_KNOWN` | `[业界]` lowRISC Style Guide |
| **传播派** | 让 `X` 自然传播，靠它在仿真中暴露未初始化路径——这也是 `casex`/`casez`/`default: 'x` 的原始动机 | `[业界]` Cummings SNUG 1999 §3.3（描述了该动机及其失败模式）；Mills SNUG 2012 §2.1 |
| **分场景派** | X-optimism = 仿真把 X 变成 0/1；X-pessimism = 把 X 传出去。*"without X-optimism, it would be almost impossible to simulate synchronous resets"* | `[业界]` Sutherland, *I'm Still In Love With My X!*, DVCon 2013 —— **仅取到检索摘要，[未经一手资料印证]** |
| **第三方观察** | 断言方案的额外好处：*"The assertions could also illuminate the need for X propagation through RTL code since the X's are now visible."* | `[业界]` Mills SNUG 2012 §2.5/§7.0 |

### 矛盾的根源

Verilog 的 `X` 语义在仿真中是**悲观**的（一律传播），在综合中是**乐观**的（当 don't care 自由优化），**两者不可能同时正确**。任何依赖 X 行为的设计决策都建立在这条裂缝上。

### `casex` / `casez` 是这条裂缝的具体形态

- `casex`/`casez` 的通配是**对称**的：case **表达式**一侧的 `x`/`z` 也会被当通配符去匹配 case item。这意味着一个未初始化信号上的 `X` 可以"命中"任意分支，仿真结果凭空变得合法，而综合出的电路没有这个行为。
- 工具侧不对称：Vivado 描述 `casez`/`casex` 时只提 "branch alternative" 里的 z/x，而 IEEE 1364 §9.5.1 的仿真语义连**表达式**一侧也通配——这就是 mismatch 的机理（`[业界]` UG901 v2025.1 逐字；W08 交叉取证）。
- `casez` 只把 `Z`/`?` 当通配、对未驱动的 `X` 做精确匹配；"意外产生一个 `Z`"比"意外产生一个 `X`"难得多，所以 `casez` 优于 `casex`。但 Mills 指出 `casez` **仍有固有的** sim/synth mismatch。
- `[SV]` `case ... inside`（SV-2009）对 case 表达式一侧的 `X`/`Z` **都不通配**，是 `casez`/`casex` 的正解；约束是老综合工具的支持度。
- ⚠ **教材立场相反**：p.177 建议"采用 case、**casex** 或 casez 语句来建立状态机的模型"，p.55-56 把 casez/casex 作为处理 don't-care 的推荐手段并给出 `casex(r^mask)` 掩码比较示例，p.331 实验代码也用了 `casex`。`references/13-xiayuwen-source.md` §8.2 已把这条列为"教材过时之处"。
- `[工具]` Verilator 的 `CASEX` 告警原话是 *"it is better style to use casez with '?' instead of 'x'"*；另有 `CASEINCOMPLETE`、`CASEOVERLAP` 可用于门禁。

### 本规范的取舍

**消除派 + 断言**：

1. RTL 里不主动赋 `X`（见 D06）。
2. **禁止 `casex`**；`casez` 仅在必须通配且只能用 Verilog-2001 时使用，通配符写 `?` 不写 `z`；`[SV]` 优先 `case ... inside`。与 `SKILL.md` G5 一致。
3. 在 case 之前对选择表达式加断言（`[SV]` 用 `ASSERT_KNOWN` 类宏；`[V2001]` 用 testbench 里的检查），把"非法输入"变成显式失败报告而不是隐式的 X 传播。
4. `[工具]` **Verilator 基本是二态仿真器**，"在 Verilator 上跑通"**不能**证明 `casex`/`casez` 的 X 语义安全。要验证 X 传播必须用四态仿真器（iverilog 或商业工具）。这一条要写进 CI 说明，否则会给人虚假的安全感。

### 什么情况下应当偏离默认

- 快速原型 / 没有断言基础设施的探索性代码 → 传播派在调试期仍有价值（X 能指出未初始化路径）。但**绝不能带进 tapeout / 出厂 RTL**。
- 掩码比较（教材 p.55-56 的 `casex(r^mask)` 场景）→ 改写成显式的位与比较 `if ((r ^ pattern) & mask) == '0`，不要用 `casex`。

---

## D08 · `unique` / `priority` 该不该到处加

### 各方立场与出处

| 立场 | 主张 | 出处 |
|---|---|---|
| **加派** | *"The `unique` prefix is recommended before all case statements, as it creates simulation assertions that can catch certain mistakes."* | `[业界]` lowRISC Style Guide |
| **慎用派** | *"Do not use the priority and unique directives with all SystemVerilog case statements and if-else-if statements. There are still some efficient coding styles that do not define all possible testing conditions … these efficient coding styles would trigger run-time simulation errors."* | `[业界]` Cummings, *SystemVerilog's priority & unique*, SNUG Israel 2005 §9.0/§14.0 |
| **中间派** | *"Many designers are led to believe that `unique case` and `priority case` solve their latch issues … This is simply not so. These constructs come close, but do not cover all the conditions where latches can inadvertently be generated."* | `[业界]` Mills SNUG 2012 |

### 分歧的实质

两方对"仿真断言失败"的**成本**判断不同：

- lowRISC 在一个有完整 DV 环境、CI 强制 lint-clean 的项目里，把断言失败当作**收益**（早发现）。
- Cummings 面向的是"case 表达式的合法取值确实不覆盖全部编码空间"的高效写法（例如状态编码只用了 5/8 个值）。此时 `unique` 会在每次进入非法态时刷 run-time error，**淹没真正的问题**。

### 一条双方都同意的硬结论

`unique` / `priority` **只能**消除"case item 缺失 / if-else-if 不完整"造成的 latch，**不能**消除"某个输出在某条分支里没被赋值"造成的 latch。Cummings SNUG 2005 §10.0 把它写成 Myth/Truth，Example 8/9 是实证：一个 `casez` 加了 `full_case`、case 本身是 full 的，但三个输出没在每个分支都赋值，DC 报告依旧推出三个 latch；把 `{mce1_n, mce0_n, rce_n} = 3'b111;` 挪到 case 之前，latch 立刻消失。

> **消 latch 的唯一可靠手段是"块首赋默认值"**（Mills SNUG 2012 §7.0：*"The only way to fully prevent unintended latches in combinational logic blocks is to assign every output for every condition."*）。这与 `SKILL.md` §1.C 的标准手法一致。

### 本规范的取舍

`[SV]`：

1. **取值域受控且可断言**的场景（状态机、操作码译码）→ 加 `unique case`，并配 `ASSERT_KNOWN` / `inside` 断言。
2. **取值域天然不满**的场景 → 用普通 `case` + `default` + 块首默认赋值，不加 `unique`。
3. **任何情况下都不得把 `unique`/`priority` 当作块首默认赋值的替代品。**
4. `[V2001]` 无此关键字，只能靠块首默认赋值——这也说明块首默认赋值才是根本手段。
5. 有意的优先级用 `if-else-if` 或级联三元表达，不要靠 case 分支重叠的隐式优先级（`[业界]` Cummings SNUG 1999 §4.7；lowRISC）。隐式优先级既不可读，又是 `parallel_case` 改变功能的温床，且优先级链是串行 MUX 级联、深度等于分支数。

### 什么情况下应当偏离默认

项目已有完整 SVA + formal 覆盖、且 CI 会把 run-time assertion 当作失败处理 → 可以采纳 lowRISC 的"一律 `unique case`"，收益（早发现）大于噪声成本。

---

## D09 · `case` 一定要写 `default` 吗

### 各方立场与出处

| 立场 | 主张 | 出处 |
|---|---|---|
| **必须写** | *"a `default:` statement is always included … even if all cases are covered. In simulation, a case expression that evaluates to `X` will not match any case and will behave as a latch, leading to different behavior than synthesis if no default is specified."* | `[业界]` lowRISC Style Guide |
| **语言层面非强制** | Verilog 语言不要求（*"An optional case 'default' can be included"*）；VHDL 要求 `others =>` | `[业界]` Cummings SNUG 1999 §2.6 / SNUG 2005 §15.6 |
| **default 可能掩盖 bug** | 主张用 `default: 'x` + 断言，而不是一个"看起来合法"的兜底值 | `[业界]` Mills SNUG 2012；Cummings SNUG 2005 的核心论点之一 |
| **教材** | "用 if 最好写上 else 项，用 case 最好写上 default 项"；FSM 章 p.177 要求必须写 | `[教材]` p.57、p.177 |
| **工具** | Verilator `CASEINCOMPLETE` 缺覆盖就告警；Verible `case-missing-default` 要求 `default`，**除非**用了 `unique`/`unique0` | `[工具]` Verilator warnings 文档；Verible 规则集 |

### 分歧点其实很窄

三份 SNUG 论文与 lowRISC 在"综合用 RTL 的组合块里必须有 default"这点上**没有实质分歧**，分歧只在措辞层面（语言允许 vs 规范要求）。真正的分歧只有两处：

1. 加了 `unique` 之后是否还要 `default`（Verible 认为可以不要；反方认为 `unique` 只在仿真期检查、综合器把它当 don't-care，缺 default 会 mismatch）；
2. `default` 该赋什么（见 D06）。

时序块（`always_ff`）里的 case 由于状态被寄存器保持，不写 `default` 不会推 latch，但会留下 X 传播和寄生状态问题。

### 本规范的取舍

**一律写 `default`**，与 `SKILL.md` C4 / F4 一致，包括加了 `unique` 的情形、包括时序块。**推荐写法是"块首赋默认值 + `default: ;`（空）"**——这样既无 latch，又不用一个"看起来合法"的兜底值掩盖非法输入，正好调和了上面的第 3 种立场。

对状态机另有一条更强的要求（`SKILL.md` F5，`[教材]` p.381 可综合(12)）：**状态数不是 2ⁿ 时必须明确描述所有 2ⁿ 种状态的行为**，`default` 回安全态就是它的落地形式。

### 什么情况下应当偏离默认

没有。这一条是本篇里分歧最小的议题。

---

## D10 · 独热 vs 二进制 / 格雷编码

### 各方立场与出处

| 立场 | 主张 | 出处 |
|---|---|---|
| **AMD** | ≤32 状态时 **one-hot 是默认**；一般利于速度和功耗。另给 Gray（相邻 1 位翻转、最小化冒险毛刺、可降功耗）、Johnson（长路径无分支）、Sequential（最小化次态方程）的适用条件 | `[业界]` UG901 v2025.1 p.178–179 |
| **Intel** | 综合工具**对 FPGA 常用 one-hot、对 CPLD 常用最少位编码**，但具体选择因状态机和器件而异 | `[业界]` Quartus SE UG-20175 §2.6.4 p.79 |
| **Lattice** | 二进制/格雷触发器少但组合函数宽，**适合 CPLD**；FPGA 触发器多、函数生成器窄，二进制/格雷可能速度密度双输。**大而复杂的 FSM 在 FPGA 上通常首选 one-hot；小 FSM 用二进制或格雷可能更高效** | `[业界]` Lattice TN1008 p.15-3（2012 年文档，**时效性存疑**） |
| **教材** | FPGA 实现的状态机建议采用**独热码**：多用两个触发器但组合电路可省，速度和可靠性显著提高，总单元数无显著增加 | `[教材]` p.177、p.171 |
| **lowRISC / Cummings** | **不要在 RTL 里写死编码**：用 `enum` + 符号名，编码交给综合工具或脚本（`set_fsm_encoding_style` 等） | `[业界]` lowRISC Style Guide；Cummings SNUG 1998 |

### 决策变量（没有普适答案）

| 变量 | 倾向 one-hot | 倾向二进制/格雷 |
|---|---|---|
| 目标器件 | FPGA（FF 充裕、LUT 是瓶颈） | ASIC（FF 面积贵、组合逻辑便宜）、CPLD |
| 状态数 | 多（≲32 时 AMD 默认 one-hot） | 少（≲8–16） |
| 分支密度 | 分支多 → 次态逻辑优势大 | 分支少、长链路 → Gray/Johnson |
| 功耗 | 每次转移 2 位翻转 | Gray 每次 1 位翻转 |
| 可靠性 | one-hot 有天然非法态检测能力，但**必须**显式写非法态恢复 | 需额外 Hamming 保护 |
| CDC | — | Gray 用于跨域计数器（异步 FIFO），这是另一回事，不属于 FSM 编码之争 |

### 本规范的取舍

1. **不在 RTL 里写死编码**：状态用 `localparam`（`[SV]` 用 `enum`）定义符号名（`SKILL.md` F2），编码方式作为综合脚本变量 / 属性设置。这一条 lowRISC 与 Cummings 一致，是本规范的默认。
2. `[FPGA]` 默认让工具选（AMD `FSM_ENCODING` 默认 `auto`，≤32 状态时通常取 one-hot）。
3. `[ASIC]` 默认二进制；确需 one-hot 时通过综合脚本设置，不改 RTL。
4. **无论哪种编码，`default` 都必须回安全态**（D06/D09）。one-hot 的非法态（如全 0、多位为 1）**不会**因为编码是 one-hot 就自动被处理。
5. `[FPGA]` "安全状态机"是工具选项（AMD `FSM_SAFE_STATE`、Intel Safe State Machine），**不是 CDC 的替代品**。Intel 明确建议：对有异步输入的设计，正确做法是同步器寄存器链，而不是依赖 safe state machine 选项；且综合工具会把正常操作到达不了的 default 态逻辑**优化掉**，除非显式开了 safe-FSM 选项。

### 什么情况下应当偏离默认

- 需要 formal 等价性检查或安全认证、要求编码在 RTL 与网表间可追溯 → **在 RTL 里写死编码并关掉工具的 FSM 重编码**（AMD 用 `FSM_ENCODING = user_encoding` 或 `none`）。工具自动重编码会损害 formal 映射与调试稳定性。
- 需要 SEU 加固 → one-hot + 汉明检测更容易做安全态，此时编码是功能需求而非优化选项，写死在 RTL 里。

---

## D11 · `always @*` vs `always_comb`：敏感表语义**真的不同**

这不是"新旧之争"，是 LRM 明文规定的行为差异。**这是本篇技术含量最高的一条。**

### 一手条文

- `[SV]` IEEE 1800 §9.2.2.2.1（逐字）：`always_comb` 的隐式敏感表包含块内（及块内所调用函数内）被读取的每个变量的最长静态前缀展开，**但有两条例外**：
  a) 块内（或所调用函数内）声明的变量；
  b) **块内（或所调用函数内）同时被写的表达式**。
- `[V2001]` IEEE 1364-2005 §9.7.5（逐字）：`@*` 的排除项只有两条——只出现在 `wait`/事件表达式里的标识符，以及**只**作为赋值左值出现的标识符。并给出 Example 2：

```verilog
// IEEE 1364-2005 §9.7.5 Example 2：@* 等价于 @(a or b or c or d or tmp1 or tmp2)
always @* begin
    tmp1 = a & b;
    tmp2 = c & d;
    y    = tmp1 | tmp2;
end
```

**即：`@*` 会把 `tmp1`/`tmp2`（块内被写、同时在块内被读）算进敏感表，而 `always_comb` 不会。**

### 另外三条 `always_comb` 的 LRM 附加语义

- 零时刻**自动执行一次**；`always @*` 要等敏感表里有信号变化才第一次触发。
- 对**函数体内**引用的信号敏感；`always @*` 只对函数的**实参**敏感（Sutherland 称后者为 bug）。
- 左值**不得被任何其它进程写**（例外：对同一变量的不同元素赋值，只要最长静态前缀不重叠）。

> `[存疑]` 调研记录：LRM 说这些检查"可选、非标准强制"，2013 年的观察是"当时没有仿真器提供这类告警，但 lint 检查器和综合编译器会"。**这条工具支持现状在今天是否仍成立没有新的一手资料**，因此规范里应表述为"依赖 lint / 综合工具报告多驱动"，而不是"仿真器会报错"。

### 后果

从 `always @*` 迁移到 `always_comb` 时，**"先读后写"的代码会静默改变行为**——不报错、不告警，仿真结果直接变了。

```verilog
// 反例，不要抄：always_comb 下 a 变化时 c 拿到旧 b，块不会因 b 变化而重触发
always_comb begin
    c = b;
    b = a;
end

// 正例：按依赖顺序写
always_comb begin
    b = a;
    c = b;
end
```

> `[存疑]` 上述反例**综合**后会得到什么，调研中**没有取到任何一手出处**。多数综合工具对"组合块内先读后写的变量"是推锁存器或报 warning，而不是简单按数据流合并。因此本规范的表述是"该写法在仿真与综合两侧都不确定，一律禁止"，而不是"综合会怎样"。

### 本规范的取舍

1. `[V2001]` 用 `always @(*)`，`[SV]` 用 `always_comb`（`SKILL.md` C2）。**两者都禁止手写敏感表**——手写敏感表漏项是仿真-综合不一致的经典来源（`[教材]` p.380 可综合(5) 要求列全所有输入，`@(*)` 是其现代等价写法）。
2. **无论用哪个，都禁止在组合块内"先读后写"同一变量**（`SKILL.md` C5：本块赋值的变量不得在本块中被读作输入，`[教材]` p.380 可综合(7)、p.180）。中间变量必须"先赋值再使用"，不得依赖块被重新触发来收敛。
   这条规则让 `@*` 与 `always_comb` 的语义差异**在本规范的代码里不可能被观察到**——这正是本规范采纳它的理由。
3. **从 `always @*` 迁移到 `always_comb` 必须配回归仿真**，不能当作纯语法替换。
4. `[SV]` `always_comb` **不能**阻止 latch 推断——LRM 只是"建议"工具告警。消 latch 仍然靠块首默认赋值（见 D08）。

### 什么情况下应当偏离默认

老工具链或混合语言流程不支持 `always_comb` → 用 `always @(*)`，其余规则不变。反过来不成立：不要为了"看起来现代"把 V2001 代码机械改成 `always_comb`。

---

## D12 · `initial` 初值 / `reg x = 0;` 到底算不算规范

### 各方立场与出处

| 立场 | 主张 | 出处 |
|---|---|---|
| **AMD（强烈建议写）** | GSR 网络在配置结束时把所有寄存器初始化成 HDL 里写的初值；没写则综合器自选（Vivado 通常给 0）。**强烈建议初始化所有推断出的寄存器、SRL、存储器**，这能减少"仅为初始化而加的复位"，并让 RTL 仿真更贴近配置后硬件 | `[业界]` UG949 v2023.1 Ch.3 p.71；UG901 v2025.1 Ch.5 p.86 |
| **Intel（支持但有警告）** | Quartus SE 把寄存器默认值转成 **Power-Up Level**；但大范围设 Power-Up Level = high 会因 **NOT gate push-back** 插入大量反相器而劣化 QoR，并可能干扰使能推断与二级控制逻辑推断，也更难移植 | `[业界]` Quartus SE UG-20175 §2.5.1.1 p.68 |
| **ASIC（禁止依赖）** | ASIC 综合器忽略 `initial` 和声明初值，只在仿真生效，制造"仿真通过、硅片挂"的经典 bug | 调研标注 **[未经一手资料印证]**（属公认工程常识，本篇保留该标注） |
| **教材** | 可综合 RTL 中禁止 `initial`（`SKILL.md` I 的来源之一） | `[教材]` p.380–381 可综合标准 |

### 分歧根源

**SRAM-based FPGA 有配置比特流可以直接写 FF 的 INIT 属性，ASIC 没有。这是器件物理能力差异，不是风格偏好。**

### 本规范的取舍

1. `[通用]` **可综合 RTL 中禁止 `initial` 块**（`SKILL.md` §1.I）。这条不变。
2. `[FPGA]` **允许在声明处写初值**（`reg [3:0] state = 4'b0001;`）——注意这**不是** `initial` 块，`SKILL.md` I 的禁令点名的是 `initial` 块。初值的作用是让配置后的硬件与 RTL 仿真起点一致。
3. `[ASIC]` **禁止依赖任何初值**。可以写（无害），但设计的正确性不得建立在它上面。
4. **跨目标代码：初值与显式复位同时写**——初值给 FPGA 省一棵复位树，显式复位给 ASIC 保底，并在 CI 里对两条路径都跑仿真。
5. `[FPGA]` 存储器初始化用 `$readmemh`/`$readmemb` 时**必须带索引参数**（`$readmemh("init.hex", mem, 0, 1023);`），否则不同工具对起始地址的处理不一致。

```verilog
// 正例（跨 FPGA/ASIC 的写法：初值 + 显式复位都写）
reg [3:0] state = 4'd0;                       // FPGA: 进 bitstream；ASIC: 被忽略
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) state <= 4'd0;                // ASIC 的保底
    else        state <= next_state;
end
```

```verilog
// 反例，不要抄（把 FPGA 写法直接搬到 ASIC 项目）
reg busy = 1'b0;
always @(posedge clk) busy <= start | (busy & ~done);
// ASIC 综合下 busy 上电为 X 且永远出不了 X 态：仿真通过、流片后挂
```

### 什么情况下应当偏离默认

- 纯 FPGA 项目、且经评估复位树确实是时序瓶颈 → 可以对数据通路只写初值不写复位（此时 D02 的三个前提仍适用）。
- 目标是 Intel FPGA 且要把大批寄存器初始化为 1 → **不要**用 Power-Up Level 属性批量设置，那会插入大量反相器。改用显式复位。

---

## D13 · 存储器：RTL 推断 vs IP 生成 vs 直接例化原语

### 各方立场与出处

| 立场 | 主张 | 出处 |
|---|---|---|
| **AMD（推荐推断）** | 推断的优点：可移植、易读、自文档化、仿真快；缺点：可能拿不到全部 RAM 配置、结果可能次优。**"因为推断通常结果不错，它是推荐方法"**，除非某用法不被支持或 PPA 不达标 | `[业界]` UG949 v2023.1 p.62–63 |
| **AMD（XPM 折中）** | 标准推断不支持所需特性时推荐 XPM：跨器件族可移植、支持非对称位宽、QoR 可预期；缺点是只能用 XPM 支持的选项 | `[业界]` UG949 v2023.1 p.62–63 |
| **AMD（例化原语）** | 优点：对实现的最高控制、可用块的全部能力；缺点：可移植性差、冗长难懂 | 同上 |
| **Lattice（推荐 IP 生成）** | **不推荐用 RTL 描述 RAM**，应通过 IPexpress 生成 | `[业界]` Lattice TN1008 p.15-16（**2012 年文档，调研明确标注该结论"很可能已不适用于 Radiant"**） |
| **Microchip / Synplify** | 提供完整的 `syn_ramstyle` 推断控制，文档整体面向**推断** | `[业界]` *Inferring Microchip PolarFire RAM Blocks* (2025) |

### 一条被忽视的机理

AMD 明确指出：**综合器不会默认优化被例化的器件库单元**；即便让它优化，也做不到 RTL 那样的深度，通常只能优化到/从这些单元的路径，而**不能穿过**它们。例如一个被例化的 SRL 落在长路径上会直接成为瓶颈（SRL 的 clock-to-out 比普通寄存器慢）。

这意味着"例化原语"换来的控制力，代价是**在那一点上永久放弃了工具的优化能力**。

### 本规范的取舍

**优先推断 → 推断不满足需求时用厂商参数化宏（XPM / altsyncram 等）→ 最后才例化原语。** 每下一级都要在模块头注释里写明为什么上一级不行。

推断能成功的前提条件（这些不是风格建议，是硬性的推断条件）：

| 条件 | FPGA 侧要求 | 出处 |
|---|---|---|
| 存储阵列本身 | **绝不能复位**。Intel：存储块内容在运行期无法用复位清除，描述了带复位的 RAM 内容会退化成普通逻辑单元 | `[业界]` UG949 p.65；UG-20175 §2.4.1.2 |
| RAM 输出寄存器 | 可复位，但**必须同步**、且**只能复位到 0** | `[业界]` UG949 p.65 |
| 读方式 | 同步读 → BRAM；异步读 → 只能是分布式 RAM/LUTRAM。Intel 更严：**禁止 `assign q = ram[raddr_reg];` 这种连续读写法** | `[业界]` UG901 p.118；UG-20175 §2.4.1.1 |
| 输出寄存器吸收 | 必须与 RAM 数组**同层次**、**扇出为 1**、**无反馈** | `[业界]` UG949 p.64–66 |
| 读写同步模式 | 三种（read-first / write-first / no-change）必须**显式选定**并按模板写；AMD 把 write-first 标为 recommended template | `[业界]` UG901 p.124–130 |
| 不要混块 | 不要把 RAM 的读写放进带复位信号的 `always` 块里——**即使那个复位是给块内另一个无关寄存器的** | `[业界]` UG-20175 §2.4.1.2（明示不支持） |

> `[ASIC]` 侧的对应关系不同：用寄存器堆还是 SRAM 宏由 memory compiler 与 PPA 权衡决定，且单口 SRAM 通常**没有**异步读选项。ASIC 上 SRAM 宏一律是例化（memory compiler 产出），"推断"只适用于小的寄存器堆。

> `[存疑]` UG949 原话是 "the output signal can only be reset to 0"，但 BRAM 原语实际支持可配置的 `SRVAL_A/SRVAL_B`（非零复位值）。**"推断路径下只能复位到 0"是调研者的解读，UG949 没有明说是推断限制还是硬件限制**，落地前需实际综合实验确认。

### 什么情况下应当偏离默认

- 需要 BRAM 的特殊配置（级联、ECC、非对称位宽、特定 collision 行为）→ 用 XPM 或例化原语。
- 目标是 Lattice 且使用 Diamond 时代工具链 → 遵从厂商建议用 IP 生成。**但 TN1008 是 2012 年文档，用 Radiant 时应先实测推断是否可用**（调研已标注该结论时效性存疑）。
- `[ASIC]` SRAM 宏一律例化，不适用本条默认。

---

## D14 · 门控时钟：FPGA 转 CE vs ASIC 插 ICG

### 各方立场与出处

| 场景 | 做法 | 出处 |
|---|---|---|
| **ASIC** | 时钟门控（ICG cell）是**标准低功耗手段**，综合器有专门的 clock gating insertion pass；RTL 里写 `if (en) q <= d;` 反而是**期望**的写法，让工具去插 ICG。收益是同时省功耗和面积（省掉回环 MUX） | `[业界]` Emnett & Biegel, *Power Reduction Through RTL Clock Gating*, SNUG San Jose 2000（含实测硅数据） |
| **FPGA（AMD）** | **反向操作**：`synth_design -gated_clock_conversion auto` 把时钟路径上的门**转回** clock enable；真要关时钟网络用 BUFGCE / BUFGCTRL 等专用缓冲器，不是 fabric 逻辑门 | `[业界]` UG949 v2023.1 p.135；UG901 v2025.1 |
| **FPGA（Intel）** | 门控时钟不属于同步设计范式，贡献时钟偏斜、**对毛刺敏感（可致设计失效）**、器件迁移困难；用专用时钟控制块而不是 AND/OR 门；提供 Auto Gated Clock Conversion | `[业界]` Quartus SE UG-20175 §1.2.2.5/§1.2.2.6 |
| **FPGA（Lattice）** | 门控时钟"不被鼓励"，会吃光一个 PFU 的时钟资源 | `[业界]` Lattice TN1008 p.15-13 |

### 这不是"哪个对"的分歧

而是**同一段 RTL 在两条流程里被反向变换**：

- 写 `if (en) q <= d;` → 两边都安全（FPGA 映射到 FF 的 CE 引脚或 BUFGCE，ASIC 让工具插 ICG）。
- 写 `wire gclk = clk & en;` → ASIC 里勉强能用（会被换成 ICG），**FPGA 里是明确的错误**（fabric LUT 输出有毛刺、失去低偏斜时钟网、无法约束）。

### 本规范的取舍

**RTL 一律写 `if (en) q <= d;`，绝不手写门控时钟。** 与 `SKILL.md` E1（时钟不得由组合逻辑产生）、E5（分频用时钟使能）一致。

```verilog
// 正例：唯一可移植的写法
always @(posedge clk) begin
    if (en) q <= d;
end
// FPGA: 映射到 FF 的 CE 引脚 / BUFGCE；ASIC: 综合器可自动插入 ICG
```

```verilog
// 反例，不要抄：fabric 门控时钟 —— 毛刺 + 偏斜 + 无法约束
wire gclk = clk & en;
always @(posedge gclk) q <= d;
```

`[ASIC]` 必须显式例化门控单元时，用带 `test_en` 的 ICG 包装原语，并把使能接到 `scan_enable`/`test_mode`（见 `references/06-clock-reset-cdc.md`）。门控使能必须与被门控时钟同步、且在时钟低电平期间稳定。

### 一个相关但独立的坑

`[FPGA]` `KEEP_HIERARCHY` / `DONT_TOUCH` / `MARK_DEBUG` 放在需要改动的层次或实例上会**干扰门控时钟转换**（UG901 CAUTION）。调试属性和 QoR 优化在这里是冲突的。

### 什么情况下应当偏离默认

`[FPGA]` 需要真正关掉整片时钟网络（不只是省 FF 翻转）→ 用 BUFGCE / BUFGCTRL / Intel Clock Control Block 等**专用硬件**，仍然不是逻辑门。此时时钟切换要用 glitch-free 结构，且切换期间源时钟必须继续跑若干周期（Intel §2.6.2 明示：若时钟 A 立刻停止，电路会卡死）。

---

## D15 · lint waiver：内联注释 vs 集中文件

### 各方立场与出处

| 立场 | 主张 | 出处 |
|---|---|---|
| **内联派** | 豁免离代码最近，读代码就知道为什么关。这也是 Verilator 官方文档给出的第一种方法、多数中小项目做法。缺点：**会向下传播到被 `include` 的子文件**（Verilator 原文），且容易忘写 `lint_on` | `[工具]` Verilator 官方 warnings 文档 |
| **集中派** | 源码零污染，review 时能一眼审计所有豁免。Verilator 官方推荐用于第三方代码；OpenTitan 用 `lint/<ip>.vlt`。缺点：豁免与代码分离，代码改动后 waiver 可能失效却无人察觉（行号型 waiver 尤其脆弱） | `[工具]` Verilator 文档；OpenTitan 仓库实践 |
| **双方共识** | **绝不用全局 `-Wno-XXX`**——Verilator 原文：它 *"prevents other users from compiling the sources without knowing the magic set of disables needed"* | `[工具]` Verilator 文档 |

相关的第二层分歧：**`-Wall` 是否作为 CI 硬门禁**。OpenTitan 把 Verilator lint 作为 PR 合并的硬门禁；反对方指出 `-Wall` 打开的 `UNUSEDSIGNAL` 与 `DECLFILENAME` 在参数化 IP、自动生成代码场景下会产生大量非 bug 告警。

### 本规范的取舍

与 `SKILL.md` §2「最小范围 + 写明理由」一致，具体细化为：

1. **自有代码 + 单点问题 → 内联 `lint_off`/`lint_on`**，成对出现、范围最小、注释写清理由。这是 `SKILL.md` §2 给出的示例形态。
2. **第三方代码、自动生成代码、或需要审计留痕 → 用 `.vlt` 控制文件集中豁免**，并作为**第一个**文件传给 Verilator。集中文件同样满足"最小范围 + 写明理由"，不与 `SKILL.md` §2 冲突。
3. **`-Wall` 全开作为 CI 硬门禁**；只允许用 `.vlt` 对特定目录关掉 `UNUSEDSIGNAL` / `DECLFILENAME`。
4. **以下告警一律不许豁免**：`WIDTH` / `LATCH` / `MULTIDRIVEN` / `CASEINCOMPLETE` / `BLKSEQ` / `COMBDLY`。这六条对应的正是本规范的铁律（位宽、锁存器、多驱动、case 完整性、阻塞/非阻塞误用）。
5. **绝不在命令行上全局 `-Wno-XXX`**（`SKILL.md` §2 已明令）。
6. 用 `--waiver-output` 半自动生成豁免文件时，**必须人工审阅**后再入库。

> `[工具]` 一个实测到的坑（`SKILL.md` §2 已记）：**注释的第一个词如果是 `verilator`，会被当成编译指示**而报 "Unknown verilator comment"。写文档注释时在前面加个字（如 `注：`）避开。

### 什么情况下应当偏离默认

内联豁免出现在头文件 / 被 `include` 的片段里 → 一律改用 `.vlt`，因为内联作用域会向下传播到包含它的所有文件，范围反而失控。

---

## D16 · 带复位与不带复位的触发器能否写在同一个 `always` 块

### 各方立场与出处

- **不能同块** `[ASIC]`：*"a designer should not mix resetable flip-flops with follower flip-flops (flops with no resets) in the same procedural block or process"*（`[业界]` Cummings/Mills/Golson SNUG Boston 2003 §3.1）。实测结论：反例中 `q2` 虽没有复位语句，但因为它和 `q1` 共处 `else` 分支，`rst_n` 事实上变成了 `q2` 的**数据使能**，综合出一个多余的可加载触发器 + 额外组合逻辑。
  **重要限定（原文）**：这个多余逻辑*"is only a result of using a synchronous reset. If an asynchronous reset approach had been used, then both coding styles would synthesize to the same design"* → **同步复位下是硬约束，异步复位下只是风格建议。**
- **AMD 的两条建议** `[FPGA]`：(a) 优化去掉复位时**不要**用注释掉复位分支的方式（会把异步复位变成使能，产生 `CE = ~rst` 的畸形结构），正确做法是**拆成两个时序过程**；(b) *"When using a reset, make sure that all registers in the procedural statement are reset."*（`[业界]` UG949 p.54 / p.55 TIP）。两条合起来就是"同块要么全复位、要么全不复位"。
- **反方（可读性）**：拆块会让代码变长、相关逻辑分散。这是可读性 vs QoR 的权衡。

### 本规范的取舍

**同一个 `always` 块内要么全部寄存器都复位、要么全部不复位；需要区分时就拆块。** 这与 `SKILL.md` D4（每个时序 `always` 只由一个时钟沿触发）属于同一类"一个块只描述一种触发器"的纪律。

```verilog
// 反例，不要抄：q2 没有复位语句，但 rst_n 变成了它的数据使能
always @(posedge clk) begin
    if (!rst_n) q1 <= 1'b0;
    else begin
        q1 <= d;
        q2 <= q1;
    end
end

// 正例：拆成两块
always @(posedge clk) begin
    if (!rst_n) q1 <= 1'b0;
    else        q1 <= d;
end

always @(posedge clk) begin
    q2 <= q1;              // 干净的 follower FF，无复位
end
```

### 什么情况下应当偏离默认

采用异步复位、且综合报告确认没有多余逻辑 → 可以放宽为风格建议。但本规范仍推荐拆块，因为它让"哪些寄存器不复位"这件事在代码里显式可见，是 D02 豁免条件的自然落地形式。

---

## D17 · 两段式 vs 三段式 FSM（本篇只做定位，展开见 `05-fsm.md`）

- **三段式**：状态寄存 / 次态组合译码 / 输出寄存。`SKILL.md` F1 的默认，也是教材 p.168-173 的多 `always` 块写法。优点：输出是寄存器输出，无组合毛刺、时序干净、跨模块接口稳定。
- **两段式**：`enum` + 组合次态 + 时序状态寄存器，输出用组合逻辑直接译码。lowRISC / OpenTitan 风格。优点：块少、代码短。
- **教材自身也不一致**：p.169 给单 `always` 块写法，p.173 又说 Synopsys 推荐多 `always` 块（`references/13-xiayuwen-source.md` 已记录该冲突）。
- **本规范取舍**：默认三段式（`SKILL.md` F1）。理由是 `SKILL.md` H3 要求"模块间只走寄存器输出"，三段式天然满足。详细对比与偏离条件见 `references/05-fsm.md`。

---

## 附录 A · 本篇保留的"未印证 / 存疑"标注

这些是调研阶段就没拿到一手出处的说法。**本篇原样保留标注，不做加强，也不据此立规则。**

| # | 说法 | 状态 |
|---|---|---|
| 1 | "ASIC 综合器忽略 `initial` 与声明初值" | `[未经一手资料印证]`（公认工程常识，无可引用一手文档） |
| 2 | "X 安全派禁止 RTL 赋 X" 的**厂商文档**依据 | `[未经一手资料印证]`（技术理由可自洽推导，但无一手厂商文档） |
| 3 | RMM 推荐同步复位的原文 | `[未经一手资料印证]`（经 SNUG 2003 转引，RMM 原文未取到） |
| 4 | Cummings/Mills SNUG 2002 复位论文正文；Cummings SNUG 1998 FSM 论文正文；Sutherland DVCon 2013 X 论文正文 | 均**未取到正文**，仅书目/摘要 |
| 5 | Vivado 对 SystemVerilog `unique` / `priority` 的支持程度 | UG901 v2025.1 全文检索**未找到**支持声明；`[未经一手资料印证]`，需实测 |
| 6 | `always_comb` 中**函数调用**时敏感表的细节推断 | AMD 文档只说"由驱动它的逻辑推断"，未说明函数内部引用信号；`[存疑]` |
| 7 | "BRAM 推断路径下输出只能复位到 0" 是推断限制还是硬件限制 | UG949 未明说；调研者解读，`[存疑]`，需综合实验确认 |
| 8 | Lattice "不推荐 RTL 推断 RAM" 的现行有效性 | 依据是 2012 年 Diamond 时代文档，`[时效性存疑]` |
| 9 | Intel Quartus **Pro** Edition 的现行内容（`no_rw_check` 语义、shift register 推断阈值等） | 本文 Intel 条目全部引自 Standard Edition UG-20175 (2018)，`[需以 Pro 版复核]` |
| 10 | "组合块内先读后写的变量"**综合**后的结果 | 无一手出处；本规范因此写成"一律禁止"而非"综合会怎样" |
| 11 | "ASIC 库与 STA 流程可以有意利用 latch 做 time borrowing" | 方向对，`[无一手出处]` |
| 12 | `always_comb` 单一写者检查的**工具支持现状** | 依据是 2013 年的观察，`[存疑]` |

---

## ⚠️ 与主规范的冲突

**本篇未发现与 `SKILL.md` 铁律的实质性冲突。** 以下三处是需要上层裁决的**措辞/覆盖面问题**，不是技术冲突：

1. **`SKILL.md` §1.I 禁止 `initial` 块，但未表态"声明初值 `reg x = 0;`"是否允许。**
   本篇 D12 按"声明初值不是 `initial` 块，`[FPGA]` 允许、`[ASIC]` 不得依赖"处理。
   建议 `SKILL.md` I 的禁令措辞明确加一句"（声明处初值不在此禁令内，见 D12）"，否则模型可能把 `reg [3:0] s = 4'd0;` 也判成违规。

2. **`SKILL.md` §2 说"豁免 lint 规则的**唯一**正确姿势：最小范围 + 写明理由"，并只给了内联示例。**
   本篇 D15 把 `.vlt` 集中豁免也纳入"最小范围 + 写明理由"的合法形态（用于第三方/生成代码）。
   两者在原则上一致，但"唯一"一词加上只给内联示例，容易被读成"禁止 `.vlt`"。建议 `SKILL.md` §2 补一句"第三方/生成代码用 `.vlt` 集中豁免，见 `references/14-disputes.md` D15"。

3. **`SKILL.md` B1 要求低有效复位带 `_n` 后缀，而 AMD UG901 要求控制输入一律 active-High。**
   本篇 D04 的处理是"模块接口按 B1 命名，AMD FPGA 目标在模块边界统一转一次极性"。这不推翻 B1，但 `SKILL.md` §1.E 目前没提极性转换这件事。建议在 E 组补一行。

此外记录两处**教材自身前后不一致**（已由 `references/13-xiayuwen-source.md` §8.4 认领，本篇 D06/D17 沿用其结论，未另行裁决）：
`case default` 赋 `'bx`（p.177、p.181）vs 回安全态（p.171、p.177 例外条款）；单 `always` 块 FSM（p.169）vs 多 `always` 块（p.173）。

---

## 本篇检查清单

写完 RTL 后，凡涉及以下议题，逐条确认自己的选择是"默认"还是"经论证的偏离"：

- [ ] 模块头注释写明了复位方式（同步/异步/同步化异步）与极性，且与目标器件匹配（D01/D04）
- [ ] 用了异步复位的地方，都有复位同步器（异步断言、同步释放）；多时钟域每域一套（D01）
- [ ] 未复位的寄存器全部落在数据通路上，且伴随的 `valid`/`enable` 已复位、复位周期数 ≥ 流水深度（D02）
- [ ] 时序块里复位分支写在使能分支之前；若按 Intel 语义写，模块头注释已注明（D03）
- [ ] 复位极性在全设计只翻转一次，没有"同一物理复位的高/低有效两个版本"（D04）
- [ ] 全文搜索 `full_case` / `parallel_case`（含注释式与属性式）零命中（D05）
- [ ] 全文搜索 `'bx` / `'hx` 赋值：状态机次态、跨模块接口、`valid` 类信号上零命中；宽松档的每一处都写了理由注释（D06）
- [ ] 所有 `x`/`z` 字面量都写了全位宽（`8'hxx` 而非 `'bx`）（D06）
- [ ] 全文搜索 `casex` 零命中；`casez` 只用 `?` 通配且每处都有理由（D07）
- [ ] 明白"Verilator 跑通 ≠ X 语义安全"，X 相关行为已用四态仿真器验证（D07）
- [ ] 每个组合块的开头都有默认赋值；没有把 `unique`/`priority` 当作消 latch 手段（D08）
- [ ] 每个 `case` 都有 `default`（含加了 `unique` 的、含时序块里的）（D09）
- [ ] 状态用符号名定义，RTL 里没有写死编码；`default` 回安全态；非法态恢复路径显式存在（D10）
- [ ] 组合块内没有"先读后写"同一变量；从 `always @*` 改 `always_comb` 时跑了回归（D11）
- [ ] 跨 FPGA/ASIC 的代码：初值与显式复位都写了（D12）
- [ ] 存储器优先用推断；存储阵列没有被复位；读写模式显式选定；输出寄存器同层次、扇出 1、无反馈（D13）
- [ ] 全文搜索 `clk &` / `clk |` 等 fabric 门控时钟零命中；分频只用时钟使能（D14）
- [ ] lint 豁免范围最小、写明理由；`WIDTH`/`LATCH`/`MULTIDRIVEN`/`CASEINCOMPLETE`/`BLKSEQ`/`COMBDLY` 无一豁免；命令行无全局 `-Wno-XXX`（D15）
- [ ] 每个时序 `always` 块内的寄存器要么全复位、要么全不复位（D16）

