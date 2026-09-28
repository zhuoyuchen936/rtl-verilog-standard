# 08 模块层次与接口设计

> 本篇展开 `SKILL.md` 铁律 **H 节（层次与接口）**，并补上 H 节没有细说的参数化、`generate`、
> package/interface、握手协议与背压。凡与 SKILL.md 冲突之处，一律以 SKILL.md 为准；
> 本文认为主规范需要澄清的地方，集中写在文末「⚠️ 与主规范的冲突 / 待裁决」一节。
>
> 标签：`[教材]`（夏宇闻《Verilog 数字系统设计教程(第4版)》，带书页号） /
> `[业界]`（带文档名与章节） / `[工具]`（Verilator / Vivado Linter 官方文档定义的告警）。
> 适用范围：`[通用]` `[FPGA]` `[ASIC]` `[V2001]` `[SV]`。

---

## 本篇速览

1. **例化只用命名端口连接** `.clk(clk)`；禁止位置连接、禁止 `.*`、禁止 `.name` 隐式连接。
2. **参数覆盖只用 `#(.NAME(v))`**；`defparam` 禁用；`` `define `` 不得用于模块参数化。
   对外可调的用 `parameter`，模块内部推导量一律 `localparam`。
3. **一个模块一个时钟域**（同步器 / 异步 FIFO 是唯一例外）；**跨模块只走寄存器输出**。
4. **valid/ready 三条硬规则**：valid 拉高后未握手不得撤销；valid 期间 data 必须保持；
   **`ready` 不得组合依赖同一端口的 `valid`**（协议允许，本规范禁止，理由见 §7.3）。
5. **ready 是关键路径时插 `skid_buffer.v`**——全寄存、满吞吐、代价是 2 拍延迟 + 2 组数据寄存器。
6. 端口一律 **ANSI 风格**声明，配 `` `default_nettype none ``；**顶层之外不要出现 `inout`**。

---

## 1. 模块划分：切多大、按什么切

### H-1.1 一个文件一个模块，文件名 == 模块名 `[通用]`

`[教材]` p.380 语汇(1)(2)；`[工具]` Verilator `DECLFILENAME`。这是 SKILL.md A1/A2，不重复论证。

注意教材自己的例子（p.22-23 例 2.7）把 `trist1` 与 `mytri` 写在同一段代码里——那是排版紧凑的
教学示例，不是编码规范。教材在 p.380 的规范清单里明确要求一文件一模块，以后者为准。

### H-1.2 层次的分工：上层做结构互连，叶子做行为描述 `[通用]`

`[教材]` p.16（R-B13-06）：「在这个设计树上，**节点对应着该层次上基本单元的行为描述，
树枝对应着基本单元的结构分解**」；p.380 可综合(1)：把设计切成小的功能块，每块用行为风格描述。

落地成两条可检查的规则：

- **顶层与中间层模块里不应出现 `always` 逻辑**，只应有：子模块例化、`assign` 形式的纯连线、
  以及必要的位拼接/切片。中间层一旦开始写 `always`，说明这一层同时承担了"互连"和"计算"
  两个职责，后面拆分、复用、替换网表做门级仿真都会很痛。
- **叶子模块里不写门级原语**。`[教材]` p.380 可综合(1)"除非时序极端吃紧"。门级原语
  （`and`/`or`/`not`）只能按位置连接、且输出必须是第一个端口（`[教材]` p.21，R-B13-15），
  与本规范"一律命名端口连接"的要求天然冲突——这也是不写门级的一个附带理由。

`[教材]` p.16（R-B13-08）还给出层次与"可综合性"的对应关系：高层次的行为级模块只用于仿真、
做系统性能评估和指标分配，**不必综合**；接近底层的模块才需要综合、优化、布线和后仿真。
换句话说，"这个模块要不要守可综合子集"是由它在层次树上的位置决定的，不是由个人偏好决定的。

### H-1.3 一个模块只有一个时钟域 `[通用]`

