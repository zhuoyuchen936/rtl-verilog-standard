# 06 · 时钟、复位与跨时钟域

这一篇管的是**整个芯片里最容易出现"仿真全过、上板偶发挂死"的那类问题**。
组合逻辑写错了，仿真通常当场就露馅；时钟和 CDC 写错了，它可能跑一万次才错一次，
而且错在客户手里。所以这里的规则比别处更硬。

教材对这部分覆盖较弱（第 11 章只讲到"数据接口的同步方法"的概念层面），
本篇主要依据业界一手资料，并配有本 skill 中**已通过 lint 与综合验证**的模板。

---

## 本篇速览

1. **时钟只能来自时钟源**，不能由组合逻辑、也不能由普通触发器的输出产生。要分频就用**时钟使能**。
2. **只要用异步复位，就必须同步释放**——这是本篇唯一没有任何分歧的一条。
3. **单 bit 电平**跨域打两拍；**多 bit 绝对不能各自打两拍**，必须走格雷码 / 握手 / 异步 FIFO。
4. 同步器的**输入必须是寄存器输出**，不能是组合逻辑输出（组合毛刺会被采成真实脉冲）。
5. FPGA 与 ASIC 在复位策略上**方向相反**，见 `14-disputes.md` D01/D02。

---

## 一、时钟

### R-06-01 时钟不得由组合逻辑产生 `[通用]` `[教材]` p.380 可综合(2) `[业界]`

教材原话要求"保证 Verilog 源代码中的时钟和复位信号是干净的（即不是由组合逻辑或没有考虑到的门产生的）"。

**为什么**：组合逻辑有毛刺。一个毛刺送到触发器的时钟端，就是一次意料之外的翻转，
而且这种错误在 RTL 仿真里**看不出来**（RTL 仿真没有延时，不产生毛刺），
只有带延时的门级仿真或真实硅片上才会暴露。此外，组合产生的时钟无法被 STA 正确分析，
也无法被 DFT 的 scan 链控制。

```verilog
// 反例，不要抄
wire gated_clk = clk & enable;          // 组合门控时钟：毛刺 + STA 无法分析
always @(posedge gated_clk) q <= d;

// 正例：改用时钟使能，让综合器决定是否插入 ICG
always @(posedge clk) begin
    if (enable) q <= d;
end
```

### R-06-02 分频不要用触发器输出直接当时钟 `[通用]`

```verilog
// 反例，不要抄：clk_div2 是一个由逻辑产生的时钟，跨了时钟域还没人知道
reg clk_div2;
always @(posedge clk) clk_div2 <= ~clk_div2;
always @(posedge clk_div2) ...          // 新时钟域，需要 CDC 处理

// 正例：单一时钟 + 使能脉冲，全设计仍然只有一个时钟域
reg tick;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) tick <= 1'b0;
    else        tick <= ~tick;
end
always @(posedge clk) begin
    if (tick) ...                        // 半速逻辑
end
```

**为什么**：每多一个时钟就多一个时钟域、多一组 CDC 风险、多一份约束。
用使能则整个设计仍是单时钟域，STA 一把过。

`[FPGA]` 若确实需要真时钟，用 MMCM/PLL 和全局时钟缓冲（BUFG），不要用逻辑分频。
`[ASIC]` 时钟树由后端综合，RTL 侧只写使能。

### R-06-03 时钟门控交给工具，不要在 RTL 里手写 `[ASIC]`

写 `if (en) q <= d;`，综合器（Power Compiler 等）会自动把它变成 ICG 单元。
手写 `assign gclk = clk & en;` 既有毛刺风险，又绕过了工具的门控合并优化。

> `[FPGA]` 上方向相反：Vivado 会把门控时钟**转成**时钟使能（UG949 有专门一节
> "Converting Clock Gating to Clock Enable"），因为 FPGA 的触发器本来就有 CE 端。
> 同一段 RTL 在两条流程里被反向变换，所以**统一写 `if (en)` 对两边都最优**。

