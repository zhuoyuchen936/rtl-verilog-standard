# 11 · 提交前自检与 code review 检查表

> 配套主规范 `SKILL.md`。本篇不新增铁律，只把铁律翻译成**可勾选的动作**和**可执行的检查命令**。
> 标签约定同主规范：来源 `[教材]`/`[业界]`/`[工具]`，适用范围 `[通用]`/`[FPGA]`/`[ASIC]`/`[V2001]`/`[SV]`。

---

## 本篇速览

1. **先跑工具，再开口。** `python3 scripts/rtl_lint.py --top <top> --synth <file>.v` 必须输出 `通过 ✔`；没跑就提交的 PR，审查者有权直接打回，不必看代码。
2. **工具能查的问题不值得人争论**：位宽、latch、多驱动、组合环、case 覆盖、文件名/模块名，这六类一律以工具输出为准，不接受"我觉得没问题"。
3. **人只审工具查不出来的四件事**：架构与接口协议、复位/时钟域策略、状态机能否从非法态恢复、位宽截断是否是"故意的"。
4. **锁存器只有一个可靠修法**：组合块开头给所有被赋值对象赋默认值。`unique`/`priority`/`full_case` 都堵不住这个洞 `[业界]` Mills SNUG 2012 §4.1b。
5. **`-Wno-XXX` 全局关警告 = 审查不通过**，无例外。豁免只能是"最小范围 + 写清理由"，或集中进 `.vlt` 控制文件。
6. **FPGA 与 ASIC 的检查项不同**（复位极性、`initial` 初值、三态、DFT），审查前先确认 target；两者相反的地方本篇都会两边写出来。

---

## 0. 规矩：工具能查的，不要用人争论

### 0.1 提交前的固定动作 `[工具]` `[通用]`

```bash
# 最小动作：一条命令，两个引擎
python3 scripts/rtl_lint.py --top counter --synth rtl/counter.v

# SystemVerilog 加 --sv
python3 scripts/rtl_lint.py --top fifo_sync --sv --synth rtl/fifo_sync.sv

# 想让"告警"也直接判失败（推荐在 CI 里加）
python3 scripts/rtl_lint.py --top counter --synth --strict rtl/counter.v
```

它做两件人眼做不到的事：

| 引擎 | 命令 | 查什么 |
|---|---|---|
| Verilator | `--lint-only -Wall` | 语法、位宽、敏感表、latch、未驱动/未使用信号、case 覆盖、文件名≠模块名 |
| Yosys | `hierarchy -check; proc; opt -purge; check -assert; stat` | **真正推断出来的** latch（`$dlatch`）、多驱动网、组合环路，以及门/单元数量 |

为什么必须两个都跑 `[工具]` `[通用]`：Verilator 是**源码级**分析，Yosys 的 `proc` 会把 `always` 块真正展开成寄存器和 MUX，**latch 只有在 `proc` 之后才现形**。一个 lint 干净的文件，`stat` 里冒出 `$dlatch` 是常见事。

> 退出码：Verilator 默认把 warning 当致命错误、以非零码退出（这正是官方 `-Wno-fatal` "Disable fatal exit on warnings" 存在的理由，`[业界]` W06/S1 Verilator Arguments）。因此**只要有 warning，`rtl_lint.py` 就不会打印 `通过 ✔`**。CI 上再加 `--strict` 做双保险。

### 0.2 三层 lint 分工，别指望一个工具包打天下 `[业界]` OpenTitan Design Methodology `[通用]`

| 层 | 工具 | 管什么 | 是否门禁 |
|---|---|---|---|
| 风格 | `verible-verilog-format --verify` / `verible-verilog-lint` / `svlint` | 缩进、行长、命名、`module-filename` | OpenTitan：PR 门禁 `[SV]` 为主 |
| 语义 | `verilator --lint-only -Wall` | 位宽、latch、多驱动、敏感表 | **本规范的硬门禁** `[通用]` |
| 结构 | `yosys proc + check + stat` / `synth_design` | 真实推断结果、资源数 | 冒烟必跑 |
| 签核 | AscentLint / SpyGlass / Questa CDC | 完整规则集、CDC 结构分析 | `[ASIC]` 定期跑，非每次 PR |

OpenTitan 的原话是 Verilator/Verible 做 PR 门禁、商业 AscentLint 每 8 小时跑一次并发布结果 —— **快的放前面，慢的放后面**，不要把 30 秒能查出来的问题留给 8 小时后的报告。

### 0.3 Verilator 查不了什么（别用它下结论） `[业界]` W06/S4 Language Standard Support `[通用]`

- **X 传播**：官方原话 "Verilator is mostly a two-state simulator, not a four-state simulator."。因此 **`casex`/`casez` 的 X 语义安全性、复位前 X 传播，Verilator 给不出可靠答案**，要用四态仿真器（iverilog 粗筛，VCS/Questa/Xcelium 签核）。
- `specify` 块与时序检查一律被忽略。
- 不加 `--timing` 时延时语句被忽略并报 `STMTDLY`。
- 反过来说，Verilator 是**最严格的可综合子集守门员**：能过 Verilator lint 的代码，通常也能过综合器。

---

## 1. 提交前自检清单

> 用法：每条自己勾。**勾不掉就不要提交**。括号里的标签是来源与适用范围。

### 1.1 编译 / lint