`[业界]` Cummings, *Synthesis and Scripting Techniques for Designing Multi-Asynchronous Clock
Designs*, SNUG 2001, §6.0：*"Guideline: Only allow one clock per module."*
唯一例外是专门的跨域模块（两级同步器、异步 FIFO、req/ack 握手器），该论文自己列出了这条例外。

**为什么值得为它专门调整模块划分**：

- `set_false_path` / `set_max_delay` 这类跨域约束可以按**模块边界**批量施加，不必逐信号点名；
- CDC 检查工具可以机械地把"模块端口"当成跨域点候选，误报和漏报都会大幅下降；
- OpenTitan 的 CDC 方法学（`[业界]` *Design Methodology within OpenTitan*）是同一思路的工程化：
  维护一份"已验证的跨域子模块清单"→ 强制只能用清单里的模块 → 用工具检查全设计是否合规。

配套：`[业界]` 同论文 §6.0 要求用命名约定标识每个信号的时钟源（SKILL.md B1 的 `clk_axi` /
`clk_core`），这样"某个信号出现在错误的时钟域里"在代码评审时肉眼可见。

### H-1.4 每个状态机独立成模块 `[通用]`

`[业界]` Cummings, *State Machine Coding Styles for Synthesis*, SNUG 1998：
*"make each state machine a separate Verilog module."*
若确实要在一个模块里放多个 FSM，状态名必须加前缀区分（`[业界]` lowRISC *Verilog Coding Style Guide*）。

### H-1.5 模块边界要和后端边界对齐 `[ASIC]`

`[业界]` Synopsys *Power Compiler* datasheet 的推论（见 `_research/web/W04` R-W04-33）：
电源域（power domain）边界应当与模块层次对齐，一个 power domain 尽量对应一个或若干**完整**模块；
隔离使能 / 保持使能 / 电源开关控制作为普通端口引出，且必须来自 always-on 域。
隔离单元、电平移位器、保持寄存器**不要手写进 RTL**，由工具依 UPF 插入。

同理，如果项目要做物理层次划分（partition / block-level P&R），那些 partition 边界上的模块
必须满足 H-3.1（跨模块只走寄存器输出），否则后端无法独立收敛。

### H-1.6 模块粒度：可复用 IP 的门槛 `[通用]`

`[教材]` p.14：功能经过验证的、可综合的、总门数在 **5000 门以上**的模型才称为"软核"。
这个数字今天不必当硬指标，但它传达的判断是有用的——**比这更小的东西不值得当独立 IP 维护**
（接口文档、验证环境、版本管理的固定成本会超过复用收益），应当作为上层模块的内部子模块存在。

---

## 2. 端口声明：ANSI 风格

### H-2.1 一律用 ANSI 风格（V2001 起）`[V2001]` `[SV]`

```verilog
`default_nettype none

module fifo_sync #(
    parameter integer DATA_W = 32,          // 对外可调
    parameter integer DEPTH  = 16
) (
    input  wire                 clk,
    input  wire                 rst_n,
    // 上游（写侧）
    input  wire                 s_valid,
    output wire                 s_ready,
    input  wire [DATA_W-1:0]    s_data,
    // 下游（读侧）
    output reg                  m_valid,
    input  wire                 m_ready,
    output reg  [DATA_W-1:0]    m_data
);
```

反例（**不要抄**，Verilog-1995 非 ANSI 风格）：

```verilog
module fifo_sync (clk, rst_n, s_valid, s_ready, s_data, m_valid, m_ready, m_data);
    parameter DATA_W = 32;
    input  clk, rst_n, s_valid;             // 反例：一行多个声明，且与端口列表分离
    output s_ready;
    input  [DATA_W-1:0] s_data;
    output reg m_valid;
    // ... 端口名在这里出现了两次到三次，改一处漏两处