---

## 二、复位

### R-06-04 只要用异步复位，就必须同步释放 `[通用]` `[业界]`

这是本篇唯一**没有分歧**的一条。异步复位有两个独立的时刻：

- **断言（assert）**：异步生效，不依赖时钟——这正是我们要的，上电、时钟还没起振时也能复位。
- **释放（deassert）**：如果也异步，就有两个问题：
  1. 释放沿若落在时钟有效沿的 **recovery/removal 窗口**内，触发器可能进入亚稳态；
  2. 复位树上各触发器的延时不同，**退出复位的时刻不一致**，状态机可能落进非法状态组合。

解法就是让复位的到来保持异步、而释放被同步到本时钟域：

```verilog
// 见 assets/templates/v2001/reset_sync.v（已通过 lint + 综合验证）
always @(posedge clk or negedge arst_n) begin
    if (!arst_n) rst_pipe <= 2'b00;      // 异步断言：立刻清零
    else         rst_pipe <= {rst_pipe[0], 1'b1};   // 同步释放：走满两拍
end
assign rst_n_sync = rst_pipe[1];
```

**每个时钟域各实例化一个**，把它的输出作为该域所有触发器的复位。

### R-06-05 异步复位写进敏感表，同步复位绝不写进敏感表 `[通用]` `[教材]` p.189-191

两者块内写法完全一样，**差别只在敏感表**：

```verilog
always @(posedge clk or negedge rst_n)   // 异步
    if (!rst_n) q <= 1'b0; else q <= d;

always @(posedge clk)                    // 同步
    if (!rst_n) q <= 1'b0; else q <= d;
```

教材 p.191 对同步复位特别强调过：**绝对不要**把 set/reset 写进事件控制表。
写进去就变成了异步复位，与设计意图不符，而且综合出来的电路和你想的不是一个。

### R-06-06 复位低有效并统一命名 `rst_n` `[通用]`

低有效是标准单元库的惯例（异步清零端通常是低有效），也是 lowRISC/OpenTitan 的选择。
模块接口一律 `rst_n`；若外部给的是高有效，在**边界转一次极性**，不要让两种极性在内部混行。

### R-06-07 哪些寄存器可以不复位 `[FPGA]` `[ASIC]` 分歧显著

这是本规范里 FPGA 与 ASIC 分歧最大的一条，详见 `14-disputes.md` D02。简述：

| | 立场 | 理由 |
|---|---|---|
| `[FPGA]` AMD/Xilinx | 数据通路**尽量不加**复位 | 配置比特流已把触发器初始化好；加了复位会妨碍打包进 SRL/DSP/BRAM，浪费资源 |
| `[ASIC]` lowRISC/OpenTitan | 倾向全复位 | ASIC 上电状态随机，且门级仿真与形式验证需要确定初态 |

**本规范的默认**：**控制路径（状态机、计数器、握手信号、有效位）必须复位；
纯数据路径（流水线上的数据寄存器）可以不复位**，前提是：
① 它的有效位（valid）有复位；② 不复位不会造成 X 传播到控制逻辑；③ 在模块头注释里写明。

### R-06-08 存储器阵列绝不复位 `[通用]`

片上 RAM 的存储阵列没有复位端。给 `mem` 写复位分支会让综合器放弃 RAM、
改用触发器实现，资源瞬间爆炸。只有 RAM 的**输出寄存器**可以复位，且应当是同步复位。
详见 `09-memory-and-primitives.md`。

---

## 三、跨时钟域（CDC）

### R-06-09 同步器的输入必须来自寄存器输出 `[通用]`

如果 `d_async` 是组合逻辑的输出，它上面的毛刺会被目的域采样成一个**真实存在**的脉冲。
源域必须先打一拍再送出去。

### R-06-10 单 bit 电平信号：两级同步器 `[通用]`

