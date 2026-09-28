---
name: rtl-verilog-standard
description: 编写、审查、重构 Verilog/SystemVerilog RTL 代码时必须使用的团队编码规范。涵盖命名与文件组织、组合/时序逻辑写法、阻塞与非阻塞赋值、锁存器规避、状态机三段式、复位与时钟域(CDC)、位宽与符号、存储器推断、可综合子集、testbench 自检、以及 Verilator/Vivado/Yosys 工具链命令。只要任务涉及 .v/.sv/.svh 文件、module/always/assign/case/FSM/触发器/计数器/FIFO/握手/AXI/流水线/综合/仿真/lint/时序约束，或用户提到 RTL、Verilog、SystemVerilog、FPGA、ASIC、数字电路设计、IP 核、testbench、UVM，就应当使用本 skill——即使用户没有明说"按规范写"。生成任何一行 RTL 之前先读它，改别人的 RTL 之前也先读它。
license: 团队内部使用。教材条目版权归《Verilog 数字系统设计教程(第4版)》(夏宇闻) 及原出版方所有，此处仅作规范溯源引用。
---

# RTL (Verilog / SystemVerilog) 编码规范

这份规范的目的很具体：**让不同的模型、不同的人写出来的 RTL 看起来像同一个人写的，并且综合出来的电路和作者心里想的那个电路是同一个。**

RTL 不是软件。你写的每一行都会变成门和触发器，而语言允许你写出"仿真通过、综合出来完全是另一回事"的代码。本规范里绝大多数条款存在的理由都是这一句话。

规范来源有三处，条目里会标注：
- `[教材]` —《Verilog 数字系统设计教程(第 4 版)》夏宇闻 编著，清华大学出版社（标注书上页码）
- `[业界]` — lowRISC/Google style guide、Cliff Cummings SNUG 论文、Xilinx/Intel 官方指南、开源核实践
- `[工具]` — Verilator / Yosys 实测行为（本规范所有代码模板都经过实际 lint 与综合验证）

适用标签：`[通用]` `[FPGA]` `[ASIC]` `[V2001]` `[SV]`。**默认基线是 Verilog-2001**；SystemVerilog 只用可综合子集，见 `references/02-synthesizable-subset.md`。

---

## 0. 动手之前：先把设计契约写下来

不要一上来就写 `module`。先在模块头部注释里回答这 5 个问题，答不上来就说明需求还没想清楚：

1. **时钟**：几个时钟域？各自频率？本模块有没有跨域路径？
2. **复位**：同步还是异步？低有效还是高有效？哪些寄存器可以不复位？
3. **接口时序**：valid/ready 握手？固定延迟？谁提供背压？违反协议会怎样？
4. **吞吐与延迟**：每周期一个数据，还是 N 周期一个？关键路径预期在哪？
5. **面积/频率取舍**：要不要流水？要不要资源共享？

写不出来就先问用户，不要替他假设。**假设错的架构，后面的代码写得再规范也是白写。**

---

## 1. 铁律（违反即打回）

这一节是硬性的。其余章节解释细节，但 A~I 这九组共 46 条必须无条件遵守。

### A. 文件与模块组织

| # | 规则 | 出处 |
|---|------|------|
| A1 | **一个文件只放一个 module**，也不要把一个 module 拆到几个文件里 | `[教材]` p.380 语汇(1) |
| A2 | **文件名 == 模块名**（`counter.v` 里就是 `module counter`） | `[教材]` p.380 语汇(2) `[工具]` Verilator `DECLFILENAME` 会查 |
| A3 | 文件以 `` `default_nettype none `` 开头、`` `default_nettype wire `` 结尾 | `[业界]` lowRISC |
| A4 | 每行只写一个声明或语句；用逐层缩进（4 空格，**不用 Tab**） | `[教材]` p.380 语汇(3)(4) |