- [ ] `rtl_lint.py ... --synth` 输出 `通过 ✔`，**零 error 零 warning** `[工具]` `[通用]`
- [ ] Yosys `stat` 里没有意料之外的 `$dlatch`；DFF 数量与手算一致 `[工具]` `[通用]`
- [ ] 文件名 == 模块名，一个文件只有一个 module（Verilator `DECLFILENAME`）`[教材]` p.380(1)(2) `[工具]` `[通用]`
- [ ] 文件以 `` `default_nettype none `` 开头、`` `default_nettype wire `` 结尾（把拼写错误变成编译错误）`[业界]` lowRISC `[通用]`
- [ ] 没有任何全局 `-Wno-XXX`；所有豁免都是最小范围 + 写明理由（见 §3）`[业界]` Verilator 官方 `[通用]`
- [ ] 4 空格缩进、无 Tab、每行一个声明或语句 `[教材]` p.380(3)(4) `[通用]`
- [ ] 模块头注释写全：功能 / 时钟域 / 复位方式 / 接口协议 / CDC 说明 `[业界]` `[通用]`
- [ ] `[SV]` `verible-verilog-format --verify --failsafe_success=false` 通过（**必须加 `--failsafe_success=false`，否则出错也返回 0**）`[业界]` W06/S25

### 1.2 组合逻辑

- [ ] 组合 `always` 块内**只有 `=`**，没有 `<=`（Verilator `COMBDLY`）`[教材]` p.197(3)、p.205 `[通用]`
- [ ] 敏感表写 `always @(*)`（`[SV]` 用 `always_comb`），**没有手写敏感表** `[教材]` p.322-323 电平敏感 always `[业界]` Mills&Cummings SNUG'99 §2.1 `[通用]`
- [ ] **块首给所有被赋值对象（含临时量、向量全位、结构体字段）赋了默认值** `[业界]` Mills SNUG 2012 §7.0 `[通用]`
- [ ] 每个 `case` 都有 `default`，每个 `if` 都有 `else`（或已被块首默认值覆盖）`[教材]` p.323 `[通用]`
- [ ] 本块赋值的变量没有在本块中被读作输入（无组合反馈）`[教材]` p.380(7)、p.180 `[通用]`
- [ ] `[SV]` `always_comb` 内没有"先读后写"同一变量 —— `always_comb` 的隐式敏感表**排除块内被写的变量**，而 `always @*` 不排除；同一段代码换关键字会静默改行为 `[业界]` IEEE 1800 §9.2.2.2.1 vs IEEE 1364-2005 §9.7.5 Example 2 `[SV]`/`[V2001]` 差异点

> **为什么不能靠 `unique`/`priority` 防 latch**：它们只检查 case **分支集合**的互斥/完整性；latch 推断针对的是"某个输出在某条可达路径上没被赋值"。Mills SNUG 2012 的原话：*"Many designers are led to believe that unique case and priority case solve their latch issues... **This is simply not so.**"* 两者是正交的。

### 1.3 时序逻辑

- [ ] 时序 `always` 块内**只有 `<=`**（Verilator `BLKSEQ`）`[教材]` p.197(1)、p.205、p.320 `[通用]`
- [ ] 同一个 `always` 块内没有混用 `=` 和 `<=` `[教材]` p.197(5) `[通用]`
- [ ] **一个变量只在一个 `always` 块里被赋值**（Verilator `MULTIDRIVEN`）`[教材]` p.197(6)、p.180 `[通用]`
- [ ] 每个时序 `always` 只由**一个**时钟沿触发；敏感表里只有时钟沿和异步复位沿，且全部是边沿敏感 `[教材]` p.180(4) `[业界]` Cummings SNUG 2003 §5.1 `[通用]`
- [ ] 赋值里没有 `#` 延迟（含 `#0`）`[教材]` p.197(8)、p.381(13) `[通用]`
- [ ] 没有用 `integer` / `time` 做设计信号 `[教材]` p.381(14) `[通用]`
- [ ] `[ASIC]` 带复位的触发器与不带复位的 follower 触发器**不在同一个 `always` 块**（同步复位下会多综合出可加载 FF）`[业界]` Cummings SNUG 2003 §3.1
- [ ] 复杂算术（阶乘、除法、长循环）没有塞进一个时钟周期，已拆成多周期 + 中间寄存器 `[教材]` p.326 `[通用]`

> **为什么 D1~D3 是最重要的三条**：Verilog 的分层事件队列里，阻塞赋值在 active region 立刻更新，非阻塞赋值要等 NBA region。时序块用阻塞赋值 → 多个 `always` 块的执行顺序影响结果，而 IEEE 标准**不规定这个顺序**。教材 p.322 思考题 3 把它演示得很直白：把 `b=a; c=b;` 拆成两个 `always @(posedge clk)` 块，就是竞争冒险；顺序对调，电路从 1 级寄存器变成 2 级串联寄存器。

### 1.4 复位与时钟

- [ ] 时钟和复位不由组合逻辑产生（没有 `assign gclk = clk & en;`）`[教材]` p.380(2) `[业界]` `[通用]`
- [ ] 异步复位在敏感表里；同步复位**不在**敏感表里；同一根复位不会在一处同步、另一处异步（Verilator `SYNCASYNCNET`）`[教材]` p.189-191 `[工具]` `[通用]`
- [ ] 复位极性与分支极性一致（`negedge rst_n` 配 `if (!rst_n)`）`[业界]` lowRISC `[通用]`
- [ ] 所有内部状态寄存器可复位；不复位的只能是纯数据搬运的流水寄存器，且 valid/enable 类控制位**必须**复位 `[教材]` p.317（reg 未赋值即不定态）`[业界]` Cummings SNUG 2003 §2.0 `[通用]`
- [ ] 需要分频/省功耗时用**时钟使能** `if (en) q <= d;`，不是门控时钟 `[业界]` Synopsys Power Compiler / AMD UG949 `[通用]`
- [ ] `[ASIC]` 异步复位配了复位同步器（异步置位、同步释放）—— Cummings SNUG 2003 §7.0 原文全大写：*"EVERY ASIC USING AN ASYNCHRONOUS RESET SHOULD INCLUDE A RESET SYNCHRONIZER CIRCUIT!!"*
- [ ] `[ASIC]` 每个时钟域一套独立的复位同步器与复位树 `[业界]` Cummings SNUG 2003 §11.0
- [ ] `[ASIC]` 复位路径上除复位同步器和 DFT 旁路 MUX 外没有任何逻辑（复位不参与功能）`[业界]` Cummings SNUG 2003 §10.0
- [ ] 跨时钟域信号都走了同步器 / 异步 FIFO / 握手，且**同步器输入来自寄存器输出**（不是组合逻辑末端）`[业界]` `[通用]`
- [ ] 一个模块只有一个时钟域（例外只有同步器 / 异步 FIFO 模块本身）`[业界]` Cummings SNUG 2001 §6.0 `[通用]`