```verilog
// 见 assets/templates/v2001/sync_2ff.v
(* ASYNC_REG = "TRUE" *) reg [1:0] sync_q;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) sync_q <= 2'b00;
    else        sync_q <= {sync_q[0], d_async};
end
assign q_sync = sync_q[1];
```

**为什么是两级**：第一级采到亚稳态时，第二级给它一整个时钟周期去解析，
把 MTBF 推到工程可接受的量级（通常是"宇宙年龄"级别）。极高频或高可靠场景用三级。

`[FPGA]` `ASYNC_REG="TRUE"` 让 Vivado 把两级触发器摆进同一个 slice、禁止优化与复制，
并告知时序引擎这条路径不必满足 setup。
`[ASIC]` 用库里的同步器单元，或加 `set_false_path` + `dont_touch`。

### R-06-11 单周期脉冲跨域：toggle 同步器，不要用 R-06-10 `[通用]`

两级同步器同步的是**电平**。源域一个只持续 1 拍的脉冲，若目的域时钟更慢，会被整个错过。

做法：源域把脉冲变成电平翻转，目的域同步后做边沿检测还原。
见 `assets/templates/v2001/pulse_sync.v`。

**限制**：两次输入脉冲之间必须至少间隔目的域 2~3 个周期，否则仍会丢。
密集脉冲请用握手或异步 FIFO。

### R-06-12 多 bit 数据**绝不能**各自打两拍 `[通用]` ★最容易犯的致命错误★

多个 bit 的物理路径延时不同，各自的亚稳态收敛方向也彼此独立。
当总线从 `0111` 变到 `1000`（4 个 bit 同时翻转），目的域可能采到 `1111`、`0000`
或任何中间组合——一个**从未存在过**的值。

三种正确方案，按场景选：

| 方案 | 适用 | 模板 |
|---|---|---|
| **格雷码** | 每次只变化 1（计数器、FIFO 指针） | `async_fifo.v` 里的指针 |
| **MCP 握手** | 更新不频繁（配置寄存器、状态快照） | `handshake_mcp.v` |
| **异步 FIFO** | 连续高吞吐数据流 | `async_fifo.v` |

Gray 编码只在相邻源更新中变化一位；源端需寄存且逐步递增。仍须约束到接收域
第一级同步器的路径延迟和总线 skew，避免不同次更新在物理路径上交叠。
接收域可以跳过中间计数；同步器仅降低亚稳态传播概率，不提供绝对保证。

### R-06-13 MCP、Gray 总线和约束优先级

`handshake_mcp.v` 从 `data_q` 到 `dst_data` 的数据在 req/ack 往返期间保持。
最大数据延迟应从控制同步链的最早捕获时刻、两个时钟的关系和实现裕量推导，
不能机械套用源时钟周期。它是异步 bundled-data 传输，不应直接套用同步 multicycle 例外。

Vivado 中 `set_clock_groups` 和同路径的 `set_false_path` 会覆盖 `set_max_delay`。
若同一时钟对有 MCP/Gray 数据路径需要最大延迟约束，不要整域切断，再试图用 max delay 补回。
对其他允许放弃 setup/hold 分析的跨域路径施加局部例外；保留同步链后续级的同域时序分析。

示意（`cdc_budget_ns` 由具体握手时序推导；对象名以综合网表为准）：

```tcl
set src_regs [get_cells -hier -filter {NAME =~ */u_handshake/data_q_reg*}]
set dst_regs [get_cells -hier -filter {NAME =~ */u_handshake/dst_data_reg*}]
if {[llength $src_regs] == 0 || [llength $dst_regs] == 0} {
    error "CDC endpoints did not match the synthesized design"
}
set_max_delay -datapath_only $cdc_budget_ns -from $src_regs -to $dst_regs
report_timing -from $src_regs -to $dst_regs
report_exceptions -ignored
```

