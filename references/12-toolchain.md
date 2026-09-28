# 12 · 工具链命令与工程约定

> 配套主规范 `SKILL.md`。本篇不新增铁律，只回答一个问题：**"你说的这些规则，我用什么命令去验证？"**
> 标签约定同主规范：来源 `[教材]` / `[业界]` / `[工具]`，适用范围 `[通用]` / `[FPGA]` / `[ASIC]` / `[V2001]` / `[SV]`。
> 业界条目的出处编号 `W06/Sxx`、`W03/Sxx` 指向调研文件 `_research/web/W06-toolchain-commands.md`、`W03-vendor-fpga-guidelines.md` 的来源清单。

---

## 本篇速览

1. **默认入口只有一条命令**：`python3 scripts/rtl_lint.py --top <top> --synth <file>.v`。它在 Windows 上会自动经 WSL 调用 verilator/yosys，输出必须是 `通过 ✔`。
2. **Windows 编码**：脚本已对 stdout/stderr 设置 UTF-8；其他 Python 工具仍可能需要 `PYTHONIOENCODING=utf-8`。
3. **lint 的语义层永远是 `verilator --lint-only -Wall`**；风格层用 Verible/svlint；结构层用 `yosys proc+check`；三层分工，谁也替代不了谁 `[业界]` OpenTitan。
4. **豁免警告只有三种合法姿势**，优先级从高到低：改代码 > 最小范围行内 `lint_off/lint_on` > `.vlt` 控制文件。命令行 `-Wno-XXX` 一律视为审查不通过。
5. **`.f` 文件只写"可移植交集"**：源文件路径 + `+incdir+` + `+define+`。`-g2012`、`-Wall`、`--top-module` 这类工具特有 flag 放命令行，否则换个工具就报未知参数。
6. **CI 的顺序是快的在前**：format → 风格 lint → 语义 lint → 仿真 → 综合冒烟。别把 30 秒能查出来的问题留给 8 小时后的报告。
7. **Vivado 生产构建走非工程模式 Tcl**，`.xpr` 不进版本库；**时序不收敛也会出 bit 文件**，所以 `build.tcl` 里必须自己判 WNS/WHS 并 `error`。

---

## 0. 首选入口：`scripts/rtl_lint.py`

### 0.1 它是什么 `[工具]` `[通用]`

本 skill 自带的一层薄封装，把两个引擎的调用、Windows/WSL 路径转换、输出摘要合并成一条命令。优先采用项目已有入口；本脚本适合工具支持的独立 RTL（见 SKILL.md §3）。

| 引擎 | 实际执行的命令 | 查什么 | 为什么不能省 |
|---|---|---|---|
| Verilator | `--lint-only -Wall [+ -sv/--top-module/-I/+define+/waiver]` | 语法、位宽、敏感表、latch、未驱动/未使用、case 覆盖、文件名≠模块名 | 源码级、秒回、覆盖面最广 |
| Yosys | `read_verilog → hierarchy -check → proc → select -assert-none（latch 单元）→ opt -purge → check -assert → stat` | **真正被推断出来的** latch（`$dlatch`）、多驱动网、组合环，以及单元数量 | `always` 块只有在 `proc` 之后才展开成寄存器和 MUX，**latch 到这一步才现形**；纯 linter 会漏 |

`--synth` 才启用 Yosys 那一半。未加该选项时只报告 lint；若目标设计不兼容 Yosys，改用项目综合流程并说明覆盖范围。

### 0.2 用法 `[工具]` `[通用]`

Linux / macOS / WSL 内部（macOS 上**必须**是 `python3`，见 §0.3.2）：

```bash
python3 scripts/rtl_lint.py rtl/counter.v                              # 最小
python3 scripts/rtl_lint.py --top counter --synth rtl/counter.v        # 推荐默认
python3 scripts/rtl_lint.py --top fifo_sync --sv --synth rtl/fifo_sync.sv
python3 scripts/rtl_lint.py --top top --inc rtl/include --define SYNTHESIS --synth rtl/*.v
python3 scripts/rtl_lint.py --top soc_top --waiver lint/waivers.vlt --synth rtl/*.v
python3 scripts/rtl_lint.py --top counter --synth --strict rtl/counter.v   # CI 双保险
```

Windows PowerShell（脚本自动探测 WSL，**不需要**你手写 `wsl`）：

```powershell
$env:PYTHONIOENCODING = 'utf-8'      # 对其他 Python 工具可选；本脚本已设 UTF-8
python scripts\rtl_lint.py --top fsm_3seg --synth assets\templates\v2001\fsm_3seg.v
python scripts\rtl_lint.py --top fifo_sync --sv --synth --distro Ubuntu rtl\fifo_sync.sv
```

实测输出（Verilator 5.024 + Yosys 0.33，经 WSL 调用，`assets/templates/v2001/fsm_3seg.v`）：

```
[verilator --lint-only -Wall]  错误 0 / 警告 0
  lint 干净 ✔
...
No latch inferred for signal `\fsm_3seg.\next_state' ...
=== fsm_3seg ===
   Number of cells:                 11
     $adff  3   $eq  3   $logic_not  1   $mux  2   $pmux  1   $reduce_bool  1
结论: 通过 ✔
```

会读这份输出的人应该注意 `$adff 3`：三段式状态机 + 异步复位，这是 3 个寄存器单元（可能各含多位），不是 3 个触发器位；如果这里冒出 `$dlatch`，就是组合块漏了赋值。**`stat` 是最便宜的"电路和我想的一样吗"检查。**

`[工具]` **macOS 复测**（Apple Silicon，Verilator 5.050 + Yosys 0.68 原生，无 WSL）：
同一个 `fsm_3seg.v` 得到**完全相同**的 `No latch inferred` 与 `$adff 3`，结论同为「通过 ✔」。
工具版本从 5.024/0.33 跨到 5.050/0.68、平台从 WSL 换到原生 arm64，这个判据都没有漂移——
说明它依赖的是写法本身而不是某个工具版本的巧合。

### 0.3 平台实测坑与限制（Windows / macOS） `[工具]` `[通用]`

#### 0.3.1 Windows

| 现象 | 原因 | 处理 |
|---|---|---|
| 第一行就 `UnicodeEncodeError: 'charmap' codec can't encode` | 脚本打印中文，Windows Python 默认按控制台代码页（cp1252/cp936）编码 stdout | 脚本已内建 UTF-8 重配置；旧版或外部工具可设 `PYTHONIOENCODING=utf-8` |
| `找不到 verilator` | WSL 里没装 | `wsl -- sudo apt install verilator yosys` |
| 宏/include 配置 | `--inc` 和 `--define` 现已传给两个引擎 | Yosys 使用 Tcl 参数列表保留空格；需带 Tcl 支持的 Yosys 构建 |
| 想用 `.f` filelist | 脚本只接受**文件列表**，不认 `-f` | 自己展开，见下方 PowerShell 片段 |
| 想加 verilator 原生 flag | 用 `--verilator-arg=` **等号形式** | `--verilator-arg=--timing`；写成空格形式会被脚本自己的 argparse 吃掉 |

以下仅适用于**纯源文件清单**，路径需已相对当前目录。含 `+incdir+`、`+define+`、嵌套清单或空格路径时使用项目构建入口；不得静默丢弃这些选项。PowerShell 示例：

```powershell
$srcs = Get-Content rtl\rtl.f | Where-Object { $_.Trim() -ne '' -and $_ -notmatch '^\s*(//|#|\+)' }
python scripts\rtl_lint.py --top soc_top --synth $srcs
```

#### 0.3.2 macOS

`[工具]` 下表每一条都在 macOS 26.6 / Apple Silicon 上实测过。