> **`[FPGA]` 与 `[ASIC]` 在这里是相反的，必须两边都写清楚：**
> - `[FPGA]` AMD UG901 逐字：*"**Do not asynchronously set or reset registers.** ... Sequential functionality in device resources, such as block RAM components and DSP blocks, **can be set or reset synchronously only**."* 异步复位会阻断 BRAM/DSP/SRL 推断、吃掉 control set。
> - `[ASIC]` lowRISC/OpenTitan 逐字：*"Chip wide all resets are defined as active low and asynchronous."* 标准单元有异步复位端，且有完整的 reset tree / recovery-removal 方法学。
> - **审查动作**：不是判对错，是查模块头注释有没有写明本模块用哪种，以及全项目是否一致。混用才是真错误。

### 1.5 状态机

- [ ] 状态编码用 `localparam`（`[SV]` 用 `enum`），不是 `` `define ``，不是裸数字 `[业界]` lowRISC/Cummings `[通用]`
- [ ] 次态组合块**开头先写 `next_state = state;`**，并给所有 Moore/Mealy 输出赋默认值 `[业界]` lowRISC / Mills SNUG 2012 `[通用]`
- [ ] `case` 有 `default` `[教材]` p.177 `[通用]`
- [ ] 状态数不是 2ⁿ 时，**所有 2ⁿ 种编码的行为都被明确描述**，能从非法态回到安全态 `[教材]` p.381(12) `[通用]`
- [ ] 没有用 `casex` 做状态译码（教材 p.329 的 `seqdet.v` 用了 `casex`，**本规范不采纳这个写法**，理由见 §6-D4）`[业界]` Cummings SNUG'99 `[通用]`
- [ ] 时序块里只有复位和 `state <= next_state;`，没有别的逻辑 `[业界]` lowRISC `[通用]`
- [ ] 没有综合器实现的异步状态机 `[教材]` p.180(3)、p.177 `[通用]`
- [ ] `[ASIC]` 安全关键设计：确认综合脚本没有让工具自行 FSM 重编码（Vivado 支持 `fsm_encoding` / `fsm_extract` 属性，默认会重编码）`[业界]` AMD UG901 Ch.9

### 1.6 位宽与符号

- [ ] 字面量全部写全位宽和进制：`8'd0` / `4'b1010`，没有裸 `0` / `1` `[业界]` lowRISC `[通用]`
- [ ] 赋值两侧位宽相等；截断/扩展**显式写出来**（Verilator `WIDTHTRUNC` / `WIDTHEXPAND`）`[工具]` `[通用]`
- [ ] 拼接 `{}` 里每个操作数都有显式位宽 —— IEEE 1364-2005 逐字：*"**Unsized constant numbers shall not be allowed in concatenations.**"* `[业界]` `[通用]`
- [ ] 需要保留进位/全积的算式**先把操作数扩宽**，没有写成 `{a + b}` 这种被拼接强制自决定的形式 `[业界]` IEEE 1364-2005 §5.4.2/§5.4.3 `[通用]`
- [ ] 有符号运算显式 `$signed()`；没有有符号与无符号混合比较 —— *"**If any operand is unsigned, the result is unsigned, regardless of the operator.**"*；且 **part-select 与拼接的结果永远是无符号的**，符号位要手工补 `[业界]` IEEE 1364-2005 §5.5.1 `[通用]`
- [ ] `case` 各分支表达式位宽相同；没有用 `'bx` 代替 `n'bx` `[教材]` p.54 `[通用]`
- [ ] 没有 `casex`；`casez` 只在必须通配时用，且通配符写 `?` 不写 `z` `[业界]` Cummings SNUG'99 Boston 逐字 Guideline `[通用]`
- [ ] 没有 `full_case` / `parallel_case`（注释式、`// synthesis` 式、属性式全禁）`[业界]` Cummings SNUG'99 Boston `[通用]`
- [ ] `for` 循环边界是常量 `[教材]` p.381(15) `[通用]`
- [ ] `[SV]` 用了 `$clog2` 的地方处理了边界：`$clog2(0)==0`、`$clog2(1)==0`，写成 `(DEPTH<=1) ? 1 : $clog2(DEPTH)` `[业界]` IEEE 1364-2005 §17.11.1 逐字

### 1.7 接口与层次

