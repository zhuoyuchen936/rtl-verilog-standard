# 09 · 存储器与硬核原语推断

综合器认存储器靠的是**固定的代码范式**，不是靠理解你的意图。
范式写对了，几百个触发器变成一块 BRAM；写错一个细节（比如给阵列加了复位），
它就老老实实给你综合出几千个触发器，资源报告瞬间爆红。

这一篇讲的就是那几个不能改的范式。

---

## 本篇速览

1. **存储器阵列绝不能有复位**——片上 RAM 没有复位端，加了就退化成触发器阵列。
2. 读输出**必须寄存**才能推断出 Block RAM；组合读会变成分布式 RAM/LUT。
3. 读写同地址时的行为（read-first / write-first）**各厂商默认不同**，跨平台必须显式确认。
4. `[ASIC]` 一般不推断，而是例化 memory compiler 生成的 SRAM 宏；RTL 里的 `mem` 只是仿真替身。

---

## 一、基本推断范式

### R-09-01 存储体的标准声明与读写 `[通用]`

```verilog
// 见 assets/templates/v2001/sdp_ram.v（已通过 lint + 综合验证，Yosys 报 32768 memory bits）
reg [DW-1:0] mem [0:(2**AW)-1];

always @(posedge clk) begin
    if (we) mem[waddr] <= wdata;
    if (re) rdata      <= mem[raddr];
end
```

本例的同钟 read-first 契约通过以下写法实现。其他端口类型按目标器件模板或工艺宏接口描述。

1. **读写放在同一个 `always @(posedge clk)` 里，且不带任何复位。**
2. **读输出寄存**（`rdata <= mem[raddr]`），不是 `assign rdata = mem[raddr]`。
3. 存储体只在这一个块里被赋值，别处不再碰它。

### R-09-02 存储器阵列绝不能复位 `[通用]` ★最常见的资源爆炸原因★

```verilog
// 反例，不要抄：综合器只能放弃 RAM，改用触发器实现整个阵列
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (i = 0; i < DEPTH; i = i + 1) mem[i] <= 0;
    end else if (we) mem[waddr] <= wdata;
end
```

**为什么**：物理上的片上 RAM（BRAM / SRAM 宏）根本没有复位端，
它的复位需要靠外部逻辑逐地址写一遍。写成上面那样，综合器唯一能满足语义的办法
就是用触发器搭出整个阵列。

需要"清空"存储器，请用一个状态机在复位后逐地址写 0，或者干脆用一个 valid 位数组
（valid 位可以复位，它数量少）来表示"这一项还没写过"。

### R-09-03 只有 RAM 的输出寄存器可以复位，且必须是同步复位到 0 `[FPGA]`

调研记录（`_research/web/W03-vendor-fpga-guidelines.md`，引 UG949 / Quartus 手册）指出：
Block RAM 自带的输出寄存器要能被综合器**吸收**，需要同时满足：
同一层次内、数据输出扇出为 1、无反馈、且复位是**同步**的并且**复位到 0**。
任何一条不满足，输出寄存器就会被搬到 BRAM 外面用普通触发器实现，白白多花资源和延迟。

> 这几条来自 W03 调研（标注了 UG949 p.64–66 / Quartus §2.4.1.2），我未逐页复核原文，
> 引用时请以厂商当前版本手册为准。

---

## 二、读写同地址的行为

### R-09-04 read-first 与 write-first 必须显式确认 `[通用]`

同一周期读写**同一个地址**时，`rdata` 拿到的是旧值还是新值？

| 行为 | 含义 | `sdp_ram.v` 的写法 |
|---|---|---|
| **read-first**（先读后写） | 读到**旧**值 | 本模板就是这种：非阻塞赋值在同一时刻统一更新 |
| **write-first**（写穿透） | 读到**新**值 | 需要显式加旁路逻辑 |

```verilog
// write-first：显式旁路，不要指望工具默认这么做
wire same_addr = we && re && (waddr == raddr);
always @(posedge clk) begin
    if (we) mem[waddr] <= wdata;
    if (re) rdata <= same_addr ? wdata : mem[raddr];
end
```

**为什么要在意**：不同厂商、不同 RAM 模式的默认行为不同。
依赖默认行为的设计换个平台就会错，而且这种错只在读写撞地址时才出现，很难在仿真里撞到。

---

## 三、指定实现方式

### R-09-05 用属性指定 RAM 实现风格 `[FPGA]`

```verilog
(* ram_style = "block" *)       reg [31:0] mem_big  [0:1023];  // Xilinx: 强制 BRAM
(* ram_style = "distributed" *) reg [7:0]  mem_tiny [0:15];    // Xilinx: 强制 LUTRAM
(* ramstyle = "M20K" *)         reg [31:0] mem_alt  [0:1023];  // Intel
```

容量、读写端口、时钟、复位和读延迟共同决定可映射的资源。属性表达目标选择，使用层次资源报告核对实际实例与利用率。

### R-09-06 移位寄存器与 SRL `[FPGA]`

长的、无中间抽头的移位寄存器在 Xilinx 上会被推断成 SRL（一个 LUT 顶 32 级），
非常省资源。**但加了复位就推不成 SRL 了**——SRL 没有复位端。
这是 R-06-07"数据通路尽量不加复位"在 FPGA 上的一个具体收益。

