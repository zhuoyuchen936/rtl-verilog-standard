# rtl-verilog-standard

一套给**人和模型共用**的 Verilog / SystemVerilog RTL 编码规范。

目标很直接：让不同的模型（Claude、Codex、Cursor、Copilot……）、不同的人写出来的 RTL
看起来像同一个人写的，并且**综合出来的电路和作者心里想的那个电路是同一个**。

## 它是怎么来的

- **教材侧**：逐页提取《Verilog 数字系统设计教程(第 4 版)》(夏宇闻，清华大学出版社) 全书 519 页扫描件中
  的规范性条目，条条带书页号。核心来源包括 p.380「语汇代码的编写标准」8 条、p.380-381「可综合代码的
  编写标准」15 条、p.180「综合的一般原则」、p.180-185「语言指导原则」、p.197「Verilog 模块编程要点」8 条。
- **业界侧**：lowRISC/OpenTitan style guide、Cliff Cummings 的 SNUG 系列论文、Don Mills 的 latch 论文、
  AMD/Xilinx UG901/UG949、Intel Quartus 设计建议、IEEE 1364-2005 与 IEEE 1800 标准原文。
  多数条目是把 PDF 下载到本地逐字比对得到的，不是检索摘要。
- **工具侧**：所有代码模板都经 `verilator --lint-only -Wall` 零告警 + `yosys` 综合验证；
  testbench 实际编译运行通过。
- **交叉审查**：用 Codex (gpt-5.2-codex) 作独立第二信源，对反模式/锁存器/位宽/仿真-综合不一致等
  条目做交叉取证，逐条标注「已印证 / 未能印证 / 有误」。

凡是业界存在真实分歧的地方（同步 vs 异步复位、数据通路要不要复位、`full_case`、独热编码、
X 传播……），规范不装作铁板一块——`references/14-disputes.md` 把各方立场、适用条件、
以及本规范的默认取舍和偏离条件都写清楚了。

## 目录

```
rtl-verilog-standard/
├── SKILL.md          主规范：20 条铁律 + 导航（先读这个）
├── references/       14 篇专题详解，按需打开
├── assets/templates/ 可直接抄的模板，全部经过 lint 与综合验证
└── scripts/rtl_lint.py  一条命令跑 lint + 综合冒烟测试
```

## 怎么用

### Claude Code

拷贝整个目录到 `~/.claude/skills/rtl-verilog-standard/`（Windows: `C:\Users\<你>\.claude\skills\`），
重启后聊到 Verilog/RTL 相关任务会自动触发。也可以直接 `/rtl-verilog-standard` 调用。

### Codex / 任何读 AGENTS.md 的工具

在你的 RTL 仓库根目录放一个 `AGENTS.md`：

```markdown
# RTL 编码规范
写任何 Verilog/SystemVerilog 之前，先读 `docs/rtl-verilog-standard/SKILL.md` 并严格遵守。
细节见同目录 `references/`。提交前必须跑：
    python3 docs/rtl-verilog-standard/scripts/rtl_lint.py --top <top> --synth <files>
输出必须是「通过 ✔」。
```

### Cursor / Windsurf

把 `SKILL.md` 的「铁律」一节内容放进 `.cursor/rules/rtl.mdc`（或 `.cursorrules`），
并在其中指向本目录的 `references/` 做延伸阅读。

### 其它模型 / 直接贴提示词

`SKILL.md` 本身就是自洽的提示词，整篇贴进 system prompt 即可（约 300 行）。
上下文紧张时，只贴「1. 铁律」一节。

## 自检

```bash
python3 scripts/rtl_lint.py --top counter --synth rtl/counter.v
```

注意是 `python3`：macOS 自 12.3 起**不再提供 `python` 这个命令**，写 `python` 会直接 command not found。

先装引擎：

```bash
# macOS (Homebrew)
brew install verilator yosys icarus-verilog

# Ubuntu / WSL
sudo apt install verilator yosys iverilog
```

Windows 上无需安装任何 EDA 工具——脚本会自动探测并经 WSL 调用 `verilator` / `yosys`。

**Homebrew 与 PATH**：brew 把工具装进 `/opt/homebrew/bin`（Apple Silicon）或 `/usr/local/bin`（Intel），
而这两个目录在**非登录 shell** 里通常不在 PATH 上——CI、Makefile、agent 工具链调用本脚本时正是这种情况。
`rtl_lint.py` 会自己回退去搜这两个目录，所以即使 PATH 里没有也能找到引擎；
但你自己在终端里跑 `verilator` 仍然需要 `~/.zprofile` 里有：

```bash
eval "$(/opt/homebrew/bin/brew shellenv)"
```

## 已知缺口（如实列出，不装完整）

这套规范经过 7 路对抗性审查（技术正确性 / 教材溯源抽查 / 内部一致性 / 代码实编译 /
FPGA-ASIC 标注 / Codex 独立复核 / 完整性批评），审查报告全部保留在 `_research/review/`。
以下是**改完之后仍然存在**的缺口：

1. **时序约束（SDC/XDC）覆盖不完整**。只在 `06-clock-reset-cdc.md` 给了与 CDC 直接相关的最小集
   （`create_clock`、`set_clock_groups -asynchronous`、同步器 false path、MCP 的 `set_max_delay`）。
   `create_generated_clock`、IO delay、multicycle path 的完整方法学不在范围内。
2. **验证只到 lint + 结构综合冒烟**。`scripts/rtl_lint.py` 用的是 Verilator（二态，测不了 X 传播）
   和 Yosys（推断行为不代表 Vivado / Quartus / DC / Genus）。它的定位是**提交前挡掉低级错误**，
   不替代目标综合器实跑、STA、CDC/RDC、门级/形式验证与 DFT。
3. **部分厂商条款是二手引用**。W03/W04 调研中标注了文档号与页码，但少数 PDF 来自课程站镜像而非厂商官方域名，
   Intel 部分文档抓取时返回 403 只拿到检索摘要。凡此类条目文中均已标注，落到关键决策前请以厂商当前版本手册复核。
4. **教材第 11 章（数据接口同步）提取不完整**。该章节的两次自动提取都被内容过滤拦下，
   相关内容改由业界资料（Cummings、厂商手册）补足，教材侧溯源较薄。
5. **UVM 只到方法学层面**。教材第五部分本身没有 UVM 代码，本规范也未提供 UVM 模板。

## 版权

教材条目版权归《Verilog 数字系统设计教程(第 4 版)》(夏宇闻) 及原出版方所有，
本规范仅作条款溯源引用，并注明书页号。业界条目均标注原始 URL 与文档名。
本目录供团队内部使用。