| 现象 | 原因 | 处理 |
|---|---|---|
| `python: command not found` | **macOS 自 12.3 起不再自带 `python`**，只有 `python3` | 一律写 `python3`。本规范所有示例已统一 |
| `找不到 verilator`，但 `verilator` 明明装了 | Homebrew 装在 `/opt/homebrew/bin`（Apple Silicon）/ `/usr/local/bin`（Intel），**非登录 shell 的 PATH 里没有它**——CI、Makefile、agent 调用时正是这种情况 | 脚本已内建对这两个目录的回退搜索，无需你干预；**你自己终端里**要用则需 `~/.zprofile` 里有 `eval "$(/opt/homebrew/bin/brew shellenv)"` |
| 想照抄 0.3.1 的 `PYTHONIOENCODING` | macOS 终端默认就是 UTF-8 | **不需要**。0.3.1 那条 `UnicodeEncodeError` 是 Windows 代码页特有的，macOS 上不会发生 |
| `brew install gtkwave` 失败 | **上游已停止维护，Homebrew 于 2025-10-29 禁用了该 formula** | 改用 `brew install surfer`（VCD/FST/GHW，活跃维护），或用 Vivado/Quartus 自带波形器 |
| 找不到 Verible | **Homebrew 没有 verible formula** | 从 <https://github.com/chipsalliance/verible/releases> 下 macOS 二进制手动放进 PATH |
| Vivado / Quartus 装不上 | **这两家根本不出 macOS 版**——不是 Apple Silicon 的问题，Intel Mac 同样没有 | 只能走 Linux 虚拟机（UTM/Parallels）、远程 Linux 服务器，或另一台 PC。**§3、§4 两章在 Mac 本机不可执行** |

把 `.f` 展开成文件列表（zsh / bash，与上面 PowerShell 片段等价）：

```bash
srcs=$(grep -vE '^\s*(//|#|\+)' rtl/rtl.f | grep -vE '^\s*$')
python3 scripts/rtl_lint.py --top soc_top --synth ${=srcs}
```

（`${=srcs}` 是 zsh 的按词拆分语法；bash 里直接写 `$srcs` 即可。）

### 0.4 退出码语义 `[工具]` `[通用]`

- Verilator **默认把 warning 当致命错误**并以非零码退出（这正是官方 `-Wno-fatal` "Disable fatal exit on warnings" 存在的理由，`[业界]` W06/S1）。因此**只要有一条 warning，就不会打印 `通过 ✔`**。
- `--strict` 的意义在于：当你用 `--verilator-arg=-Wno-fatal` 摸底遗留代码时，把 warning 重新变成失败。
- Yosys 段：实际 latch 单元触发 `select -assert-none`，或 `check -assert` 返回非零，均判失败；不再根据日志关键字猜测。任何 Verilator 非零退出（包括无标准诊断的崩溃）均判失败。

### 0.5 它**不**做什么

不跑功能仿真、不查代码风格（缩进/命名/行长）、不做 CDC 结构分析、不做时序。这四件事分别归 §2/§7（仿真）、§6（风格）、§3.5（CDC）、§3.4（时序）。**"rtl_lint 过了"不等于"设计对了"。**

---

## 1. Verilator —— 语义 lint 与快速仿真

### 1.1 lint 最小命令 `[业界]` W06/S1 `[通用]`

```bash
verilator --lint-only -Wall --top-module fifo_sync -f rtl/rtl.f
```

```powershell
wsl verilator --lint-only -Wall --top-module fifo_sync -f rtl/rtl.f
```

- `--lint-only`：官方定义 "Check the files for lint violations only, do not create any other output."——不生成任何文件，秒级返回。
- `-Wall`："Enable all style warnings"。**默认不开** style 组（`DECLFILENAME`、`UNUSEDSIGNAL`、`VARHIDDEN` 等），而这几类正是模型生成代码最容易踩的。
- `--top-module` 必须显式写 `[业界]` W06/S1：filelist 里若有多个未被例化的模块，Verilator 会报多顶层错误或选错顶层，**lint 覆盖面会莫名其妙地变小而你毫无察觉**。

反例：只跑 `iverilog -o /dev/null` 就宣称"lint 通过"——iverilog 不做位宽/latch/多驱动检查。

### 1.2 `-Wno-fatal`：门禁不加，摸底才加 `[业界]` W06/S1 `[通用]`

```bash
verilator --lint-only -Wall -f rtl/rtl.f                    # 门禁：有 warning ⇒ exit != 0
verilator --lint-only -Wall -Wno-fatal -f rtl/rtl.f | tee lint.log   # 摸底：一次看全
```

`-Wno-fatal` 只改退出行为，不改是否打印。**CI 里出现它 = 门禁形同虚设。**

### 1.3 高频 warning 与正确修法 `[业界]` W06/S2（引号内为官方原文）`[通用]`

**修法一栏写的是"改代码"，不是"关警告"**——这张表里没有一条应该用 `lint_off` 解决。

| 代码 | 官方含义 | 典型成因 | 正确修法 | 对应铁律 |
|---|---|---|---|---|
| `WIDTHTRUNC` | "a value is truncated" | 大赋小，高位被丢 | 显式 part-select `x[7:0]`，表明"我知道在截位" | G3 |
| `WIDTHEXPAND` | "a value is zero expanded" | 小赋大 | 显式 `{{4{1'b0}}, x}` 或位宽化字面量 | G1/G3 |
| `WIDTHCONCAT` | "a concatenate or replication has an indeterminate width" | 拼接里放了裸 `1` | 所有拼接元素写定宽 `1'b1` | G1 |
| `LATCH` | "a signal is not assigned in all control paths of a combinational always block, resulting in latch inference" | `if` 无 `else` / `case` 无 `default` | **块首赋默认值**（SKILL.md §C 的标准手法） | C3/C4 |
| `CASEINCOMPLETE` | "there is a stimulus pattern for which no case item is provided" | 没写 `default` | 加 `default:` | C4/F4 |
| `CASEX` | "it is better style to use casez with '?' instead of 'x'" | 用了 `casex` | 本规范直接禁 `casex` | G5 |
| `BLKSEQ` | "blocking assignment (=) is used in a sequential block" | 时序块里写了 `=` | 改 `<=` | D1 |
| `COMBDLY` | "there is a delayed assignment inside of a combinatorial block" | 组合块里写了 `<=` | 改 `=` | C1 |
| `MULTIDRIVEN` | "the specified signal has multiple procedural drivers" | 同一变量被两个 always 赋值 | 合并到一个 always 块 | D3 |
| `SYNCASYNCNET` | "a net is used in multiple always statements with posedge/negedges, mixing sync and async resets" | 同一根复位既同步又异步 | 统一复位风格 | E2 |
| `UNOPTFLAT` | "optimization of the specified signal is disabled"；官方补充这常常"isn't truly circular as viewed by synthesis, which analyzes interconnection per bit, but is circular to the IEEE event model which analyzes per-signal" | 同一向量不同 bit 互相驱动，如 `wire [2:0] x = {x[1:0], shift_in};` | ①拆成两个信号 ②`/*verilator split_var*/` ③`--report-unoptflat` 让工具推荐拆分点 | C5 |
| `IMPLICIT` | "a wire is implicitly declared from a sub-module output" | 忘了声明 | 加 `` `default_nettype none `` 让它变成编译错误 | A3 |
| `DECLFILENAME` | "a module name doesn't match the filename" | 一文件多模块 | 一文件一模块、同名 | A1/A2 |
| `PINMISSING` / `PINCONNECTEMPTY` | 例化端口漏连 / 显式接空 | 例化不全 | 补全；**有意悬空就写 `.pin()`**，让"刻意"可见 | H1 |
| `ALWCOMBORDER` | "an always_comb block reads a variable before assigning it later in the same block" | 组合块内先读后写 | 调整顺序：先写后读 | C5 |
| `UNUSEDSIGNAL` / `UNDRIVEN` | 信号无消费者 / 无驱动 | 端口留着没用 | 删掉，或按官方提示用含 `unused` 的命名标注 | — |
| `SELRANGE` | "a selection index will go out of bounds" | 常量下标越界 | 修下标或参数化 | G3 |

`DECLFILENAME` 不是纯风格问题：`-y <dir>` + `+libext+` 的库搜索、Verible 的 `module-filename`、Vivado 的 `-y` 搜索**都按"文件名 = 模块名"工作**，不一致会让某些工具找不到模块。这就是铁律 A2 的工具侧理由。

### 1.4 `lint_off` 的三种作用域 `[业界]` W06/S2、S3 `[通用]`

**作用域从窄到宽，推荐度从高到低：**

**(a) 行内元注释**——最小范围包住那一行，旁边写清理由：

```verilog
// 注：ROM 地址高位恒零，截位已人工确认（2026-08-12, reviewer: xxx）
/* verilator lint_off WIDTHTRUNC */
assign rom_addr = base_addr + offset;
/* verilator lint_on WIDTHTRUNC */
```

⚠️ **官方明确的传播规则**："A lint_off in the design source code will propagate down to any child files (files later included by the file with the lint_off), but will not propagate upwards to any parent file."
两个直接后果：
- 写在**头文件顶部**的 `lint_off WIDTH` 会静默关掉整棵 `` `include `` 树的位宽检查；
- **忘写 `lint_on` == 从该点到文件末尾（及所有 include）全关**。