```verilog
// 能推断成 SRL：无复位
reg [DELAY-1:0] pipe;
always @(posedge clk) pipe <= {pipe[DELAY-2:0], din};
```

### R-09-07 ROM 用 `initial` + `$readmemh` 初始化 `[FPGA]`

```verilog
reg [15:0] rom [0:255];
// 索引参数不能省。不带索引时，仿真器按文件行数填、综合器按数组深度填，
// 一旦文件行数与数组深度不一致就会出现仿真-综合不一致。
// AMD UG901「Loading Memory Contents With File I/O Tasks」明确要求带索引。
initial $readmemh("rom_init.hex", rom, 0, 255);

always @(posedge clk) dout <= rom[addr];
```

`[FPGA]` 可综合：初值会被写进配置比特流。
`[ASIC]` **不可综合**：ASIC 上电状态随机，ROM 必须用 memory compiler 或综合成组合逻辑
（小容量的话，直接写 `case` 让综合器优化成门阵列往往更划算）。

这是 FPGA 与 ASIC 的又一处方向性差异，见 `14-disputes.md` D12。

---

## 四、ASIC 侧

### R-09-08 ASIC 一般不推断存储器，而是例化宏 `[ASIC]`

流程是：用 memory compiler 生成 SRAM 宏 → RTL 里例化它 → 仿真时用厂商提供的
behavioral model 或自己写的替身模块。

此时 `sdp_ram.v` 这样的模块只作为**仿真替身**存在，需要用条件编译隔开：

```verilog
`ifdef SYNTHESIS
    sram_2p_1024x32 u_mem (.clk(clk), .we(we), /* ... */);
`else
    sdp_ram #(.DW(32), .AW(10)) u_mem (.clk(clk), .we(we), /* ... */);
`endif
```

### R-09-09 存储器的 DFT 需要单独考虑 `[ASIC]`

SRAM 宏不在 scan 链上，需要 MBIST（Memory BIST）来测试。
RTL 阶段要预留 BIST 接口或走 wrapper，这一点在项目早期就要和 DFT 团队约定。

---

## 五、FIFO

### R-09-10 同步 FIFO 用同一时钟，异步 FIFO 走格雷码 `[通用]`

- **同步 FIFO**（读写同时钟）：用一个计数器记录占用量即可判断满空，简单可靠。
- **异步 FIFO**（读写不同时钟）：必须用格雷码指针 + 跨域同步，见
  `assets/templates/v2001/async_fifo.v` 与 `06-clock-reset-cdc.md` R-06-14。

用需求允许的最坏突发计算任一时间窗内累计写入与读出的最大差值，并计入回压生效前已经发出的数据。指针同步会延迟满/空的解除，需核对可用带宽。长期平均写入高于读出且上游持续发送时，需要流控。

### R-09-11 按实际访问选择存储结构

列出每个发射拍的读写地址、宽度、字节使能以及同址组合。标明读延迟、读使能关闭时的输出、返回端背压和最大在途数。按最坏合法地址序列计算 bank 冲突，按有效传输计数核验可持续带宽。

| 访问需求 | 候选 | 决定取舍的条件 |
|---|---|---|
| 相邻元素成组消费 | 加宽单字、按低位分 bank、分拍返回 | 对齐与跨字访问、独立写使能、尾组和消费者采样拍。加宽带来的返回 MUX、量化和写回也计入时序与资源。 |
| 多路独立随机读 | 多读口宏、复制只读表或广播写、分 bank 加仲裁 | 复制可换读口，所有副本须接收每笔获准写入。分 bank 需验证同 bank 请求的等待、顺序和公平性。 |
| 同步 RAM 或跨域 FIFO | BRAM/URAM、LUTRAM、工艺 SRAM 宏、带输出缓冲的 FIFO | 按目标核对读延迟、read-first/write-first/no-change 和端口碰撞规格。异步双时钟同址行为依器件与协议约定。把组合读改同步读时同步修改 empty/valid 和首字到达时刻。 |

`sdp_ram.v` 采用同钟同步读，同址同时读写返回旧值，`re=0` 保持上次输出。RTL 数值通过后，目标映射阶段再核对 RAM 类型、数量及工具插入的旁路。针对 ASIC 使用实际 SRAM 宏的时序与碰撞模型。

---

## 本篇检查清单

- [ ] 存储器阵列**没有**任何复位分支
- [ ] 读输出是寄存的（想推断 BRAM 时）
- [ ] 读写进程与目标 RAM 的推断模板或工艺宏接口匹配
- [ ] 存储体只在一个 always 块里被赋值
- [ ] 读写同地址的行为（read-first / write-first）已确认并写进注释
- [ ] 目标映射报告给出了所选 BRAM/URAM/LUTRAM 或 SRAM 宏的数量和端口模式
- [ ] 想推断 SRL 的移位寄存器没有加复位
- [ ] ROM 的 `$readmemh` 初始化方式与目标工艺匹配（FPGA 可综合 / ASIC 不可）
- [ ] `[ASIC]` 存储器宏与仿真替身用条件编译隔开，且已和 DFT 约定 MBIST 接口
- [ ] FIFO 容量覆盖最坏突发积压和回压生效前的在途数据