```

**为什么**：非 ANSI 风格要求同一个端口名分别出现在端口列表、方向声明、类型声明三处。
加端口时漏写方向声明，在 Verilog-1995 语义下不是错误——它会退化成一根隐式 net，
于是"端口存在但永远没被驱动"。`` `default_nettype none ``（SKILL.md A3）能挡住其中一部分，
但根本的修法是让每个端口只写一次。ANSI 风格顺带解决了参数在端口位宽里使用的顺序问题
（`#()` 在端口列表之前展开）。

### H-2.2 端口顺序与类型 `[通用]`

固定顺序，全项目统一：

1. `clk`（多时钟域按域分组，`clk_axi` / `clk_core`）
2. `rst_n`
3. DFT 端口（`[ASIC]`：`scanmode_i` / `scan_rst_ni` 等，`[业界]` OpenTitan `prim_rst_sync.sv`）
4. 上游数据接口（valid / ready / data / last，同一接口的信号必须相邻且用同一前缀）
5. 下游数据接口
6. 配置输入 / 状态输出 / 中断

类型：

- `[V2001]` **输入一律 `input wire`**；输出若在 `always` 块内被赋值写 `output reg`，
  否则写 `output wire`。
- `[SV]` 统一用 `logic`。但要知道一个坑：`[业界]` Mills, *Yet Another Latch and Gotchas Paper*,
  SNUG 2012 §6.0 指出，SV-2009 起 `logic` 是 value set 而非 type，`input logic` 被推断为
  `input wire logic`（net，可多驱动），要变量语义必须写 `input var logic`。
  本规范的取舍：**输入端口不依赖 `logic` 的单驱动性做防御**，多驱动交给 lint 查
  （`[工具]` Verilator `MULTIDRIVEN`）。
- 每行只声明一个端口（`[教材]` p.380 语汇(3)(4)）。

### H-2.3 顶层之外不要出现 `inout` / 三态 `[ASIC]` 强制 / `[FPGA]` 强制

这是 SKILL.md H4。两侧理由不同，都要知道：

- `[ASIC]`：`[业界]` Cummings/Mills/Golson SNUG 2003 §4.3——内部三态总线在上电、复位释放、
  以及任何"多驱动器同时使能"的窗口里会发生总线竞争，瞬时短路电流可能损伤器件；
  而且**用了内部三态就被迫接受异步上电复位**（否则必须用复位直接关断三态使能）。改用 MUX 后
  这个约束整个消失。
- `[FPGA]`：`[业界]` Quartus Prime SE UG-20175 §2.6.1——现代 FPGA 内部**没有**三态资源
  （早期 Virtex 的 TBUF 已被移除），三态一律落在 I/O 上（AMD 侧实现为 `OBUFT`）。
  Intel 还给出一条层次相关的硬限制：**块级设计流程中，层次边界不能含双向端口**，
  除非该低层双向端口直接穿透到顶层输出引脚且不接任何其它逻辑——因为综合器必须把三态
  "推"到顶层才能用上 I/O 的三态驱动器，这需要跨层次优化。

`[教材]` p.22-23 例 2.6/2.7 与 `_research/book/G05` 的实验十（`inout [7:0] databus` 出现在
`sys` 这个中间层模块上）都在子模块层面用了三态，那是教学演示总线共享概念。**本规范按业界取舍，
不采纳该写法**：片内共享总线一律用 MUX 或"或树 + 单热使能"实现。

标准的顶层三态写法（唯一允许出现 `inout` 的地方）：

```verilog
// 顶层：inout 拆成三根内部信号，内部逻辑只见单向信号
inout  wire [7:0] pad_data;
wire   [7:0]      pad_data_i;   // 输入方向
wire   [7:0]      pad_data_o;   // 输出方向
wire              pad_data_oe;  // 输出使能，高有效

assign pad_data   = pad_data_oe ? pad_data_o : 8'bzzzz_zzzz;
assign pad_data_i = pad_data;
```

---

## 3. 例化与端口连接

### H-3.1 必须用命名端口连接 `[通用]`（SKILL.md H1）