反例（不要抄）：

```verilog
/* verilator lint_off WIDTH */   // 文件第 1 行，再也没有 lint_on —— 整个文件 + 所有 include 全瞎
```

**(b) `.vlt` 控制文件**——第三方 IP / 生成代码不可改源码时用，保持源码零污染：

```
`verilator_config

// ---- 第三方 IP：不改源码，集中豁免 ----
lint_off -rule WIDTH        -file "*/vendor/*"
lint_off -rule DECLFILENAME -file "*/vendor/*"

// ---- 本项目：精确到文件/行 + 写清理由 ----
lint_off -rule WIDTHTRUNC -file "*/rtl/rom_ctrl.sv" -lines 42

tracing_off -file "*/vendor/*"
```

- 首行必须是 `` `verilator_config ``；文件会过预处理器，支持 `` `ifdef ``/`` `define ``/注释。
- **顺序要求（官方原文）**："Control files should be passed as the first file to Verilator, as file/line-specific directives apply only to subsequently-read files." → `verilator --lint-only -Wall waivers.vlt -f rtl/rtl.f`。`rtl_lint.py --waiver` 已经替你放在源文件之前。
- `lint_off` 参数：`-rule` / `-file`（支持 `*`/`?` 通配）/ `-lines` / `-contents` / `-match`。另有 `coverage_off`、`tracing_off`、`public`、`hier_block`、`timing_on/off`。
- 优先级（官方）："global rules first, then file-specific rules, then `--match` rules, all processed in parse order."，且"Metacomments and control file directives do not interact."——**行内注释和 `.vlt` 是两套独立机制，不要指望互相覆盖**。

**(c) 命令行 `-Wno-<code>`**——官方自己给出的缺点是它"removes all checking across the source files, and prevents other users from compiling the sources without knowing the magic set of disables needed."
**本规范据此禁止**（与 SKILL.md §2 一致）：CI 与提交命令里出现 `-Wno-XXX`，审查直接不通过。

接手遗留代码的正确姿势：`--waiver-output waivers.vlt` 生成基线 → **逐条 review，把真 bug 那些删掉** → 剩下的固化为基线，此后禁止新增 `[业界]` W06/S1。（`--waiver-output` 在本地 Verilator 5.024 上确认存在，`[工具]`。）

### 1.5 用 Verilator 跑仿真 `[业界]` W06/S1、S5 `[通用]`

```bash
# A. 纯 SV testbench（含 #10 / @(posedge clk) / wait / fork-join）
verilator --binary -j 0 -Wall --top-module tb_fifo_sync -f rtl/rtl.f tb/tb_fifo_sync.sv
./obj_dir/Vtb_fifo_sync

# B. C++ testbench
verilator --cc --exe --build -j 0 -Wall sim_main.cpp our.v
obj_dir/Vour
```

- `--binary` 官方定义就是 `--main --exe --build --timing` 的别名。**`--timing` 是关键**：不加它，延时语句会像综合一样被直接忽略，只报一条 `STMTDLY` warning——你的 testbench 会"跑完了但什么都没发生"。
- `-j 0` 是"用满可用核"，**不是"不并行"**。
- 输出目录默认 `obj_dir`，用 `--Mdir` 改。

### 1.6 波形：版本差异要当心 `[工具]` `[业界]` W06/S1、S8 `[通用]`

- Verilator **5.050 文档**：`--trace` 已废弃，改用 `--trace-fst` / `--trace-vcd` / `--trace-saif`。
- **本地实测 Verilator 5.024**：`verilator --help` 里有 `--trace`（VCD）与 `--trace-fst`，**没有 `--trace-vcd`**。
  → **结论：`--trace-fst` 是跨版本最安全的写法**；脚本里不要硬写 `--trace-vcd`，除非锁定了 ≥5.03x。这是"文档版本 ≠ 你装的版本"的典型例子，**任何 flag 拿不准就先 `verilator --help | grep <flag>`**。
- 波形开关写在 TB 里，用 plusarg 控制，默认关闭：

```systemverilog
initial begin
    if ($test$plusargs("trace")) begin
        $dumpfile("build/sim/wave.fst");
        $dumpvars(0, tb_top);      // 0 = 全层级
    end
end
```

```bash
verilator --binary --trace-fst -Wall -f rtl/rtl.f tb/tb_top.sv
./obj_dir/Vtb_top +trace
```

大设计再加 `--trace-depth N` 和 `/*verilator tracing_off*/`。
反例：无条件 `$dumpvars(0, tb_top)` + VCD 跑百万周期回归 → 几十 GB 波形，磁盘先死。

#### 1.6.1 用什么看波形 `[工具]`

| 平台 | 查看器 | 说明 |
|---|---|---|
| Linux / WSL | GTKWave | 传统默认；WSL 下需要 WSLg 或 X server |
| **macOS** | **Surfer** (`brew install surfer`) | **GTKWave 在 Mac 上装不了**——上游停止维护，Homebrew 于 2025-10-29 禁用了该 formula。Surfer 是活跃维护的原生替代，VCD / FST / GHW 全支持 |
| 任意 | Vivado / Quartus 自带 | 已经在跑厂商流程时最省事 |

`[工具]` **macOS 实测**（2026-08-30，Surfer 0.7.0）：用本 skill 自带的
`assets/templates/v2001/tb_fsm_3seg.v` 跑完整链路——

```bash
# 1) 编译 + 跑仿真（TB 里已有 $dumpfile/$dumpvars，产出 tb_fsm_3seg.vcd）
iverilog -g2012 -Wall -s tb_fsm_3seg -o sim.vvp \
         assets/templates/v2001/fsm_3seg.v assets/templates/v2001/tb_fsm_3seg.v
vvp -N sim.vvp                      # → checks run : 8 / failures : 0 / TEST PASSED

# 2) 开波形
surfer tb_fsm_3seg.vcd
```

**Surfer 相对 GTKWave 的一个实用差异**：它会 **watch 波形文件**，仿真重跑、文件被覆盖后
**自动重新加载**，不用手动 File→Reload。改 RTL → 重跑 → 直接看新波形，循环更快。

想脚本化摆信号（相当于 GTKWave 的 `.gtkw` save file）：

```bash
surfer -c waves.cmd tb_fsm_3seg.vcd     # 命令文件，一行一条
surfer -s saved.ron  tb_fsm_3seg.vcd    # 或加载之前保存的界面状态
```

长仿真用 FST 而不是 VCD（大设计上体积差一个数量级；上面这个几百周期的小 TB 两者都才 1.2 KB，看不出差别）。
**注意 `-fst` 的位置**——它是 vvp 的**扩展参数，必须写在 `.vvp` 文件后面**，写在前面会被当成普通选项而报错，见 §2.2。