- [ ] 例化全部用命名端口连接 `.clk(clk)`；没有按位置连接，没有 `.*` `[教材]` p.315 `[业界]` `[通用]`
- [ ] 没有 `PINMISSING`：所有端口都连了；有意悬空写成显式的 `.pin_name()`（`PINCONNECTEMPTY` 是刻意声明，不是漏）`[工具]` `[通用]`
- [ ] 端口连接位宽严格匹配（工具会静默截断/补零）`[业界]` lowRISC `[通用]`
- [ ] 模块间只走寄存器输出，或明确标注的组合输出 `[业界]` `[通用]`
- [ ] 顶层之外没有 `inout` / 三态 —— `[FPGA]` AMD UG901 逐字：内部 BUFT *"is converted automatically to logic realized in LUTs"*；`[ASIC]` 内部三态有上电总线竞争风险，一律改 MUX
- [ ] 参数用 `parameter` / `localparam`，没有魔数 `[教材]` p.380(8) `[通用]`
- [ ] 没有跨模块层次引用（XMR）进入可综合 RTL（注：此条**未取到一手出处**，属业界共识，按本规范执行但不作为一票否决项）

### 1.8 验证

- [ ] testbench 自检（有期望值比对），不是"看波形觉得对" `[教材]` p.314 `[通用]`
- [ ] 回归失败能让进程返回非零：iverilog 用 `vvp -N`（`$stop` 时退出码 1）`[业界]` W06/S13 `[通用]`
- [ ] 复位序列写对：**在时钟无效沿改变复位**，时刻 0 的第一次赋值用 `<=` `[业界]` Cummings SNUG 2003 §7.4 `[通用]`
- [ ] 波形默认关闭，用 plusarg（如 `+trace`）开；长回归用 FST 不用 VCD `[业界]` W06/S8 `[通用]`
- [ ] 至少跑过 RTL 级仿真；改动涉及时序/复位的还要跑综合后门级仿真 `[教材]` p.313、p.316 练习题 1 `[通用]`
- [ ] 随机激励 + 定向激励都有（教材 p.315-316 的两种测试法对照就是这个意思）`[教材]` `[通用]`
- [ ] `[通用]` 断言只在仿真里生效：用 `` `ifndef SYNTHESIS `` 包住，**不要指望综合器**。注：Vivado `synth_design -assert` 的官方定义是"启用 **VHDL** assert 语句"，不是 SV 断言综合 `[业界]` W06/S16

### 1.9 自检通过的代码长什么样（正例，可直接综合）

```verilog
`default_nettype none
//----------------------------------------------------------------------
// mux4_reg.v
// 功能  : 4 选 1 + 独热译码 + 一级输出寄存
// 时钟域: clk 单域，本模块无 CDC
// 复位  : rst_n 异步低有效、同步释放（由上层 reset_sync.v 提供）
// 接口  : 无握手，组合译码 + 输出寄存，固定 1 拍延迟
//----------------------------------------------------------------------
module mux4_reg #(
    parameter integer DW = 8
) (
    input  wire            clk,
    input  wire            rst_n,
    input  wire [1:0]      sel,
    input  wire [DW-1:0]   d0,
    input  wire [DW-1:0]   d1,
    input  wire [DW-1:0]   d2,
    input  wire [DW-1:0]   d3,
    output reg  [DW-1:0]   q,
    output reg  [3:0]      onehot
);

    reg [DW-1:0] mux_data;

    // 组合块：块首赋默认值 —— 防 latch 的唯一可靠手段
    always @(*) begin
        mux_data = {DW{1'b0}};
        onehot   = 4'b0000;
        case (sel)
            2'd0: begin mux_data = d0; onehot = 4'b0001; end
            2'd1: begin mux_data = d1; onehot = 4'b0010; end
            2'd2: begin mux_data = d2; onehot = 4'b0100; end
            2'd3: begin mux_data = d3; onehot = 4'b1000; end
            default: ;   // 默认值已在块首给出
        endcase
    end

    // 时序块：只有非阻塞赋值，只有一个时钟沿
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) q <= {DW{1'b0}};
        else        q <= mux_data;
    end

endmodule
`default_nettype wire
```

`sel` 只有 4 种取值、`case` 已经全覆盖，为什么还要 `default`？因为**仿真时 `sel` 取值为 `X` 不会匹配任何 case item，行为等同 latch，而综合器不知道 `X`** —— 这正是 lowRISC 要求"即使全覆盖也必须写 `default`"的理由 `[业界]` lowRISC Case Statements。

---

## 2. Verilator warning 速查表：代码 → 含义 → 正确修法

> 引号内为 Verilator 官方 *Errors and Warnings* 文档原文（`[业界]` https://verilator.org/guide/latest/warnings.html ）。
> **"正确修法"一栏里没有一条是 `lint_off`** —— 这是故意的。

| 代码 | 官方含义 | 典型成因 | 正确修法 | 审查态度 |
|---|---|---|---|---|
| `WIDTH` | "Two operands have different widths, or a part select has a different size than needed." | `assign a8 = b4 + c16;` | 显式定宽：part-select / 拼接 / `[SV]` cast `8'(x)` | 🔴 不许豁免 |
| `WIDTHTRUNC` | "for when a value is truncated" | 大赋小 | 写成 `x[7:0]`，表明"我知道在截位"；配断言 `wide[15:8]==0` | 🔴 不许豁免 |
| `WIDTHEXPAND` | "for when a value is zero expanded" | 小赋大 | `{{4{1'b0}}, x}` 或 cast | 🟡 |
| `WIDTHCONCAT` | "Warns that a concatenate or replication has an indeterminate width." | 拼接里放了无宽度字面量 `1` | 所有拼接元素写成定宽 `1'b1` | 🔴 |
| `LATCH` | "a signal is not assigned in all control paths of a combinational always block, resulting in latch inference" | if 无 else / case 无 default / 分支漏赋某个输出 | **块首赋默认值**；真要 latch 用 `[SV]` `always_latch` 并写明 | 🔴 不许豁免 |
| `CASEINCOMPLETE` | "there is a stimulus pattern for which no case item is provided" | 缺 `default` | 加 `default:` | 🔴 |
| `CASEOVERLAP` | "case statement has overlapping values" | `casez` 通配重叠 → 隐式优先级链 | 收紧/重排 case item；**有意的优先级请改写成 `if-else-if`** | 🟡 |
| `CASEX` | "it is better style to use casez with '?' instead of 'x'" | 用了 `casex` | 改 `casez` + `?`；`[SV]` 用 `case ... inside` | 🔴 |
| `BLKSEQ` | "blocking assignment (=) is used in a sequential block." | 时序块里写 `=` | 时序块一律 `<=` | 🔴 |
| `COMBDLY` | "there is a delayed assignment inside of a combinatorial block... may lead to the simulator not matching synthesis." | 组合块里写 `<=` | 组合块一律 `=` | 🔴 |
| `MULTIDRIVEN` | "the specified signal has multiple procedural drivers" | 同一信号被两个 `always` 赋值 | 合并到一个块 | 🔴 不许豁免 |
| `UNOPTFLAT` | "optimization of the specified signal is disabled"；官方例 `wire [2:0] x = {x[1:0], shift_in};` | 同一向量不同 bit 互相驱动 | 拆成两个信号（官方修法 `wire [2:0] xout = {x[1:0], shift_in};`）；或 `--report-unoptflat` 让工具推荐拆分点 | 🔴 疑似组合环 |
| `ALWCOMBORDER` | "an always_comb block reads a variable before assigning it later in the same block" | 组合块内先读后写 | 按依赖顺序：先写后读 | 🔴 `[SV]` |
| `SYNCASYNCNET` | "a net is used in multiple always statements with posedge/negedges, mixing sync and async resets" | 同一复位既同步又异步 | 统一复位风格，或分成两根网 | 🔴 |
| `IMPLICIT` | "a wire is implicitly declared from a sub-module output" | 忘了声明 wire | 显式声明；**加 `` `default_nettype none `` 把它变成编译错误** | 🔴 |
| `UNDRIVEN` | "the specified signal has no source" | 忘了连 | 补驱动 | 🔴 |
| `PINMISSING` | "a module has a pin that is not mentioned in an instance" | 例化少连口 | 补全；确实悬空写 `.pin_name()` | 🔴 |
| `PINCONNECTEMPTY` | "an instance pin is connected to `.pin_name()` with no signal" | 有意悬空 | 保持显式 `.x()`，这是**刻意声明**，不是缺陷 | 🟢 |
| `DECLFILENAME` | "a module name doesn't match the filename" | `fifo.v` 里定义 `sync_fifo` | 一文件一模块、文件名==模块名 | 🟡 |
| `VARHIDDEN` | "a variable declaration hides a variable in upper-level scope" | genvar/循环变量重名 | 改名 | 🟡 |
| `SELRANGE` | "a selection index will go out of bounds" | 常量下标越界 | 修下标或用 `$bits`/参数化 | 🔴 |
| `UNUSEDSIGNAL` | "the specified signal is never used/consumed" | 端口/信号声明后没用 | 删掉；或按官方提示改成含 `unused` 的名字 | 🟢 参数化 IP 里噪声大，可用 `.vlt` 按目录关 |

**`DECLFILENAME` 与 `UNUSEDSIGNAL` 是唯二可以按目录整体豁免的**（`[业界]` W06 §3.2：参数化 IP、自动生成代码里它们噪声极大）。其余全部不许。

### 反例集锦（**这是反例，不要抄**）

```verilog
// ===== 反例，不要抄 =====