`[教材]` p.23：「带"."表示被引用模块的端口，**名称必须与被引用模块 mytri 的端口定义一致**，
小括号中表示在本模块中与之连接的线路。」p.24 再次强调："."后面紧跟端口名，**其名称必须与
模块定义的端口名一致**；小括号内的信号名可以用别的名，但**必须在本模块中定义，说明其类型**。
`_research/book/G05` 的实验十（p.342、p.343）里全部实例调用都是这个写法。

```verilog
// 正例：一行一个端口，clk/rst 在最前，同一接口的信号相邻
skid_buffer #(
    .WIDTH   (DATA_W)
) u_skid_in (
    .clk     (clk),
    .rst_n   (rst_n),
    .s_valid (up_valid),
    .s_ready (up_ready),
    .s_data  (up_data),
    .m_valid (core_valid),
    .m_ready (core_ready),
    .m_data  (core_data)
);
```

```verilog
// 反例，不要抄：位置连接
skid_buffer u_skid_in (clk, rst_n, up_valid, up_ready, up_data,
                       core_valid, core_ready, core_data);
// 子模块端口顺序一改，这里静默错连，编译和 lint 都不会报错。
```

**唯一例外**：门级原语（`and` / `or` / `not` / `bufif1` …）由语言规定接口顺序，只能按位置连接，
且输出必须是第一个端口（`[教材]` p.21 R-B13-15）。本规范默认不写门级，所以实践中这条例外用不上。

### H-3.2 禁止 `.*` 与 `.name` 隐式连接 `[通用]`

`.*` 与 `.name`（SV 的隐式命名连接）都靠"名字相同即连上"工作。禁止的理由：

- 连接关系不再写在代码里，评审时无法在例化点看出这个实例到底接了什么；
- 改名字就等于改连线。把上层的 `data` 改成 `data_q`，`.* ` 会从"连上"变成"端口悬空"或编译错误，
  错误信息指向的是端口而不是那次改名；