### 1.7 断言、覆盖率与性能 flag 不要混用 `[业界]` W06/S1、S6 `[通用]`

| 目的 | flag |
|---|---|
| 功能验证 | `--assert --coverage`（`--coverage` = line + toggle + expr） |
| 性能基准 | `-O3 --x-assign fast --x-initial fast --no-assert` |

理由：assert/coverage 埋点显著拖慢仿真；而性能 flag **会破坏 X 语义与断言语义**——用它跑功能回归等于自欺。
注：官方称 `--assert` 自 v5.038 起默认开启（此版本号 W06 标注未能二次定位到原文位置）。**本地是 5.024，所以要显式写 `--assert`** `[工具]`。

### 1.8 Verilator 的能力边界——别用它下错结论 `[业界]` W06/S4 `[通用]`

- **"Verilator is mostly a two-state simulator, not a four-state simulator."** → **复位前 X 传播、`casex`/`casez` 的 X 语义安全性，Verilator 给不出可靠答案**。要验 X 必须用四态仿真器（iverilog 粗筛，VCS/Questa/Xcelium 签核）。这对 `[ASIC]` 门级验证尤其关键。
- "All specify blocks and timing checks are ignored."
- class 支持有限，约束随机、完整 class-based UVM 不要指望它。
- 反过来说：**Verilator 是最严格的可综合子集守门员**——能过它 lint 的代码通常也能过综合器。这就是本规范把它设为硬门禁的理由。

### 1.9 平台说明（Windows / macOS） `[业界]` W06/S9 `[通用]`

官方主测平台是 Ubuntu，另在 macOS/FreeBSD/MSVC 上测试；WSL2、Cygwin、MinGW 亦可构建。

**Windows：走 WSL2**，路径写 `/mnt/d/...`，或直接把工程放进 WSL 文件系统（跨文件系统 IO 慢是实打实的）。`rtl_lint.py` 已经内建了 `wsl --` 调用与 `D:\x` → `/mnt/d/x` 的路径翻译，**这是它在 Windows 上作为首选入口的主要价值**。

**macOS：全部原生，不需要虚拟机。**

```bash
brew install verilator yosys icarus-verilog
```

`[工具]` 本机实测（macOS 26.6，Apple Silicon）：Verilator 5.050 + Yosys 0.68 + Icarus 13.0，
对 `assets/templates/v2001/sync_2ff.v` 跑 `--synth` 全程通过，与 Linux 下行为一致。
Mac 上**没有** WSL 那一层，`--distro` 参数无意义（会被忽略）。

需要注意的是开源流在 Mac 上是完整的，**厂商流不是**：Vivado 与 Quartus 都不提供 macOS 版本，
§3 / §4 两章只能在 Linux/Windows 上执行（见 §0.3.2）。

---

## 2. Icarus Verilog —— 四态仿真的最低成本入口

Verilator 查不了 X 传播（§1.8），iverilog 是最便宜的四态补位。

### 2.1 必须显式指定语言版本 `[业界]` W06/S11 `[SV]`

iverilog **默认是 `-g2005`**。写 SystemVerilog 不加 `-g2012` 会在 `logic`、`always_ff`、`typedef struct` 处直接报语法错误——这个错误很容易被误读成"我的代码写错了"。

```bash
iverilog -g2012 -Wall -Winfloop -s tb_top -o build/sim.vvp -c rtl/rtl.f tb/tb_top.sv
vvp -N build/sim.vvp -fst +trace
```

```powershell
# MSYS2 安装的 iverilog
iverilog.exe -g2012 -Wall -Winfloop -s tb_top -o build\sim.vvp -c rtl\rtl.f tb\tb_top.sv
vvp.exe -N build\sim.vvp -fst +trace
& "C:\msys64\mingw64\bin\gtkwave.exe" build\wave.fst
```

### 2.2 三个容易漏的 flag `[业界]` W06/S11、S13 `[通用]`

| flag | 官方语义 | 为什么必须写 |
|---|---|---|
| `-s <top>` | "Specifies the root module for elaboration instead of auto-detecting" | 同 `--top-module` 的理由：自动推断会选错根，导致跑的不是你以为的那个设计 |
| `-Winfloop` | `-Wall` 官方描述是 "Enables most warnings **except infloop**" | 零延时无限循环是 testbench 最常见的挂死原因，而 `-Wall` 不管它 |
| `vvp -N` | "returns exit code 1 if simulation calls `$stop`" | **CI 的生死线**：不加 `-N`，断言失败调 `$stop` 时进程照样返回 0，回归"全绿"但其实全错 |

`vvp` 默认写 VCD，`-fst` 切 FST（体积小、GTKWave/Surfer 直读），`-none` 关闭 dump。

⚠️ `[工具]` **`-fst` 必须放在 `.vvp` 文件之后**，它是 vvp 的*扩展参数*不是普通选项：

```bash
vvp -N sim.vvp -fst      # ✅ 对
vvp -N -fst sim.vvp      # ❌ vvp: illegal option -- f  → 仿真直接不跑，波形一个都没有
```

`vvp --help` 的 Usage 行 `vvp [options] input-file [+plusargs...]` 里并没有列出 `-fst`，
正是因为它属于文件后面那一段。**实测于 Icarus 13.0 / macOS**，这条在 Linux 上同样成立。

另外 FST 只决定**格式**，不决定**文件名**——文件名由 TB 里的 `$dumpfile` 决定。
两者不一致时会出现"名字叫 `.vcd`、内容其实是 FST"的别扭结果，所以 `$dumpfile` 也要写成 `.fst`：

```systemverilog
$dumpfile("build/sim/wave.fst");   // 与 vvp 的 -fst 配套
```
**macOS 上只有 Surfer 这一个选项**——GTKWave 上游已停更，Homebrew 于 2025-10-29 禁用了它（见 §0.3.2），`brew install surfer` 即可，FST/VCD 都直读。

### 2.3 cmdfile 与 Verilator `.f` 不是一回事 `[业界]` W06/S12 `[通用]`

- iverilog 用 `-c <cmdfile>`；文件里支持 `#` / `//` / `/* */` 注释、`-y <dir>`、`-v`、`+libext+`、`+incdir+`、`+define+name=value`、`+timescale+`、`+parameter+`，以及 `$(NAME)` 环境变量替换。
- Verilator 的 `-f` 文件可以放**任意命令行参数**；iverilog 的 cmdfile **只接受上面那几类**。
- **实践结论（也就是 §8.2 的 filelist 约定）**：同一份 `.f` 想同时喂给 Verilator 和 iverilog，就只能写"纯文件名 + `+incdir+` + `+define+`"这个交集。在 `.f` 里写 `-g2012`，Verilator 会报未知参数。
- 注：W06 明确标注"iverilog cmdfile 不接受普通 flag"这一条是**从官方指令白名单推断**的，官方没有一句显式禁止；首次接入项目时请本地实测一次。

---

## 3. Vivado —— 非工程模式 Tcl + XSim `[FPGA]`（AMD/Xilinx）

### 3.1 为什么是非工程模式 `[业界]` W06/S15 UG892 `[FPGA]`

UG892 原话解释了机理：`read_*` 系列命令"allows a file on the disk to be read by the Vivado Design Suite to build an in-memory design database, **without copying the file or creating a dependency on the file in any way, as it would in Project mode**."

- **非工程模式**：构建是纯函数式的——输入是源码 + 约束 + 脚本，输出是 checkpoint + 报告 + bit。可复现、可 review、可 CI。
- **工程模式**：`.xpr` 含绝对路径与 GUI 状态，多人协作必冲突。

**本规范默认**：`build.tcl` 进版本库；`.xpr` / `.runs/` / `.cache/` / `.Xil/` 进 `.gitignore`。（分歧见 §10.3。）