// ① LATCH：if 无 else，y 在 en==0 的路径上没被赋值
always @(*) if (en) y = d;                 // 修法：块首 y = 1'b0;

// ② BLKSEQ + MULTIDRIVEN：时序块用阻塞赋值，且 b 被两个块驱动
always @(posedge clk) b = a;
always @(posedge clk) c = b;               // 执行顺序未定义 → 竞争冒险（教材 p.322 思考题 3）

// ③ WIDTHCONCAT + 进位丢失：拼接使操作数自决定，(a+b) 只有 8 bit
wire [8:0] sum_bad = {a8 + b8};            // 修法：{1'b0,a8} + {1'b0,b8}

// ④ 符号陷阱：part-select 结果是无符号的，比较被整体提升为无符号
wire lt_bad = (sa[7:0] < u8);              // sa=-1 会变成 255
wire sr_bad = sa[7:0] >>> 1;               // part-select 无符号 → 其实是逻辑右移

// ⑤ 门控时钟：en 的毛刺会变成假时钟沿，且切断 CTS/STA/DFT
assign gclk = clk & en;
always @(posedge gclk) q <= d;             // 修法：always @(posedge clk) if (en) q <= d;

// ⑥ 无位宽字面量 + 裸 -1：与 8 位无符号量比较恒为真
wire always_true = (u8 < -1);              // -1 是 32 位有符号 → 提升为 32'hFFFF_FFFF
```

---

## 3. 豁免 lint 的唯一正确姿势

按推荐度排序 `[业界]` Verilator 官方 *Errors and Warnings* / *Control Files*：

1. **先改代码**。绝大多数 `WIDTH`/`LATCH`/`CASEINCOMPLETE` 都是真 bug。
2. 确需局部豁免：最小范围 `lint_off`/`lint_on` 成对包住**那一行**，旁边写清原因。
3. 第三方 IP / 生成代码不可改：用 `.vlt` 控制文件集中豁免，源码零污染。
4. **最后才是** `-Wno-XXX` —— 官方明确不推荐："removes all checking across the source files, and prevents other users from compiling the sources without knowing the magic set of disables needed."

```verilog
// 正例：最小范围 + 写清理由 + 成对
/* verilator lint_off WIDTHTRUNC */
assign rom_addr = base_addr + offset;   // ROM 高位恒零，截位已人工确认 2026-08-12
/* verilator lint_on  WIDTHTRUNC */
```

```verilog
// 反例，不要抄：文件第 1 行，且没有 lint_on
/* verilator lint_off WIDTH */
```

**为什么反例致命**：官方原文 —— *"A lint_off in the design source code will **propagate down to any child files**（files later included by the file with the lint_off），but will not propagate upwards."* 一个写在头文件顶部的 `lint_off WIDTH`，会静默关掉整棵包含树的位宽检查。忘写 `lint_on` 等价于"从该点到文件末尾及所有 include 全关"。

`.vlt` 控制文件（必须作为**第一个**文件传入，因为 file/line 指令只对**随后读入**的文件生效）：

```
`verilator_config
// 第三方 IP：不改源码，集中豁免
lint_off -rule WIDTH        -file "*/vendor/*"
lint_off -rule DECLFILENAME -file "*/vendor/*"
// 本项目：逐条写清理由 + 精确到文件/行
lint_off -rule WIDTHTRUNC -file "*/rtl/rom_ctrl.v" -lines 42
```