> **引用格式说明**：书上 p.380 同一页印着**两份各自从 (1) 开始编号**的清单——
> 「1. 语汇代码的编写标准」(1)~(8) 和「2. 可综合代码的编写标准」(1)~(11)（后者续到 p.381 的 (12)~(15)）。
> 因此本规范一律写成 `p.380 语汇(N)` / `p.380 可综合(N)`，不要只写 `p.380 (N)`，否则指代不清。
| A5 | 模块头部必须有注释块：功能、时钟域、复位方式、接口协议、CDC 说明 | `[业界]` |

`A3` 的理由：不加它时，打错一个信号名会被 Verilog 默默当成一根新的 1-bit wire，综合后变成一根悬空线，而仿真可能"看起来是对的"。加上它，拼写错误当场变成编译错误。这是投入产出比最高的一条规则。

### B. 命名

| # | 规则 |
|---|------|
| B1 | 时钟一律 `clk`（多时钟域 `clk_axi` / `clk_core`）；复位一律 `rst_n`（低有效）或 `rst`（高有效），**低有效必须带 `_n` 后缀** |
| B2 | 信号名用 `lower_snake_case`，全大写留给 `parameter` / `localparam` / 宏 |
| B3 | 名字要有意义并携带信息；只有循环变量之类的局部量可以简短 `[教材]` p.380 语汇(6) |
| B4 | 大小写风格全项目自始至终一致 `[教材]` p.380 语汇(5) |
| B5 | 不要在代码里直接写魔数（字面量），用 `parameter` / `localparam` `[教材]` p.380 语汇(8) |

推荐（非强制）后缀体系，来自 lowRISC，团队一旦选定就全项目统一：
`_i` 输入 / `_o` 输出 / `_n` 低有效 / `_q` 寄存器输出 / `_d` 寄存器输入 / `_next` 次态 / `_r` 已寄存 / `_s1`,`_s2` 同步器级。

### C. 组合逻辑

| # | 规则 | 出处 |
|---|------|------|
| C1 | 组合 `always` 块内**只用阻塞赋值 `=`**（*刻意*建模电平敏感 latch 时除外，见下） | `[教材]` p.197 原则(3)、p.207 |
| C2 | 敏感表用 `always @(*)`；`[SV]` 用 `always_comb` | `[教材]` p.380 可综合(5) 要求列全所有输入，`@(*)` 是其现代等价写法 |
| C3 | **所有输出在所有路径上都必须被赋值**，否则综合出锁存器 | `[教材]` p.380 可综合(6)、p.57、p.323 |
| C4 | `case` 必须有 `default`；`if` 必须有 `else`（或在块首先赋默认值） | `[教材]` p.57「用 if 最好写上 else 项，用 case 最好写上 default 项」 |
| C5 | 组合块里不能有**组合反馈**：任何变量必须先赋值后使用，禁止在赋值之前读取本块将要写的变量 | `[教材]` p.380 可综合(7)、p.180 |

> C1 的例外：如果你**确实要**建一个电平敏感的透明锁存器，教材 p.197 原则(2) 与 Cummings Guideline #2
> 都要求用**非阻塞赋值 `<=`**。这与"组合逻辑用 `=`"不矛盾——latch 不是组合逻辑。
> 但请记住教材 p.180 的态度：不推荐用 always 块同时描述锁存器和组合逻辑，容易出错。
> 刻意建 latch 时必须在注释里写明理由，并对 lint 的 LATCH 规则做**最小范围**豁免。
>
> C5 的措辞说明：教材 p.380 可综合(7) 的原话更严——"已被定义为输出的寄存器变量绝对不能再在该 always
> 块中读进来作为输入信号"。按字面理解会误伤 `tmp = a & b; y = tmp | c;` 这种**先写后读**的中间临时量，
> 而它恰恰是 IEEE 1364-2005 §9.7.5 给出的标准写法。真正要禁的是**先读后写**（构成组合环路 / 推断锁存器），
> 所以本规范按上表的措辞执行。

**规避锁存器的标准手法**（比逐条补 `else` 可靠得多）——在块首先给所有输出赋默认值：

```verilog
always @(*) begin
    y     = 8'd0;      // 先给默认值
    valid = 1'b0;
    case (sel)
        2'b00: begin y = a; valid = 1'b1; end
        2'b01: begin y = b; valid = 1'b1; end
        default: ;      // 用默认值即可
    endcase
end
```