### 3.2 `build.tcl` 模板（结构照 UG892 官方脚本，补时序门禁与 CDC 报告）

```tcl
# syn/build.tcl  —— vivado -mode batch -source syn/build.tcl
set root      [file normalize [file dirname [info script]]/..]
set outputDir $root/build/syn
set repDir    $root/build/reports
file mkdir $outputDir $repDir

set TOP  soc_top
set PART xc7a100tcsg324-1

# ---- 消息严格化（ID 随版本变化，见 3.6，务必先在本地日志确认）----
# set_msg_config -id {Synth 8-327}  -new_severity ERROR   ;# inferred latch
# set_msg_config -id {Synth 8-3331} -limit 10             ;# 限流而不是抑制

# STEP 1: 读源（read_* 不复制文件）
read_verilog -sv [glob $root/rtl/pkg/*.sv $root/rtl/*.sv]
read_xdc     [glob $root/constr/*.xdc]

# STEP 2: 综合
synth_design -top $TOP -part $PART \
             -include_dirs [list $root/rtl/include] \
             -verilog_define SYNTHESIS \
             -flatten_hierarchy rebuilt
write_checkpoint -force  $outputDir/post_synth.dcp
report_timing_summary    -file $repDir/post_synth_timing_summary.rpt
report_utilization       -file $repDir/post_synth_util.rpt
report_cdc -details      -file $repDir/post_synth_cdc.rpt
report_clock_interaction -delay_type min_max -file $repDir/post_synth_clk_interaction.rpt

# STEP 3: 优化 + 布局
opt_design
place_design
phys_opt_design
write_checkpoint -force $outputDir/post_place.dcp
report_timing_summary   -file $repDir/post_place_timing_summary.rpt

# STEP 4: 布线 + 报告
route_design
write_checkpoint -force $outputDir/post_route.dcp
report_timing_summary -file $repDir/post_route_timing_summary.rpt
report_utilization    -file $repDir/post_route_util.rpt
report_drc            -file $repDir/post_route_drc.rpt

# STEP 5: 时序门禁 —— 不收敛就让构建失败
set wns [get_property SLACK [get_timing_paths -delay_type max]]
set whs [get_property SLACK [get_timing_paths -delay_type min]]
puts "== WNS=$wns  WHS=$whs =="
if {$wns < 0 || $whs < 0} { error "TIMING NOT MET: WNS=$wns WHS=$whs" }

# STEP 6: 比特流
write_bitstream -force $outputDir/$TOP.bit
```

**STEP 5 不是可选项**：Vivado **时序不满足照样会生成 bit 文件**。只看 `write_bitstream` 是否成功，等于没做时序检查。

调用方式：

```bash
vivado -mode batch -source syn/build.tcl -log build/vivado.log -journal build/vivado.jou
```

```powershell
& "C:\Xilinx\Vivado\2024.1\bin\vivado.bat" -mode batch -source syn\build.tcl `
    -log build\vivado.log -journal build\vivado.jou
```

`-mode batch` 跑完自动退出（CI 用）；`-mode tcl` 跑完停在 Tcl shell（交互调试用）`[业界]` W06/S18 UG893。
注：`-tclargs` 在 W06 中标注**未从可访问的官方页面逐字确认**，需要传参时请本地验证。

### 3.3 `synth_design` 关键选项 `[业界]` W06/S16 UG835 `[FPGA]`

| 选项 | 说明 |
|---|---|
| `-top` / `-part` | **必写**，没有可依赖的默认值 |
| `-verilog_define NAME=VALUE` | RTL 宏（对应 Verilator 的 `+define+`） |
| `-include_dirs` | `` `include `` 搜索路径 |
| `-generic` | 覆盖 parameter/generic |
| `-mode out_of_context` | 模块级综合，不插 IO buffer；子模块/IP 单独出 checkpoint 时用 |
| `-flatten_hierarchy` | `none` 保层次、利于 debug/ILA，跨层优化受限；`full` 优化空间最大但报告里没有原始层次；`rebuilt` 折中 |
| `-assert` | **官方定义是 "Enable VHDL assert statements"**——见下 |