配 `rtl_lint.py` 用——**请用专门的 `--waiver` 选项**，它会做 Windows→WSL 路径转换，
并保证控制文件排在源文件之前：

```bash
python3 scripts/rtl_lint.py --top top --waiver lint/waivers.vlt --synth rtl/*.v
```

（旧写法 `--verilator-arg` 也能塞进去，但它**不做路径转换**，Windows 上只能用相对路径，容易踩坑。
下面这段保留作对照，新代码请一律用 `--waiver`。）

```bash
python3 scripts/rtl_lint.py --top soc_top --synth \
       --verilator-arg lint/waivers.vlt rtl/*.v
```

> `[工具]` 注意：`--verilator-arg` 的内容**不会**做 Windows→WSL 路径转换，请从工程根目录用相对路径调用；
> 用 `--waiver` 则没有这个限制（脚本已内置路径转换）。
> 接手遗留代码时可以先 `verilator --waiver-output waivers.vlt` 生成基线，**但必须逐条 review 并删掉真 bug 的那些**，然后冻结基线、禁止新增。

---

## 4. Code review 评分表

### 4.1 打分规则

- **审查者的第一个动作是跑 `rtl_lint.py`，不是读代码。** 工具能查的问题不值得人去争论；工具报红就直接打回，附上输出即可。
- 每项打 **2 / 1 / 0** 分：2 = 干净，1 = 有瑕疵但不影响正确性，0 = 有实质问题。
- **A 类任一项得 0 分 → 直接打回**，不看总分。
- B 类得 0 分 → 必须在本 PR 内改完。C 类得 0 分 → 记 issue，可后续改。
- 总分仅用于横向比较代码质量趋势，不作为放行依据。

### 4.2 评分表