Gray 指针的 skew 预算应按源更新间隔和接收采样要求确定；Vivado 可用 `set_bus_skew`
并配最大数据延迟。`set_bus_skew` 独立于路径时序例外，不能据此认为 max delay 也未被覆盖。
只在没有这类有界延迟需求、且已验证 CDC 结构的时钟对上使用整域异步分组。

参考：[AMD UG903 异步约束](https://docs.amd.com/r/en-US/ug903-vivado-using-constraints/Constraining-Asynchronous-Signals)、
[UG903 Gray 总线实例](https://docs.amd.com/r/en-US/ug903-vivado-using-constraints/set_bus_skew-Example-Two)、
[UG835 set_bus_skew](https://docs.amd.com/r/en-US/ug835-vivado-tcl-commands/set_bus_skew)。核对日期：2026-09-28。

### R-06-13b 模板复位契约与约束范围

`pulse_sync`、`handshake_mcp`、`async_fifo` 均要求两域协调复位，丢弃在途数据/事件，
各自同步释放，恢复前禁止新事务。单侧复位可能造成伪脉冲、丢失请求、FIFO 指针不一致或死锁。
若系统要求任意单侧复位，需增加重同步/初始化握手协议，并验证 RDC 和复位中的事务行为。

本篇只覆盖与 CDC 直接相关的约束。基本时钟、generated clock、IO delay 和完整时序例外
应采用项目 XDC/SDC；不得把示例当成能直接签核的约束文件。

### R-06-14 异步 FIFO 的满空判断必须"保守" `[通用]`

见 `async_fifo.v`。要点：读写指针都比地址多 1 bit（用来区分满和空）；
指针转格雷码后跨域；**满/空各自在自己的域里判断**，用"本域真指针"与"对域同步来的指针"比较。

因为对域指针是延迟若干拍的旧值，判断天然偏保守：**可能短暂虚报满/空，但绝不会漏报**——
不会溢出，也不会读空。这个方向性是设计的关键，反过来就是灾难。

---

## 四、常见错误速查

| 现象 | 多半是 |
|---|---|
| 仿真全过、上板偶发挂死/丢数 | CDC 没做，或多 bit 各自打两拍 |
| 复位后状态机偶尔进不了 IDLE | 异步复位没有同步释放 |
| 时序报告里出现莫名其妙的时钟 | 组合逻辑或触发器输出被当成了时钟 |
| 综合资源暴涨、BRAM 用量为 0 | 给存储器阵列加了复位 |
| 同步器被综合器优化掉了 | 缺 `ASYNC_REG` / `dont_touch` |
| Verilator 报 `SYNCASYNCNET` | 同一信号既当同步复位又当异步复位 |

---

## 本篇检查清单

- [ ] 全设计的时钟都来自时钟源（端口 / PLL / MMCM），没有组合产生的时钟
- [ ] 需要降速的地方用的是时钟使能，不是分频出来的时钟
- [ ] 每个时钟域都有自己的 `reset_sync`，异步复位做了同步释放
- [ ] 复位统一低有效、命名 `rst_n`；外部极性在边界转换
- [ ] 模块头注释写明了本模块的复位方式（同步/异步）和时钟域
- [ ] 所有跨时钟域路径都已识别，并走了同步器 / 握手 / 异步 FIFO
- [ ] 同步器的输入是寄存器输出，不是组合逻辑输出
- [ ] 没有任何多 bit 总线是"各自打两拍"过来的
- [ ] 单周期脉冲跨域用的是 toggle 同步器，不是电平同步器
- [ ] 同步器加了 `ASYNC_REG`（FPGA）或等价约束（ASIC）
- [ ] MCP 握手的数据路径在 SDC 里有 `set_max_delay -datapath_only`
- [ ] 存储器阵列没有复位分支
- [ ] `verilator --lint-only -Wall` 没有 `SYNCASYNCNET` 告警