⚠️ **`-assert` 的常见误读** `[业界]` W06/§3.10：中文资料常把它说成"开启 SystemVerilog 断言综合"，这是错的。SV 的 `assert property` 在 Vivado 综合中的处理与此 flag 无关。**SV 断言请用 `` `ifndef SYNTHESIS `` 包住**，靠仿真/形式验证保证。
注：`-flatten_hierarchy` 的取值 `rebuilt`（GUI 默认）W06 标注**未从官方页面逐字确认**（只确认了 `full`/`none`）。若报错就改 `none`。

### 3.4 报告：每一步都出，最低要求两份 `[业界]` W06/S15、S20 `[FPGA]`

综合后 / 布局后 / 布线后各一份 `report_timing_summary` + `report_utilization`，落到 `build/reports/` 并由 CI 归档。UG906 原话："Review this report or the messages tab for Errors, Critical Warnings and Warnings"，且"The Synthesis tool can issue Critical Warnings and Warnings that become more serious later in the flow."

### 3.5 CDC 必须跑 `report_cdc`，且它**不给时序数字** `[业界]` W06/S19 UG949 `[FPGA]`

- 它做的是"**structural analysis** of the clock domain crossings"，用于找出可能导致 metastability 或数据不一致的不安全跨域结构。
- **关键限制（官方原文）**："Report CDC does not provide timing information because timing slack does not make sense on paths that cross asynchronous clock domains."
- → **推论（本节重点）**：CDC 问题**永远不会**体现在 timing slack 上。**时序报告全绿 ≠ 跨时钟域安全。** 这正是铁律 E6 必须靠结构（同步器/异步 FIFO/握手）而不是靠约束去保证的原因。
- 每条 Critical 都要有结论：要么改成标准两级同步器 / 异步 FIFO（`assets/templates/v2001/sync_2ff.v`、`async_fifo.v`），要么写 waiver 说明为什么安全。
- `[ASIC]` 对应工具是 SpyGlass CDC / Questa CDC / Conformal CDC，机理相同。
- 注：CDC 规则 ID（CDC-1 / CDC-4 …）W06 标注**未从官方页面取到列表**，不要照抄具体 ID。

### 3.6 `set_msg_config`：升级、限流，不要一把梭抑制 `[业界]` W06/S21 UG835 `[FPGA]`

合法严重级别：`INFO` / `STATUS` / `WARNING` / `CRITICAL WARNING` / `ERROR`；选项 `-id` / `-string` / `-severity` / `-new_severity` / `-limit` / `-suppress`。

```tcl
set_msg_config -id {Synth 8-327}  -new_severity ERROR   ;# 把 inferred latch 直接升成错误
set_msg_config -id {Synth 8-3331} -limit 10             ;# 已确认无害的第三方 IP 消息，限流
```

- 规则：**其余 Critical Warning 视为构建失败**；`-suppress` 只用于逐条确认过的具体 ID，不用于整类消息。
- ⚠️ 具体消息 ID **随 Vivado 版本变化**，W06 明确标注这些 ID 来自社区实践、无官方来源。写进 `build.tcl` 前必须先在本地日志里确认。

### 3.7 XSim 三步 `[业界]` W06/S17 UG900 `[FPGA]`

```bash
mkdir -p build/xsim && cd build/xsim
xvlog -sv -i ../../rtl/include -f ../../rtl/rtl.f -log xvlog_rtl.log
xvlog -sv ../../tb/tb_soc_top.sv                  -log xvlog_tb.log
xelab -debug typical -s tb_snap -timescale 1ns/1ps tb_soc_top -log xelab.log
xsim  tb_snap -R -log xsim.log
```

```powershell
New-Item -ItemType Directory -Force build\xsim | Out-Null
Push-Location build\xsim
xvlog.bat -sv -i ..\..\rtl\include -f ..\..\rtl\rtl.f -log xvlog_rtl.log
xvlog.bat -sv ..\..\tb\tb_soc_top.sv                  -log xvlog_tb.log
xelab.bat -debug typical -s tb_snap -timescale 1ns/1ps tb_soc_top -log xelab.log
xsim.bat  tb_snap -R -log xsim.log
Pop-Location
```

要点：SV 必须 `-sv`；`-d NAME=VAL` 定义宏（xelab）；`-s` 指定 snapshot 名；`-R` 一路跑到底；`-timescale` 默认 `1ns/1ps`；`-debug` 取值 `typical/line/wave/xlibs/off/all`。

---

## 4. Quartus `[FPGA]`（Intel/Altera）—— 全节标注「需本地二次核对」

> ⚠️ **W06 如实记录：Intel/Altera 文档站本轮抓取全部返回 HTTP 403**（`intel.com`、`altera.com`、`cdrdv2-public.intel.com` 三个域）。本节内容来自检索摘要与通行工程实践，**未逐字对照官方页面**。使用前请用本地 `quartus_sh --qhelp` 或本地安装的 PDF 复核。**转抄本节时不要删掉这个标注。**

四个可执行文件对应四个阶段（Pro Edition）：`quartus_syn`（Analysis & Synthesis）→ `quartus_fit`（Fitter）→ `quartus_asm`（Assembler）→ `quartus_sta`（Timing Analyzer）。Standard Edition 的综合可执行文件是 `quartus_map`。

```bash
quartus_sh --flow compile my_proj          # 一条命令跑完
# 或分步（便于单步重跑与定位）
quartus_syn my_proj && quartus_fit my_proj && quartus_asm my_proj && quartus_sta my_proj
```

```powershell
& "C:\intelFPGA_pro\24.1\quartus\bin64\quartus_sh.exe" --flow compile my_proj
```

`.qsf` 是纯 `set_global_assignment` 列表，**可以手写并进版本库**（`.qpf` 只是工程壳）：

```tcl
# my_proj.qsf  —— [需本地二次核对] assignment 名称
set_global_assignment -name FAMILY "Cyclone V"
set_global_assignment -name DEVICE 5CSEMA5F31C6
set_global_assignment -name TOP_LEVEL_ENTITY soc_top
set_global_assignment -name SYSTEMVERILOG_FILE rtl/pkg/soc_pkg.sv
set_global_assignment -name SYSTEMVERILOG_FILE rtl/soc_top.sv
set_global_assignment -name SEARCH_PATH rtl/include
set_global_assignment -name SDC_FILE constr/soc_top.sdc
set_location_assignment PIN_AF14 -to clk
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to clk
```

`[FPGA]` 跨厂商提醒：Intel 与 AMD 在**二级控制信号优先级上语义相反**（Intel 硬件顺序 `aclr > aload > ena > sclr > sload > data`；AMD 要求 RTL 里 set/reset 写在 enable 之前）`[业界]` W03/R-W03-12、R-W03-13。**同一份 RTL 换厂商时，`if/else` 的嵌套顺序可能需要改**——这不是工具链问题，但只有把两家的工具链都跑一遍才会暴露。详见 `references/06-clock-reset-cdc.md`。

---

## 5. Yosys —— 结构冒烟与资源估算 `[通用]`（开源流）

### 5.1 命令与顺序 `[业界]` W06/S29、S31 `[工具]`

```tcl
# syn/smoke.ys —— yosys -s syn/smoke.ys -l build/syn/yosys.log
read_verilog -sv -I rtl/include rtl/pkg/soc_pkg.sv rtl/fifo_sync.sv rtl/soc_top.sv
hierarchy -check -top soc_top
proc
opt -purge
check -assert
stat
write_verilog -noattr build/syn/soc_top_gate.v
```

- **`hierarchy` 必须是加载设计后的第一条命令**（官方原话："`hierarchy` should always be the first command after loading a design"）——用于解析层次与参数化实例；`-defer` 是可选参数，不是默认值。
- `read_verilog` **自动定义宏 `SYNTHESIS`**（`-formal` 时改为 `FORMAL`），并且**永远定义 `YOSYS`**。这与 Vivado/DC 的习惯一致，所以 `` `ifndef SYNTHESIS `` 包住的仿真代码在 Yosys 下同样被排除。
- `proc` 把 `always` 展开成寄存器/MUX；**latch 只有在这一步之后才现形**——这是 `rtl_lint.py --synth` 存在的全部理由。
- `stat` 给单元统计：`$adff`/`$dff` 是向量单元，需结合 WIDTH 参数核对寄存器位数；出现 `$dlatch` 就是组合块漏赋值；出现意外的 `$mem` 说明被推断成了存储器。

`[工具]` 实测（Yosys 0.33，`assets/templates/v2001/fsm_3seg.v`）：`proc` 阶段打印 `No latch inferred for signal '\next_state'`，`stat` 给出 `$adff 3 / $eq 3 / $mux 2 / $pmux 1`——三段式 FSM 的状态寄存器 + 输出寄存器，与手算一致。**这一行 `No latch inferred` 就是三段式写法值不值的直接证据。**

### 5.2 定位与边界 `[工具]` `[通用]`

Yosys 用于**快速可综合性冒烟 + 资源量级估算**，**不是** FPGA/ASIC 产品级综合的替代品（除非走 nextpnr / OpenLane 全开源流）。
**Yosys 对 SystemVerilog 的支持远小于 Verilator**：SV interface、复杂 package、部分 `typedef` 会直接失败。此时正确做法是 **Verilator 做 lint、Yosys 只对能读进去的子模块做冒烟**，而不是为了迁就 Yosys 去改 RTL 风格。

---

## 6. 风格 lint：Verible / svlint `[SV]`

Verilator 管**语义**（位宽/latch/多驱动），Verible/svlint 管**风格**（命名/缩进/行长/语法构造）。两者**互补不重复**——OpenTitan 就是这么分工的 `[业界]` W06/S34。二选一即可，不必都上。

### 6.1 Verible `[业界]` W06/S24、S25、S27 `[SV]`

```bash
verible-verilog-lint --rules_config_search --lint_fatal --parse_fatal rtl/*.sv
verible-verilog-format --verify --failsafe_success=false rtl/*.sv   # CI：只检查
verible-verilog-format --inplace --column_limit=100 rtl/*.sv        # 本地：原地改
```

```powershell
Get-ChildItem rtl -Filter *.sv -Recurse | ForEach-Object {
  verible-verilog-lint.exe --rules_config_search --lint_fatal --parse_fatal $_.FullName
}
```

**两个必须记住的坑**：
1. `verible-verilog-format` 的 `--failsafe_success` **默认是 true**——出错也返回 0。CI 里不加 `--failsafe_success=false`，格式检查等于没做。
2. `--lint_fatal` / `--parse_fatal` 不加则违规也返回 0。

行内豁免语法（与 Verilator 的完全不同，别混）：`// verilog_lint: waive rule-name`，区间用 `waive-start` / `waive-stop`；关闭格式化用 `// verilog_format: off` … `// verilog_format: on`（官方建议附上理由）。

与本规范直接对应的规则，放仓库根 `.rules.verible_lint` + `--rules_config_search`：

```
line-length=length:100
no-tabs
no-trailing-spaces
module-filename            # 对应铁律 A2 / Verilator DECLFILENAME
always-comb                # 对应 C2
always-ff-non-blocking     # 对应 D1 / Verilator BLKSEQ
case-missing-default       # 对应 C4/F4
explicit-parameter-storage-type
packed-dimensions-range-ordering
undersized-binary-literal  # 对应 G1
generate-label
typedef-structs-unions
-port-name-suffix          # 前缀 '-' 表示本项目不强制
```

注：`--rules_config_search` 的拼写在 W06 中标注**可能存在单/复数版本差异**，首次使用先 `verible-verilog-lint --help` 确认。