| # | 类 | 检查项 | 怎么查（先工具、后人眼） | 常见借口 → 怎么回 |
|---|---|---|---|---|
| 1 | A | lint / 综合冒烟干净 | `rtl_lint.py --top X --synth --strict`；看 `通过 ✔` | "我本地跑过了" → **贴输出**。没有输出等于没跑。 |
| 2 | A | 组合块无 latch | Verilator `LATCH`；Yosys `stat` 里 `$dlatch`；`[FPGA]` 综合日志 `Synth 8-327 inferring latch` | "综合器会优化掉" → 综合器优化不掉 latch，它就是综合器**推断**出来的。<br>"`unique case` 已经保证了" → Mills SNUG 2012 §4.1b 逐字反证，`unique` 不覆盖"输出漏赋值"。 |
| 3 | A | 时序块只用 `<=`、无多驱动 | Verilator `BLKSEQ` / `COMBDLY` / `MULTIDRIVEN` | "仿真结果是对的" → 顺序由仿真器调度决定，IEEE 不规定；**换个仿真器就可能变**。 |
| 4 | A | 位宽无隐式截断 | Verilator `WIDTHTRUNC` / `WIDTHEXPAND` / `WIDTHCONCAT` | "高位肯定是 0" → 那就显式写 `x[7:0]` 并加断言，让工具替你证明。 |
| 5 | A | 跨时钟域无裸线直连 | 人眼：找所有跨域信号；`[FPGA]` `report_cdc -details`；`[ASIC]` SpyGlass/Questa CDC | "只有一根信号，慢时钟采快时钟没事" → 亚稳态与位宽无关。<br>"时序报告没报错" → UG949 逐字：*"Report CDC does not provide timing information because timing slack does not make sense on paths that cross asynchronous clock domains."* CDC 只能靠**结构性**检查。 |
| 6 | A | 复位策略明确且全项目一致 | 读模块头注释；Verilator `SYNCASYNCNET`；grep 敏感表 | "FPGA/ASIC 上都能跑" → 两边的最优解**相反**（UG901 禁异步 vs lowRISC 全异步），请先说 target。 |
| 7 | A | 无门控时钟、无组合逻辑产生的时钟 | grep `assign .*clk.*&`；`[FPGA]` 看 Cell Usage；`[ASIC]` `report_clock_gating` | "省功耗必须门控" → 写 `if (en) q <= d;`，让工具插 ICG。SNUG 2000 实测：动态电流 -72%，**面积还净减 6.7%**（省掉回环 MUX）。 |
| 8 | B | FSM 可从非法态恢复 | 读 `case` + `default`；状态数非 2ⁿ 时逐个数编码 | "那个状态进不去" → 单粒子翻转/毛刺进得去；写 `default` 的成本是一行。 |
| 9 | B | `case` 有 `default`、`if` 有 `else` | Verilator `CASEINCOMPLETE` | "所有取值都覆盖了" → 仿真里 `X` 不匹配任何 item，行为等同 latch（lowRISC 的原始理由）。 |
| 10 | B | 无 `casex` / `full_case` / `parallel_case` | grep | "工具不认识就当注释" → **AMD UG901 至今仍列出这两个 meta comment**，Vivado 和 DC 都会响应，它是活的。<br>Cummings 原话：*"'full_case' and 'parallel_case' directives are most dangerous when they work!"* |
| 11 | B | 例化命名端口、无 `PINMISSING` | Verilator `PINMISSING` / `PINCONNECTEMPTY` | "顺序我核对过了" → 下一个人改端口顺序时你不在。 |
| 12 | B | 无内部三态 / `inout` | Verilator；`[FPGA]` Cell Usage 里出现 `BUFT`/`OBUFT` | "内部总线这样写最省" → `[FPGA]` UG901 逐字：内部 BUFT *"is converted automatically to logic realized in LUTs"*，一点也不省。 |
| 13 | B | 有符号/无符号未混用 | 人眼 + `$signed` grep | "编译器会处理" → IEEE 1364-2005 §5.5.1：*"If any operand is unsigned, the result is unsigned."* 它确实"处理"了，只是不是你想的那样。 |
| 14 | B | 豁免最小化且有理由 | grep `lint_off`、`-Wno-`；查有无配对 `lint_on` | "只关了一个 warning" → `lint_off` **会向下传播到所有 include**。<br>"CI 太吵" → 吵是因为有问题，不是因为工具坏。 |
| 15 | B | testbench 自检 + 失败返回非零 | 看有无期望值比对；`vvp -N` | "看波形就知道对不对" → 回归跑 500 次没人看 500 张波形。 |
| 16 | B | 无 `initial` / `#` 延迟进设计 | Verilator；grep | "FPGA 支持声明初值" → `[FPGA]` 确实进 bitstream（UG901：INIT 属性、全局复位/上电生效、**与本地复位无关**），但 `[ASIC]` 没有；用了就必须在文件头写明 "FPGA-only"。 |
| 17 | C | 命名/缩进/文件头注释 | `verible-verilog-format --verify --failsafe_success=false` | "风格是个人喜好" → 是，所以交给工具，不要在 review 里争。 |
| 18 | C | 无魔数、参数化合理 | 人眼 | "只用了一次" → 只用一次的常量也要有名字，否则下一个人不知道 19 是什么（教材 p.318 的 `j==19`）。 |
| 19 | C | 长组合链已拆流水 | `[FPGA]` `report_timing_summary`；`[ASIC]` `report_timing` | "现在时序过了" → 教材 p.326：复杂算术要"拆分成几个步骤，通过寄存器存储中间数据"。 |
| 20 | C | 注释解释"为什么"而非"是什么" | 人眼 | "代码自解释" → 时序假设、协议约定、位宽推导过程都不自解释。 |

### 4.3 审查者自己也要守的三条

1. **先跑再说**。没跑工具就提出的意见，作者有权要求你先跑。
2. **意见要能落到具体动作**。"这里写得不好"不是意见；"第 42 行 `WIDTHTRUNC`，请改成 `x[7:0]` 并加断言"才是。
3. **分清"规范违反"和"我的偏好"**。规范里没写、工具也不查的，标注为"建议"，不阻塞合入。

---

## 5. 综合报告里必须复核的几项

`[FPGA]` Vivado `[业界]` AMD UG901 / UG906：

- `WARNING: [Synth 8-327] inferring latch for variable '<name>'` → **CI 里 grep 到即 fail**；Cell Usage 里出现 `LD` 且不在白名单，同样 fail。
- Cell Usage 出现 `OBUFT` / `BUFT` → 有三态，检查是不是内部总线。
- Critical Warning 必须清零或显式豁免；用 `set_msg_config -id {...} -new_severity ERROR` 把 latch 提升为 error。
  > 注：具体消息 ID（`Synth 8-327` 等）**随 Vivado 版本变化**，写进 `build.tcl` 前先在本地日志确认（本条来自社区实践，无官方 ID 列表出处）。
- `report_cdc -details`：每条 Critical 逐条给结论 —— 要么改成标准两级同步器/异步 FIFO，要么写 waiver 说明为什么安全。
- 时序不收敛仍会产出 bit 文件，所以**必须**在脚本里检查 WNS/WHS 并主动 `error`，不能只看 `write_bitstream` 成功与否。

`[ASIC]`：Design Compiler 的等价告警（`ELAB-974` `always_comb` 里推出 latch / `ELAB-975` `always_latch` 里没有 latch / `ELAB-976` `always_ff` 里没有触发器，`[业界]` Sutherland SNUG SV 2013）、`report_clock_gating`、`report_resources`、以及 recovery/removal 弧线是否打开。

`[ASIC]` `[工具]` 开源流冒烟：Yosys `stat` 期望"没有意料之外的 `$dlatch` / `$mem`，DFF 数量与手算一致"。Yosys 对 SV 的支持**远小于** Verilator（interface、复杂 package、部分 typedef 会失败），此时用 Verilator 做 lint、Yosys 只做子模块冒烟。

---

## 6. 已知分歧：review 时不要当成硬伤

> 以下议题**业界一手资料本身就是对立的**。审查时只查"是否选了一种并全项目一致 + 有没有在模块头写明"，不要按个人偏好判错。