### D. 时序逻辑

| # | 规则 | 出处 |
|---|------|------|
| D1 | 时序 `always` 块内**只用非阻塞赋值 `<=`** | `[教材]` p.197 原则(1)、p.205 |
| D2 | **同一个 `always` 块里不要混用 `=` 和 `<=`** | `[教材]` p.197 原则(5) |
| D3 | **一个变量只能在一个 `always` 块里被赋值**（教材称"非法"；严格说语法不报错，但它是仿真竞争 + 综合多驱动错误，工具会以 `MULTIDRIVEN` 拦下）。**唯一常见例外**：真双口 RAM 的推断模板要求两个时钟块各写同一个 `mem` 数组——那是厂商规定的写法，需按 `references/09` 处理并对 `MULTIDRIVEN` 做最小范围豁免 | `[教材]` p.197 原则(6)、p.181 13.4「2. 赋值」(1)「一个 reg 的定位赋值只允许在一个 always 块内进行」 |
| D4 | 每个时序 `always` 只由**一个**时钟沿触发。双边沿（DDR）不要在普通 RTL 里手写，改为例化 IDDR/ODDR 或工艺单元 | `[教材]` p.180 13.4 always(4)、p.380 可综合(8) |
| D5 | **可综合 RTL 中**赋值语句不要用延迟 `#`；尤其不要用 `#0`。（testbench **可以**使用时间控制，不受此条约束——但也不是非用 `#` 不可，事件驱动/clocking block/UVM 环境常常完全不用） | `[教材]` p.197 原则(8)、p.381 可综合(13) |
| D6 | 不要用 `integer` / `time` 做**设计信号**（会被综合成 32/64 位总线）。过程 `for` 的循环变量不在此列——它在展开后不产生硬件，`[V2001]` 习惯声明为 `integer`（用 `reg [N:0]` 也合法），`[SV]` 可写 `for (int i = ...)`；`generate for` 用的则是 `genvar` | `[教材]` p.381 可综合(14) |
| D7 | 也要避免**多余的触发器**：在时钟沿 always 块里赋值的变量都会成为寄存器，只是中间量就挪到组合块去 | `[教材]` p.380 可综合(10) |

> 教材 p.197 要点(4) 说"在同一个 always 块中同时描述时序和组合逻辑时，用非阻塞赋值"。
> 本规范的默认做法比它更严：**直接把时序和组合拆成两个块**（教材 p.208 例 14.23 也承认拆块"是可以的"）。
> 这不是对错之争，是取舍——拆开后每个块的意图一目了然，也不会踩 D2。若确实要合写，按教材用 `<=`。

D1~D3 是本规范里最重要的三条。它们的共同理由是 **Verilog 的分层事件队列**：阻塞赋值立刻更新左值，非阻塞赋值要等到当前时间片的非阻塞事件队列才更新。在时序逻辑里用阻塞赋值，多个 `always` 块的执行顺序就会影响结果——而 IEEE 标准并不规定这个顺序，于是**仿真器换一个、甚至同一个仿真器换一次编译，结果就可能变**（竞争冒险）。详见 `references/04-sequential-logic.md`。

### E. 复位与时钟