### 6.2 svlint `[业界]` W06/S28 `[SV]`

强项是**能直接禁掉具体语法构造**，适合强制"只写现代 SV"：

```toml
# .svlint.toml（层级向上搜索）
[option]
exclude_paths = ["vendor/.*", "build/.*"]
prefix_input = "i_"
prefix_output = "o_"

[syntaxrules]
module_nonansi_forbidden               = true   # 禁非 ANSI 端口列表
keyword_forbidden_wire_reg             = true   # 禁 wire/reg，只用 logic
case_default                           = true
blocking_assignment_in_always_ff       = true
non_blocking_assignment_in_always_comb = true
```

```bash
svlint -f rtl/rtl.f          # 注意：-f 与直接列文件不能混用
```

⚠️ `keyword_forbidden_wire_reg` 只适用于**纯 SV 项目**。本规范默认基线是 Verilog-2001，`[V2001]` 代码开这条规则会全线报错——**开之前先确认项目基线**。

---

## 7. cocotb —— Python testbench `[业界]` W06/S32、S33 `[通用]`

新工程用 **Python runner**（`cocotb_tools.runner`），跨平台、Windows 上不依赖 GNU make：

```python
# dv/test_runner.py
import os
from pathlib import Path
from cocotb_tools.runner import get_runner

PROJ = Path(__file__).resolve().parents[1]

def test_fifo_sync():
    sim = os.getenv("SIM", "icarus")
    sources = [PROJ / "rtl" / "fifo_sync.v"]
    build_args = ["-g2012"] if sim == "icarus" else ["--trace-fst", "-Wall"]
    runner = get_runner(sim)
    runner.build(sources=sources, hdl_toplevel="fifo_sync",
                 includes=[PROJ / "rtl" / "include"],
                 build_args=build_args, always=True)
    runner.test(hdl_toplevel="fifo_sync", test_module="test_fifo_sync")

if __name__ == "__main__":
    test_fifo_sync()
```

```bash
SIM=icarus python dv/test_runner.py
```
```powershell
$env:SIM='icarus'; python dv\test_runner.py
```

Makefile 方式的关键变量：`SIM` / `TOPLEVEL_LANG` / `VERILOG_SOURCES` / `COCOTB_TOPLEVEL` / `COCOTB_TEST_MODULES` / `COMPILE_ARGS`（编译阶段）/ `SIM_ARGS`（运行阶段）/ `EXTRA_ARGS`（两阶段都传）/ `WAVES`，末尾 `include $(shell cocotb-config --makefiles)/Makefile.sim`。

⚠️ **变量名有版本差异**：W06 记录 Quickstart 用 `COCOTB_TOPLEVEL` / `COCOTB_TEST_MODULES`，而 Build options 页没有列出这两项，**旧版用 `TOPLEVEL` / `MODULE`**。以你安装的版本的文档为准，或直接用 Python runner 绕开变量名问题。

---

## 8. 工程约定

### 8.1 目录结构 `[业界]` W06/S34、S35、S37（OpenTitan / lowRISC Ibex）`[通用]`

```
<project>/
  rtl/            可综合 RTL，一文件一模块（铁律 A1/A2）
    include/      `include 头文件（.vh/.svh）
    pkg/          SV package
    rtl.f         只含可综合源的 filelist
  tb/  tb.f       testbench（不可综合）
  dv/             cocotb / UVM
  sim/            仿真脚本
  syn/            build.tcl / smoke.ys / .qsf
  constr/         XDC / SDC
  lint/           waivers.vlt / .rules.verible_lint
  scripts/        rtl_lint.py 等
  build/          一切生成物（.gitignore）
  Makefile  .gitignore
```

两条设计意图：**① `rtl.f` 与 `tb.f` 必须分开**——lint 和综合只看可综合代码，不会被 TB 的 `initial`/`#` 污染（这直接对应铁律 I）；**② waiver 与被约束的代码放在一起**（OpenTitan 的 `lint/<ip>.vlt` 模式），review 时一眼看到"谁在关警告"。

`.gitignore` 至少包含：`build/ obj_dir/ sim_build/ *.vvp *.vcd *.fst *.jou *.log .Xil/ *.xpr *.runs/ *.cache/ db/ incremental_db/ output_files/ qdb/ __pycache__/ results.xml`。

### 8.2 filelist (`.f`) 约定 `[业界]` W06/S1、S12、S17、S28 `[通用]`

```
// rtl/rtl.f -- 只放可综合源。工具特有 flag 一律放命令行。
// Verilator: verilator ... -F rtl/rtl.f      iverilog: iverilog -g2012 ... -c rtl/rtl.f
// xvlog:     xvlog -sv -f rtl/rtl.f          svlint:   svlint -f rtl/rtl.f
+incdir+include
+define+SYNTHESIS

pkg/soc_pkg.v
fifo_sync.v
soc_top.v
```

- **只写三样东西**：源文件路径（每行一个）、`+incdir+`、`+define+`。这是 Verilator / iverilog / xvlog / svlint 四家的最大公约数。
- **`-f` vs `-F`（Verilator）**：`-f` 里的相对路径相对**当前工作目录**；`-F` 相对**该 `.f` 文件所在目录**。**推荐 `-F`**——脚本从任意目录调用都不会断。
- **Verible 与 Yosys 不吃 `-f`**：Verible 直接接文件列表，Yosys 用 `.ys` 脚本，需要 Makefile/脚本把 `.f` 展开（见 §0.3 的 PowerShell 片段）。

### 8.3 Makefile 模板 `[业界]` W06/§2.4 `[通用]`

五个入口固定为 `lint / sim / wave / syn / clean`，`lint` 与 `sim` 失败时必须返回非零。

```makefile
TOP     ?= soc_top
TB_TOP  ?= tb_soc_top
RTL_F   ?= rtl/rtl.f
TB_SRCS ?= $(wildcard tb/*.v)
BUILD   ?= build
WAIVER  ?= lint/waivers.vlt

.PHONY: lint sim wave syn smoke clean
# 1) 本规范的硬门禁：一条命令，两个引擎
lint:
	python3 scripts/rtl_lint.py --top $(TOP) --synth --strict \
	    --waiver $(WAIVER) $(shell grep -v '^\s*\(//\|+\|$$\)' $(RTL_F) | sed 's|^|rtl/|')

# 2) 功能仿真（Icarus，四态）
$(BUILD)/sim.vvp: $(TB_SRCS)
	@mkdir -p $(BUILD)
	iverilog -g2012 -Wall -Winfloop -s $(TB_TOP) -o $@ -c $(RTL_F) $(TB_SRCS)
# 波形器：Linux/WSL 上一般是 gtkwave；macOS 上 gtkwave 装不了（见 §0.3.2），用 surfer
WAVE ?= $(shell command -v gtkwave 2>/dev/null || command -v surfer 2>/dev/null || echo surfer)
sim: $(BUILD)/sim.vvp
	vvp -N $< -fst                 # -N：$stop 时返回 1，CI 才能失败；-fst 必须在 $< 之后
wave: $(BUILD)/sim.vvp
	vvp -N $< -fst +trace && $(WAVE) $(BUILD)/wave.fst &

# 3) 可综合性冒烟
smoke:
	yosys -s syn/smoke.ys -l $(BUILD)/yosys.log
# 4) 实现
syn:
	vivado -mode batch -source syn/build.tcl -log $(BUILD)/vivado.log -journal $(BUILD)/vivado.jou
clean:
	rm -rf $(BUILD) obj_dir
```

Windows 上没有 make 时用 `scripts/build.ps1 -Stage lint|sim|wave|syn`，结尾务必：

```powershell
if ($LASTEXITCODE -ne 0) { throw "Stage '$Stage' failed with exit code $LASTEXITCODE" }
```

——PowerShell **不会**因为外部命令返回非零而自动中止，漏了这一句 CI 会一路"成功"到底。