| # | 议题 | 对立双方（均有一手出处） | 本规范默认取舍 |
|---|---|---|---|
| D1 | 同步 vs 异步复位 | `[FPGA]` AMD UG901：*"Do not asynchronously set or reset registers."* ↔ `[ASIC]` lowRISC：*"Chip wide all resets are... active low and asynchronous."*；Cummings/Mills/Golson SNUG 2003 自己从"推荐异步"改口为**中立**，并称其*"has almost become a religious issue"* | 按 target 选：`[FPGA]` 同步复位优先；`[ASIC]` 异步复位 + 复位同步器。**必须在模块头写明**，混用才是错 |
| D2 | `case` 的 `default` 赋什么 | 教材 p.323 `default: out=8'hx;`（X 当 don't-care 交给综合器优化）↔ lowRISC：*"RTL must not assert `X` to indicate 'don't care' to synthesis in any case."*；Mills SNUG 2012 反过来说 *"Propagating X is a better solution than inferring a latch"* | **默认显式回安全态**（见 `14-disputes.md`）。有完整 SVA/formal 基础设施的项目可用"全定义 + 断言非法态" |
| D3 | `unique`/`priority` 该不该到处加 | lowRISC：*"The `unique` prefix is recommended before all case statements"* ↔ Cummings SNUG 2005：*"Do not use the priority and unique directives with all... case statements"*（取值域天然不满时会刷 run-time error 淹没真问题） | 取值域受控 → 加 `unique` + `ASSERT_KNOWN`；取值域天然不满 → 普通 `case` + `default` + 块首默认赋值。**任何一种都不能替代块首默认赋值** |
| D4 | `casez` 是否也该禁 | Cummings：casez *"use sparingly and cautiously"* ↔ Mills SNUG 2012：*"The SystemVerilog casez and casex types of case statements have an **inherent** simulation/synthesis mismatch."* → 有人据此主张 casez 也禁 | `casex` 禁；`casez` 谨慎且只用 `?`；`[SV]` 优先 `case ... inside` |
| D5 | FSM 两段式 vs 三段式 | lowRISC：*"must be implemented with two process blocks"* ↔ 教材 p.168-173 与 Cummings 的三段式 | 主规范 F1 取**三段式**（输出寄存，避免组合输出毛刺跨模块）。两段式不是错，但同一项目不要混 |
| D6 | `always @*` vs `[SV]` `always_comb` | 两者敏感表语义**真的不同**：`always_comb` 排除块内被写的变量，`@*` 不排除（IEEE 1364-2005 §9.7.5 Example 2 ↔ IEEE 1800 §9.2.2.2.1） | `[V2001]` 用 `@*`，`[SV]` 用 `always_comb`。**迁移时必须配回归仿真**，"先读后写"的代码会静默改行为 |
| D7 | `-Wall` 的 `UNUSEDSIGNAL`/`DECLFILENAME` | OpenTitan 作为硬门禁 ↔ 参数化 IP / 生成代码里噪声极大 | `-Wall` 全开 + 用 `.vlt` 按目录关掉这两条；`WIDTH`/`LATCH`/`MULTIDRIVEN`/`CASEINCOMPLETE`/`BLKSEQ`/`COMBDLY` 一律不许豁免 |

---

## ⚠️ 与主规范的冲突

**没有发现规则层面的冲突。** 本篇的每一条都是 `SKILL.md` 铁律的展开。以下三点是**执行细节的补充/待确认项**，不是推翻主规范，列出来供上层裁决：

1. **`rtl_lint.py` 的"通过"判据依赖 Verilator 的默认致命行为。** 脚本只在解析到 `%Error` 时才判失败；Verilator 默认把 warning 当致命错误（会额外打印一条 `%Error: Exiting due to N warning(s)`），所以实际效果与主规范 §2 "输出必须是 `通过 ✔`" 一致。但这层耦合是隐式的 —— **建议 CI 一律加 `--strict`**，把"告警也算失败"写死，不依赖工具默认值。

2. **主规范 §2 只示范了内联 `lint_off` 一种豁免方式**，没有提第三方 IP 的 `.vlt` 控制文件。本篇 §3 补上了，并说明它同样满足主规范"最小范围 + 写明理由"的要求（`.vlt` 支持 `-file`/`-lines` 精确定位）。这是扩展，不是修改。另注：`rtl_lint.py` 的 `--verilator-arg` **不做 Windows→WSL 路径转换**，传 `.vlt` 时请用相对路径 —— 是否要给脚本加一个专门的 `--waiver` 选项（带路径转换），请上层决定。

3. **主规范 F 节的教材引用与教材 p.329 的示例不一致（教材自身的问题，不是主规范的问题）。** 教材 p.329 `seqdet.v` 的状态寄存块用的是 `casex(state)`，而主规范 G5 明令禁止 `casex`。本篇 §1.5 已按主规范执行并注明"本规范不采纳教材这个写法"。如需在 `13-xiayuwen-source.md` 里也标注这处，请上层统一处理。

---

## 本篇检查清单

- [ ] 提交前跑了 `python3 scripts/rtl_lint.py --top <top> --synth [--strict] <files>`，输出 `通过 ✔`
- [ ] §1.1~§1.8 八组自检逐条勾完，勾不掉的没有提交
- [ ] 所有 lint 豁免都是"最小范围 + 成对 `lint_on` + 写明理由"，或集中在 `.vlt` 里；**没有任何全局 `-Wno-XXX`**
- [ ] 模块头注释写明了：target（FPGA/ASIC）、复位方式、时钟域、接口协议、CDC 说明
- [ ] 综合报告（`[FPGA]` latch/三态/Critical Warning/CDC/WNS；`[ASIC]` ELAB-974~976/clock gating）已复核
- [ ] 作为审查者：先跑工具再开口；意见落到"第 N 行改成什么"；分清"规范违反"与"个人偏好"
- [ ] 遇到 §6 表里的分歧议题，只查"是否一致 + 是否写明"，不按个人偏好判错