| # | 规则 | 出处 |
|---|------|------|
| E1 | 时钟和复位必须"干净"：**不得由组合逻辑产生** | `[教材]` p.380 可综合(2) |
| E2 | 异步复位/置位**必须**写进敏感表；同步复位**绝对不要**写进敏感表 | `[教材]` p.189-191 |
| E3 | 所有内部状态寄存器必须可复位（流水线/同步寄存器可例外） | `[教材]` p.380 可综合(11) |
| E4 | 异步复位要**同步释放**（reset synchronizer），见 `assets/templates/v2001/reset_sync.v` | `[业界]` Cummings |
| E5 | `[通用]` 需要分频/降速时一律用**时钟使能**，不要把触发器输出、计数器进位或状态机译码结果当时钟。`[FPGA]` 要真时钟就用 MMCM/PLL + BUFG（分频信号走普通 fabric 布线，偏斜不可控，这条在 FPGA 上比 ASIC 上更硬）；`[ASIC]` 分频时钟必须作为独立时钟源并在 SDC 里声明为 generated clock | `[业界]` UG949「Converting Clock Gating to Clock Enable」/ Quartus SE UG-20175 §1.2.2.2 |
| E6 | 跨时钟域信号**必须**走同步器/异步FIFO/握手，且同步器输入必须来自寄存器输出 | `[业界]` |
| E7 | `[ASIC]` 可测性(DFT)：时钟与复位在测试模式下**必须可控**——经 test mode mux / scan enable / OCC / JTAG 等受控路径即可，**不要求物理外部引脚直连**；不留冗余功能；时序单元原则上进 scan 链（存储器宏、模拟宏、同步器首级、黑盒 IP 等按 DFT 方案豁免）。注意这要求的是"可控"，**不是**"每个触发器都必须有复位"——后者与 E3 的例外和数据通路免复位（见 `14-disputes.md` D02）冲突。具体方案须与 DFT 团队约定 | `[教材]` p.380 可综合(3)、p.381 设计流程(5) |

同一段逻辑，异步与同步复位的差别**只在敏感表**，块内写法完全一样：

```verilog
// 异步复位：rst_n 在敏感表里
always @(posedge clk or negedge rst_n)
    if (!rst_n) q <= 1'b0;
    else        q <= d;

// 同步复位：rst_n 不在敏感表里
always @(posedge clk)
    if (!rst_n) q <= 1'b0;
    else        q <= d;
```

`[FPGA]` Xilinx 建议优先同步复位、数据通路尽量不加复位（省资源、利于打包进 SRL/DSP）。
`[ASIC]` 主流是异步复位+同步释放。**两者都要在模块头注释里写明本模块用的是哪种。**

### F. 状态机

| # | 规则 | 出处 |
|---|------|------|
| F1 | 默认用**三段式**：状态寄存 / 次态组合译码 / 输出寄存 | `[教材]` p.168-173 `[业界]` Cummings |
| F2 | 状态编码用 `localparam`（`[SV]` 用 `enum`），不要用 `` `define `` | `[业界]` |
| F3 | 次态组合块**开头先赋默认值** `next_state = state;` | `[通用]` |
| F4 | `case` 必须有 `default` | `[教材]` p.177 |
| F5 | 状态编码存在非法值时（状态数不是 2 的幂、或用独热码），**非法编码的行为必须有明确策略**——通常就是 `default` 回安全态。教材 p.381 可综合(12) 的原话是"必须明确描述所有 2ⁿ 种状态"，那是针对二进制编码说的；独热码下 2ⁿ 是状态数的指数，逐一列举既不可行也无必要 | `[教材]` p.381 可综合(12) |
| F6 | **绝不要**用综合器设计异步状态机 | `[教材]` p.180 13.3(3)、p.178 |

关于 `default` 赋什么值，教材与业界有分歧（教材 p.177 建议赋 `'bx` 交给综合器优化；安全关键设计要求显式回到 IDLE）。本规范的取舍：**默认显式回安全态**，理由见 `references/14-disputes.md`。

### G. 位宽、运算与可综合性

| # | 规则 |
|---|------|
| G1 | 所有字面量写全位宽和进制：`8'd0` / `4'b1010`，不要裸写 `0`、`1` |
| G2 | `case` 各分支表达式位宽必须相同；禁止用 `'bx` 代替 `n'bx` `[教材]` p.54（原书点名"一个经常犯的错误"） |
| G3 | 赋值两侧位宽必须相等；需要截断/扩展时**显式**写出来 |
| G4 | 有符号运算显式用 `$signed()`；不要混用有符号与无符号。⚠️ `$signed()` **只重新解释符号位，不做位宽扩展**——`$signed(8'h80)` 是 −128 不是 +128。把无符号数转成有符号要先补一位零：`$signed({1'b0, u})` |
| G5 | 禁止 `casex`；`casez` 仅在明确知道自己在做什么时使用 |
| G6 | 禁止 `full_case` / `parallel_case` 综合指示 `[业界]` Cummings |
| G7 | 循环 `for` 的边界必须是常量（会被完全展开）；不要用变量索引做大范围动态选择 `[业界]`。教材 p.381 可综合(15) 的原话是"仔细检查代码中使用动态指针、循环声明或算术运算的部分，这类代码综合后会生成大量的门且很难优化"——只提醒要当心，未直接规定边界必须为常量，此处按现代综合器的实际限制收紧 |