### 8.4 CI 里跑什么 `[业界]` W06/S34 OpenTitan `[通用]`

顺序固定，**快的在前**；PR 门禁只包含前四层，签核类工具定时跑。

| # | 阶段 | 命令 | 是否 PR 门禁 | 量级 |
|---|---|---|---|---|
| 1 | 格式 | `verible-verilog-format --verify --failsafe_success=false` | 是 `[SV]` | 秒 |
| 2 | 风格 | `verible-verilog-lint --lint_fatal --parse_fatal`（或 svlint） | 是 `[SV]` | 秒 |
| 3 | 语义 + 结构 | **`python3 scripts/rtl_lint.py --top <top> --synth --strict`** | **是（本规范硬门禁）** | 秒~十几秒 |
| 4 | 功能回归 | `iverilog -g2012 -Wall -Winfloop` + `vvp -N` / cocotb / `verilator --binary` | 是 | 分钟 |
| 5 | 实现 | `vivado -mode batch -source syn/build.tcl`（含 WNS/WHS 门禁） | 每日 / 合并到主干时 | 十几分钟~小时 |
| 6 | 签核 | AscentLint / SpyGlass CDC / Questa CDC | 定时（OpenTitan 每 8 小时） `[ASIC]` | 小时 |

CI 必须归档的产物：`build/reports/*.rpt`（时序/资源/CDC）、lint 日志、波形只在失败时上传。
**门禁靠退出码，不靠人读日志**：`-Wno-fatal`（Verilator）、缺 `-N`（vvp）、缺 `--lint_fatal`（Verible）、缺 `--failsafe_success=false`（Verible format）、PowerShell 缺 `$LASTEXITCODE` 判断——这五处任意一处漏掉，CI 就会变成"永远绿"。

---

## 9. 分歧与本规范的取舍

| # | 分歧 | 各方立场 | 本规范默认 |
|---|---|---|---|
| 1 | 豁免用**行内 `lint_off`** 还是**集中 `.vlt`** | 内联：离代码最近、读代码就知道原因，但**会向下传播到 include 树**且容易忘 `lint_on`；集中（OpenTitan `lint/<ip>.vlt`）：源码零污染、可审计，但行号型 waiver 易失效 | **自有代码单点问题 → 内联；第三方/生成代码、需审计留痕 → `.vlt`**。双方唯一共识：**绝不用全局 `-Wno-XXX`** |
| 2 | `-Wall` 是否作 CI 硬门禁 | 支持（OpenTitan：不 lint-clean 不许合并）；反对：`UNUSEDSIGNAL`/`DECLFILENAME` 在参数化 IP 与生成代码上噪声大 | **`-Wall` 全开**，只允许用 `.vlt` 对特定目录关掉这两条；正确性警告优先修复；刻意 latch、厂商双口 RAM、TB 时钟等例外按主入口最小范围豁免，不能隐藏未解决缺陷 |
| 3 | `unique`/`priority` 能否替代 `default` | "还要写"：`unique` 只在仿真期检查，综合器当 don't-care，缺 `default` 会仿真/综合不匹配；"不用写"：`unique` 已表达意图 | **一律写 `default`**（与铁律 C4/F4 一致）。另注：**Verilator 是二态仿真器，跑通它不能证明 casex/casez 的 X 语义安全** |
| 4 | Vivado 工程模式 vs 非工程模式 | 非工程：可复现、CI 友好，但 IP Integrator/Block Design 需额外脚本化；工程：GUI 与 IP Catalog 开箱即用，但 `.xpr` 含绝对路径 | **非工程模式**；重度用 BD 的项目取折中：**用 Tcl 生成工程**，`.xpr` 仍不进库 |
| 5 | filelist 手写 `.f` vs FuseSoC/Bender/Bazel | `.f`：零依赖、任何工具都吃、模型最容易生成，但无依赖解析与版本管理；FuseSoC：一份 `.core` 驱动 lint/sim/syn 全后端，但多一层抽象 | **单仓库工程 → `.f` + Makefile**；多 IP 复用 → FuseSoC/Bender |
| 6 | 波形 VCD vs FST | VCD 是 IEEE 标准、任何工具可读、可脚本解析；FST 体积小得多（官方："FST dumps are a fraction of the size"），但非标准 | **默认 FST**；需要跨工具交换或脚本解析时才用 VCD |
| 7 | Verilator SV TB vs C++ TB vs cocotb | SV TB 可移植到 VCS/Questa，但受限于 Verilator 的 SV 支持面；C++ TB 最快、能接 C 参考模型，但不可移植；cocotb 生态好，但 VPI 边界开销大 | **模块级 → cocotb 或 SV TB；系统级/长回归/需 C 参考模型 → C++ TB** |

---

## 本篇检查清单

提交前（对应 SKILL.md §2，勾不掉就不要提交）：

- [ ] `python3 scripts/rtl_lint.py --top <top> --synth <files>` 输出 **`通过 ✔`**（SV 加 `--sv`）
- [ ] Windows 上已设 `$env:PYTHONIOENCODING='utf-8'`
- [ ] Yosys `stat` 里**没有** `$dlatch`；`$dff`/`$adff` 的 WIDTH 与实例数合计符合预期寄存器位数
- [ ] 命令行里**没有** `-Wno-XXX`、`-Wno-fatal`
- [ ] 新增的 `lint_off` 都是成对的、最小范围的，且旁边写了理由；**不在头文件顶部**
- [ ] `.f` 里只有源文件路径、`+incdir+`、`+define+`
- [ ] 一文件一模块、文件名 == 模块名（`DECLFILENAME` 零告警）

仿真：

- [ ] `iverilog` 带 `-g2012`（SV）、`-s <top>`、`-Wall -Winfloop`
- [ ] `vvp` 带 `-N`（否则 `$stop` 不会让 CI 失败）
- [ ] `verilator --binary` 的 TB 含延时时确认 `--timing` 已生效（未生效会只报 `STMTDLY`）
- [ ] 波形由 plusarg 控制、默认关闭；回归不写 GB 级波形
- [ ] 需要验 X 传播时用了**四态**仿真器，而不是 Verilator

综合 `[FPGA]`：

- [ ] `build.tcl` 进版本库，`.xpr`/`.runs`/`.cache` 在 `.gitignore` 里
- [ ] `synth_design` 写了 `-top` 与 `-part`
- [ ] 三个阶段都出了 `report_timing_summary` + `report_utilization`
- [ ] 跑了 `report_cdc -details`，每条 Critical 都有结论（改结构 或 书面 waiver）
- [ ] 脚本里有 **WNS/WHS 判断并 `error`**（记住：时序不收敛照样出 bit）
- [ ] Critical Warning 已清零或逐条 `set_msg_config` 处理过（ID 已在本地日志确认）

CI：

- [ ] 五个"永远绿"陷阱都已排除：`-Wno-fatal` / 缺 `vvp -N` / 缺 `--lint_fatal` / 缺 `--failsafe_success=false` / PowerShell 缺 `$LASTEXITCODE` 判断
- [ ] `build/reports/` 已作为 artifact 归档

---

## 维护状态与边界

2026-09-28：已修复 Verilator 退出码、Yosys include/define 透传、路径转义和 latch 判据。
脚本仍不直接解析 filelist，Yosys 内置前端仍只支持部分 SV，Tcl 功能需可用。
Windows/WSL 路径逻辑沿用，本次未在 Windows 重跑；本机验证范围见 `assets/VERIFICATION.md`。
Quartus 的历史二手引用仍需按所用版本核对。历史 Wxx 索引对应的 `_research` 不随本 skill 分发。

当前命令行为参考：[Verilator 参数](https://verilator.org/guide/latest/exe_verilator.html)、
[Yosys 前端](https://yosyshq.readthedocs.io/projects/yosys/en/latest/cmd/index_frontends.html)。
本机版本与在线文档版本可能不同，以实际安装的 `--help`/`help` 和验证记录为准。