- 与 `` `default_nettype none `` 配合时行为更绕：隐式连接不会替你声明 net。

### H-3.3 端口连接位宽必须严格匹配 `[通用]`

`[业界]` lowRISC *Verilog Coding Style Guide* §Signal Widths：*"Port connections on module
instances must always match widths correctly."*
`[工具]` Verilator `WIDTH`：*"Two operands have different widths, or a part select has a
different size than needed."*

**为什么这条在层次边界上格外要紧**：位宽不匹配的端口连接会被工具**静默**截断或补零，
不是错误。一个 12-bit 的计数器接到 8-bit 的端口上，仿真和综合都会照做，
bug 表现为"计数到 256 就回绕"，离根因很远。需要截断/扩展时显式写出来：

```verilog
// 正例：显式截断，意图写在代码里
.addr_o  (addr_full[ADDR_W-1:0]),
// 正例：显式零扩展
.data_i  ({{(DATA_W-8){1'b0}}, byte_in}),
```

### H-3.4 所有端口都要显式列出；不用的输出也要有名字 `[通用]`

`[工具]` Vivado RTL Linter `ASSIGN-12`「例化模块存在未连接引脚」（`[业界]` UG901 v2025.1
Ch.2 List of Linter Rules, p.19-20）会报告未连接引脚。本规范要求：

- **输入端口不得悬空**。没用到也要接常量，并写清为什么：`.test_en_i (1'b0),  // 无 DFT 需求`。
- **输出端口即使不用也要连到一个命名 wire**（`wire unused_ovf;`），再集中做一次
  "已知不用"的声明，而不是留空。理由：留空的输出在综合时会被优化掉，
  于是"这个功能到底实现了没有"从网表上看不出来；连到命名 wire 后，
  lint 的 unused 告警会明确指向那一个信号，评审时一眼能确认是有意为之。

实例名统一 `u_<功能>`；同一模块多次例化用 `u_<功能>_<序号或用途>`，不要用 `u1`/`u2`。
理由：实例名会进入网表、时序报告、SDC 路径、波形和 DFT 脚本，是后端唯一能引用你这块逻辑的名字。

---

## 4. 参数化

### H-4.1 `parameter` 对外，`localparam` 对内 `[V2001]` `[SV]`

```verilog
module ram_wrap #(
    parameter integer DATA_W = 32,          // 对外可调
    parameter integer DEPTH  = 1024         // 对外可调
) (
    input  wire                      clk,
    input  wire [ADDR_W-1:0]         addr,  // 见下：ADDR_W 由 DEPTH 推导
    ...
);
    // 内部推导量一律 localparam：不允许上层用 #() 改掉它，
    // 否则 ADDR_W 与 DEPTH 可能不一致，地址高位静默失效。
    localparam integer ADDR_W = clogb2(DEPTH - 1);
```

**为什么必须区分**：`parameter` 在 Verilog-2001 里可以被上层例化时覆盖。如果把
"由别的参数算出来的量"也写成 `parameter`，上层就有能力只改其中一个，破坏内部不变式，
而且这种破坏没有任何工具会报——两个参数各自都是合法值。
`localparam` 从语言层面禁止覆盖，把不变式变成编译期保证。

> ⚠️ ANSI 端口列表里若要用 `localparam` 计算端口位宽，Verilog-2001 不允许在 `#()` 之外、
> 端口列表之前声明 `localparam`。可移植的做法有两种：
> (a) 端口位宽直接写成参数表达式 `input wire [clogb2(DEPTH-1)-1:0] addr`（需要常量函数，见 H-4.5）；
> (b) 把推导量声明成带"不要覆盖我"注释的 `parameter`，并在模块内用 `localparam` 复核一次。
> 本规范默认 (a)。`[SV]` 允许在参数列表里写 `localparam`，直接用。

### H-4.2 例化时只用命名参数覆盖 `#(.NAME(value))` `[通用]`

```verilog
// 正例
async_fifo #(
    .WIDTH (32),
    .DEPTH (16)
) u_fifo (...);
```

```verilog
// 反例，不要抄：按位置覆盖参数
async_fifo #(32, 16) u_fifo (...);
// 子模块加一个参数、或调整参数顺序，这里就静默错配。
```

### H-4.3 `defparam` 禁用 `[通用]`

```verilog
// 反例，不要抄
async_fifo u_fifo (...);
defparam u_fifo.WIDTH = 32;              // 禁止
defparam top.u_core.u_fifo.DEPTH = 16;   // 更禁止：跨层次遥控
```

禁用理由（机理）：

1. **参数值不在例化点**。`defparam` 可以写在文件里的任何地方，甚至另一个模块、另一个文件里，
   通过层次名遥控某个实例。读例化那一行代码，你看不到它实际用的是什么参数。
2. **多个 `defparam` 指向同一参数时结果依赖工具的处理顺序**。语言层面这属于"值最终由谁决定"
   没有唯一确定答案的情形，不同工具、不同编译顺序可能给出不同的值——这正是
   "仿真通过、综合出来是另一回事"的典型来源。
3. **强迫工具做多轮 elaboration**。参数决定位宽，位宽决定端口，而 `defparam` 可能出现在
   已经 elaborate 过的层次上，工具必须回头重算。综合器对此的支持历来参差。
4. `#(.NAME(v))` 能表达 `defparam` 的一切**合理**用途，且把参数值放在了它该在的地方。

> 出处说明：IEEE 1364-2005 / IEEE 1800 将 `defparam` 列入 deprecated 构造，
> 但 **本轮调研未取到标准原文**，上述条目按机理论证给出，标注为 `[待补证]`。
> 无论标准状态如何，本规范禁用它的工程理由（1)(2) 独立成立。

### H-4.4 不要用 `` `define `` 做模块参数化 `[通用]`

`[业界]` lowRISC *Verilog Coding Style Guide* 禁止用 `` `define `` 参数化模块
（见 `_research/web/W04` D7 对照表）。

**为什么**：宏是**编译单元全局**的、没有作用域、没有类型。两个模块各自 `` `define WIDTH ``，
谁先被编译谁说了算，而且 `` `define `` 会一直生效到被 `` `undef `` 或编译结束——
它跨越模块边界污染其它文件。参数是模块的属性，宏是文件流的属性，两者根本不是一回事。

同样的理由，状态编码用 `localparam` 而不是 `` `define ``（SKILL.md F2）。

跨模块共享的常量：`[SV]` 放进 package（见 §6.1）；`[V2001]` 放进一个只含
`localparam` 的 `.vh` 头文件，并在每个使用它的模块里 `` `include ``——注意这仍是宏机制的变体，
要靠命名前缀（`FIFO_DEPTH_MAX` 而不是 `DEPTH_MAX`）避免碰撞。

### H-4.5 由参数推导位宽：常量函数 `[V2001]` `[SV]`

`[教材]` p.89（6.2.6 常量函数，例 6.15）给出了标准手法——用一个带限制的常规函数
在 elaboration 期算出常量，代替写死的数字：

```verilog
// 由深度算地址位宽。教材 p.89 例 6.15 的可编译版本。
function integer clogb2;
    input integer depth;
    begin
        for (clogb2 = 0; depth > 0; clogb2 = clogb2 + 1)
            depth = depth >> 1;
    end
endfunction
```

用法：`localparam integer ADDR_W = clogb2(DEPTH - 1);`
（注意教材原文 p.89 的调用写的是 `clog2(RAM_DEPTH)`，而函数定义名为 `clogb2`，
且未减 1——扫描件中的名字与边界处理不一致，此处按可编译、可用的形式给出。）

`[SV]` 可以直接用 `$clog2()`，不必自己写。

### H-4.6 参数合法性检查 `[通用]`

参数是模块与外界的契约。契约被违反时应当**在 elaboration 就失败**，而不是综合出一个
位宽为 0 或负数的怪物。已验证模板 `assets/templates/v2001/module_skeleton.v` 的做法：

```verilog
// 参数合法性检查：包在 translate_off 里，不进入可综合 RTL
// synthesis translate_off
initial begin
    if (DATA_W <= 0) begin
        $display("ERROR: %m: DATA_W must be positive, got %0d", DATA_W);
        $finish;
    end
end
// synthesis translate_on
```

三点说明：

1. `%m` 会输出**层次路径名**（`[教材]` p.96，R-B11-37：「当一个模块的多个实例执行同一段
   Verilog 代码时，`%m` 选项会区分哪个模块实例在输出」）。参数化模块往往被例化很多次，
   没有 `%m` 你不知道是哪个实例的参数错了。
2. `$error` / `$fatal` / `assert` 是 SystemVerilog。纯 `[V2001]` 用 `$display` + `$finish`，
   可移植性最好。
3. `[业界]` Cummings/Mills/Golson SNUG 2003 §5.2 与 Mills SNUG 2012 §5.0 的共同底线：
   `translate_off` / `` `ifndef SYNTHESIS `` **只允许**包裹仿真专用补丁、断言、覆盖率代码，
   **严禁**用它让综合器和仿真器看到不同的功能逻辑。参数检查属于允许的用法。
   `[SV]` 项目更推荐 `` `ifndef SYNTHESIS ``（工具无关，不依赖注释解析）。

命名：`parameter` / `localparam` 一律全大写（SKILL.md B2）。
> 分歧如实记录：`[业界]` lowRISC 用 `UpperCamelCase`（`parameter int unsigned Width = 8`），
> 目的是在 SV 里把参数与宏、与 `typedef` 出的类型名区分开。本规范**服从 SKILL.md B2 用全大写**，
> 这一点见文末待裁决第 1 条。

---

## 5. `generate`

### H-5.1 `generate` 的适用边界 `[V2001]` `[SV]`

`generate` 解决的是**结构在 elaboration 期由参数决定**的问题，和运行时的 `if` 是两件事：

| 问题 | 用什么 | 结果 |
|---|---|---|
| 位宽/级数/实例个数由 `parameter` 决定 | `generate for` + `genvar` | 展开成 N 份硬件 |
| 某个功能块要不要存在，由 `parameter` 决定 | `generate if` | 不存在的分支**不产生任何硬件** |
| 行为由运行时信号决定 | 普通 `if` / `case` | 产生 MUX |

把"参数决定"的事写成普通 `if`，功能上综合器会靠常量传播优化掉，但代价是：
被优化掉的那半边逻辑仍要通过 lint（可能触发一堆 unused / width 告警），
且读代码的人无法区分"这是配置项"还是"这是运行时判断"。反过来把运行时的事写成 `generate if`
会直接编译报错（条件必须是常量表达式）——这一侧不会出事，所以真正的风险只在前一个方向。

### H-5.2 `generate` 块必须命名 `[通用]`

```verilog
// 正例：三处 label 都写了
genvar i;
generate
    for (i = 0; i < LANES; i = i + 1) begin : gen_lane
        lane_core #(
            .DATA_W (DATA_W)
        ) u_lane (
            .clk     (clk),
            .rst_n   (rst_n),
            .s_valid (lane_valid[i]),
            .s_ready (lane_ready[i]),
            .s_data  (lane_data[(i+1)*DATA_W-1 -: DATA_W]),
            .m_valid (out_valid[i]),
            .m_ready (out_ready[i]),
            .m_data  (out_data[(i+1)*DATA_W-1 -: DATA_W])
        );
    end
endgenerate

generate
    if (HAS_ECC != 0) begin : gen_ecc
        ecc_check u_ecc (.clk(clk), .rst_n(rst_n), .data_i(m_data), .err_o(ecc_err));
    end else begin : gen_no_ecc
        assign ecc_err = 1'b0;              // else 分支也要写，否则 ecc_err 无驱动
    end
endgenerate
```

```verilog
// 反例，不要抄：未命名的 generate 块
generate
    for (i = 0; i < LANES; i = i + 1) begin       // 没有 : gen_lane
        lane_core u_lane (...);
    end
endgenerate
```

**为什么必须命名**：generate 块的 label 会成为**层次路径的一级**。
未命名时工具自动生成名字（典型是 `genblk1`、`genblk2`…），而这个自动名字的规则
**不同工具不一定一致，且会随你在文件里增删一个 generate 块而整体平移**。
一旦平移，所有引用了层次路径的东西全部失效：SDC 里的 `get_cells`、
false path、`ASYNC_REG` / `dont_touch` 之类的实例属性、DFT 脚本、波形配置、
覆盖率排除列表。命名之后路径变成 `u_top/gen_lane[3].u_lane/...`，稳定且可读。

`else` 分支即使"什么都不做"也要写出来并命名——上例中若省掉 `gen_no_ecc`，
`ecc_err` 在 `HAS_ECC == 0` 时就没有驱动源了。

### H-5.3 `generate for` 的循环边界必须是常量 `[通用]`

SKILL.md G7。`genvar` 循环在 elaboration 期被**完全展开**，边界必须是编译期常量。
教材 p.381 可综合(15) 的原话是提醒："仔细检查代码中使用动态指针、循环声明或算术运算的部分，
这类代码综合后会生成大量的门且很难优化"——它只提醒当心，本规范按现代综合器的实际限制收紧为硬规则。

一个具体后果：`for (i = 0; i < LANES; i = i + 1)` 里 `LANES = 64` 就是 64 份硬件，
不是一个循环了 64 次的电路。写 `generate` 之前先在心里乘一遍面积。

---

## 6. valid / ready 握手协议

模块之间传数据，**默认一律用 valid/ready 握手**，不要自定义"我发你必须收"的隐式时序约定。
理由很实际：握手把"能不能收"这件事显式化，下游加一级流水、上游变慢，双方都不用改代码。

### H-6.1 握手的三条规则 `[通用]` `[业界]` AXI

1. **传输发生在 `valid && ready` 同时为高的那个时钟沿。**
2. **`valid` 一旦拉高，在 `ready` 到来之前不得撤销，且 `data` 必须保持不变。**
   这条是给上游的义务——下游可能正忙，撤销会造成数据丢失。
3. **`ready` 可以随意变化，不得依赖 `valid`。**
   这条是给下游的义务：`ready` 不能等看到 `valid` 才拉高，否则两边互相等待就是死锁。

```verilog
// 正例：合法的握手判定
wire fire = m_valid & m_ready;   // 本拍成功传了一个数据

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)     cnt <= 16'd0;
    else if (fire)  cnt <= cnt + 16'd1;
end
```

```verilog
// 反例，不要抄：ready 依赖 valid，与上游的 valid 依赖 ready 撞在一起就死锁
assign s_ready = s_valid & downstream_ok;
```

### H-6.2 组合直通会拖出长路径，要用 skid buffer 打断 `[通用]`

把 `ready` 从下游一路组合传回上游，链一长 `ready` 就成了关键路径。
要打断它就得把 `ready` 也寄存，但 `ready` 一寄存，上游在看到它拉低之前还会再送一拍进来——
这一拍必须有地方接住。这就是 skid buffer 存在的理由。

见 `assets/templates/v2001/skid_buffer.v`（已验证）：输出 `m_valid`/`m_data` 和 `s_ready`
全部是寄存器输出，上下游之间没有组合直通，可以随便级联，且**保持满吞吐**
（不像简单打拍会掉一半带宽）。代价是 2 拍延迟、2 组数据寄存器。

### H-6.3 不要用 `full` / `empty` 之类的裸标志跨模块 `[通用]`

`fifo_full` 这种信号的含义依赖内部实现（是"现在满"还是"下一拍满"？），
跨模块用极易错一拍。对外一律换算成 `ready`。

### H-6.4 AXI-Stream 约定 `[通用]`

需要与外部 IP 对接时，直接用 AXI-Stream 的信号命名，不要自造：

| 信号 | 含义 |
|---|---|
| `tvalid` / `tready` | 握手，规则同 H-6.1 |
| `tdata` | 数据 |
| `tlast` | 本拍是一个 packet 的最后一拍 |
| `tkeep` / `tstrb` | 字节有效标志 |
| `tuser` | 边带信息 |

**`tlast` 的常见错误**：在 `tvalid && !tready` 期间改变 `tlast`。它和 `tdata` 一样受规则 2 约束。

### H-6.5 跨时钟域的接口不能只靠握手信号 `[通用]`

valid/ready 是**同一时钟域内**的协议。跨时钟域时，这两根线本身就是需要同步的信号，
必须换成 `06-clock-reset-cdc.md` 里的异步 FIFO 或 MCP 握手，
不能把 valid/ready 直接拉过时钟域边界。

---

## 7. 本篇检查清单

- [ ] 一个文件一个模块，文件名 == 模块名
- [ ] 每个模块只有一个时钟域；跨域的部分单独成模块并标注
- [ ] 端口用 ANSI 风格声明，时钟复位排最前，一行一个
- [ ] 顶层之外没有 `inout` / 三态，片内总线用 MUX
- [ ] 例化全部用命名端口连接，没有按位置连接，没有 `.*`
- [ ] 端口连接位宽严格匹配（`verilator -Wall` 无 `WIDTH` 类告警）
- [ ] 不用的输出也显式列出并命名
- [ ] 对外可配的用 `parameter`，内部推导量用 `localparam`；没有 `defparam`
- [ ] 参数有合法性检查（elaboration 期报错）
- [ ] `generate` 块都命名了，循环边界是常量，面积已估算
- [ ] 模块间接口默认 valid/ready 握手，且遵守三条规则
- [ ] `valid` 拉高后到 `ready` 之前，`data` / `tlast` 保持不变
- [ ] `ready` 不依赖 `valid`（无组合死锁）
- [ ] 长握手链上插了 skid buffer，模块间无组合直通路径
- [ ] 跨时钟域接口用的是异步 FIFO / MCP 握手，不是裸 valid/ready

---