### H. 层次与接口

| # | 规则 |
|---|------|
| H1 | 例化**必须**用命名端口连接 `.clk(clk)`，禁止按位置连接，禁止 `.*` |
| H2 | 把设计切成小的功能块，每块用行为风格描述；除非时序极端吃紧，否则不要写门级 `[教材]` p.380 可综合(1) |
| H3 | 模块间只走寄存器输出（或明确标注的组合输出），避免长组合链跨模块 |
| H4 | 顶层之外不要出现 `inout` / 三态；片内总线用 MUX `[ASIC]` 强制 |

### I. 明确禁止

在**可综合** RTL 中禁止出现：`initial` 块、`#` 延迟、`fork/join`、`wait`、`repeat`/`while`/`forever`、
`force`/`release`、`assign`/`deassign`（过程连续赋值）、实数类型、动态数组/队列/类、
`$display` 等系统任务、UDP、`specify` 块。

两条必须说清的边界，否则这一节会和本规范自己的模板打架：

1. **仿真专用代码是被允许的**，只要它被明确隔离，让综合器看不见：
   包在 `// synthesis translate_off … translate_on` 或 `` `ifndef SYNTHESIS `` 里的
   参数合法性检查、断言、`$display`、波形转储都可以写——`module_skeleton.v` 里的参数检查就是这么做的。
   隔离标记必须写对，否则这些代码会真的进综合。
2. **这是一份"跨工具可移植子集"，不是 IEEE 语言事实**。静态 `repeat`、有可证明上界的 `while`、
   `[FPGA]` 的寄存器初值与 RAM/ROM 初始化，在特定工具上确实可综合。
   本规范禁用它们是为了可移植性和可读性，不是因为语言不允许。要用就必须明确标注目标工具并承担锁定风险。

---

## 2. 提交前必须跑

```bash
python3 scripts/rtl_lint.py --top <顶层模块名> --synth <你的文件>.v
```

它做两件工具能做而人眼做不到的事：`verilator --lint-only -Wall` 查位宽/敏感表/锁存器/未驱动信号；`yosys proc+check` 查真实推断出的锁存器、多驱动和组合环路，并给出门数。**输出必须是 `通过 ✔`。**

> **但"两工具全绿"只是入场券，不是正确性证明。** Verilator 是二态仿真，验证不了 X 传播；
> Yosys 的推断结果也不代表 Vivado / Quartus / Design Compiler / Genus 在 RAM、DSP、时钟、复位上的行为。
> 真正的门禁还需要：目标综合器实跑 + STA + CDC/RDC 检查 + 门级/形式验证 + DFT。
> 本脚本的定位是**把低级错误在提交前挡掉**，不是替代签核流程。

SystemVerilog 加 `--sv`。逐条自检清单见 `references/11-lint-and-review-checklist.md`。

**如果你的项目基线是 Verilog-2001，必须加 `--v2001`**：

```bash
python3 scripts/rtl_lint.py --v2001 --top counter --synth rtl/counter.v
```

理由是一个实测到的陷阱：**Verilator 默认按 SystemVerilog 解析**，所以一个 `.v` 文件里
写满 `always_comb` / `logic` / `enum` 也照样 lint 全绿。不加 `--v2001`（即
`--language 1364-2001`），"Verilog-2001 基线"这件事根本没有被任何工具强制过。
加上它之后，SV 语法会立刻变成 syntax error。

**豁免 lint 规则的唯一正确姿势**：最小范围 + 写明理由。

```verilog
/* verilator lint_off BLKSEQ */
always #(CLK_PERIOD/2) clk = ~clk;   // testbench 时钟发生器，非综合逻辑
/* verilator lint_on BLKSEQ */
```

绝不要在命令行上全局 `-Wno-XXX` 把整类问题关掉。

waiver 多了以后，改用集中的 `.vlt` waiver 文件管理（每条要写清理由和责任人），用 `--waiver` 传入：

```bash
python3 scripts/rtl_lint.py --top top --waiver waivers/project.vlt --synth rtl/*.v
```

两种方式的取舍见 `references/12-toolchain.md` 与 `references/14-disputes.md`。

> 一个实测到的坑：**注释的第一个词如果是 `verilator`，会被当成编译指示**而报 "Unknown verilator comment"。写文档注释时在前面加个字（如 `注：`）避开。

---

## 3. 深入阅读（按需打开，不要一次全读）

| 文件 | 什么时候读 |
|------|-----------|
| `references/01-naming-and-format.md` | 定命名、缩进、注释、文件头模板 |
| `references/02-synthesizable-subset.md` | 拿不准某个语法能不能综合；V2001 与 SV 子集对照 |
| `references/03-combinational-logic.md` | 写组合逻辑；排查意外锁存器 |
| `references/04-sequential-logic.md` | 阻塞/非阻塞的机理、分层事件队列、竞争冒险 |
| `references/05-fsm.md` | 状态机编码、一/二/三段式对比、安全状态机 |
| `references/06-clock-reset-cdc.md` | 复位策略、跨时钟域、亚稳态、异步 FIFO |
| `references/07-datapath-and-width.md` | 位宽、符号扩展、截断、流水线、资源共享 |
| `references/08-hierarchy-and-interface.md` | 模块划分、参数化、握手协议、AXI-Stream |
| `references/09-memory-and-primitives.md` | RAM/ROM/移位寄存器推断，FPGA 与 ASIC 差异 |
| `references/10-testbench.md` | 写 testbench、自检、断言、回归 |
| `references/11-lint-and-review-checklist.md` | 提交前自检、code review 评分表 |
| `references/12-toolchain.md` | Verilator / iverilog / Vivado / Quartus / Yosys 命令 |
| `references/13-xiayuwen-source.md` | 想查某条规则在教材里的原文出处 |
| `references/14-disputes.md` | 业界有分歧的议题，以及本规范为什么这样取舍 |

## 4. 可直接抄的模板

全部经 `verilator --lint-only -Wall` 零告警 + `yosys` 综合验证；testbench 实际运行通过。

| 模板 | 用途 |
|------|------|
| `assets/templates/v2001/module_skeleton.v` | 模块骨架：文件头、参数、valid/ready、参数校验 |
| `assets/templates/v2001/fsm_3seg.v` | 三段式状态机 |
| `assets/templates/v2001/sync_2ff.v` | 单 bit 跨时钟域两级同步器 |
| `assets/templates/v2001/reset_sync.v` | 异步复位、同步释放 |
| `assets/templates/v2001/pulse_sync.v` | 单周期脉冲跨时钟域（toggle 同步器） |
| `assets/templates/v2001/handshake_mcp.v` | 多 bit 跨时钟域 req/ack 握手 |
| `assets/templates/v2001/async_fifo.v` | 格雷码异步 FIFO |
| `assets/templates/v2001/sdp_ram.v` | 简单双口 RAM（可推断 BRAM） |
| `assets/templates/v2001/skid_buffer.v` | ready/valid 全吞吐流水打拍器 |
| `assets/templates/v2001/tb_fsm_3seg.v` | 自检 testbench |
| `assets/templates/sv/fsm_3seg_sv.sv` | 三段式状态机的 SystemVerilog 写法 |

## 5. 给"审查别人代码"的场景

按 `references/11-lint-and-review-checklist.md` 的表逐项打分，并且**先跑 `rtl_lint.py` 再动嘴**——工具能查出来的问题不值得人去争论。

审查时最容易漏、后果最严重的五处，优先看：
1. 组合块有没有路径没赋值（锁存器）
2. 时序块有没有用阻塞赋值 / 同一变量被多块驱动
3. 跨时钟域有没有裸线直连
4. `case` 有没有 `default`，状态机能不能从非法态恢复
5. 位宽有没有隐式截断
