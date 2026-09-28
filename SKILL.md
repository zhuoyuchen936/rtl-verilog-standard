---
name: rtl-verilog-standard
description: 编写、审查或重构 Verilog/SystemVerilog RTL 与自检 testbench 时使用。提供组合/时序逻辑、位宽、复位、CDC、握手、存储器推断规范及可运行的 lint/综合冒烟检查。适用于 .v/.sv/.svh 代码和相关 RTL 验证；仅讨论 FPGA/ASIC 概念或只运行 HLS/实现工具时不自动套用。
license: 团队内部使用。教材条目版权归原作者与出版方，页码仅作溯源引用。
---

# RTL 编码与检查

用于手工 RTL 和自检 testbench。先继承项目语言基线、接口、复位、约束和已有验证流程；无项目约定时默认 Verilog-2001。生成代码、第三方 IP 和厂商推断模板保留原有契约，不为风格整库改写。

## 1. 开始工作

从需求、代码和工程配置确认时钟域、复位、握手、吞吐/延迟、参数合法范围。新增模块在文件头记录；小修复只补缺失且相关的信息。只有影响功能或接口且无法合理推断的问题才询问用户，其余记录假设并继续。

先确认源文件清单、顶层、宏、include 目录和工具版本，再选择下文相关参考文件。所有相对路径以本 skill 目录为基准；从项目调用脚本时使用脚本的实际绝对路径，RTL 路径仍相对调用目录。

## 2. 核心约束

- **组合与时序**：组合用阻塞赋值、完整敏感表和覆盖所有路径的赋值；时序寄存器用非阻塞赋值。信号单一驱动，避免组合反馈。刻意的 latch、双口 RAM 等特殊结构按厂商模板实现并说明例外。
- **宽度与符号**：数据运算明确宽度、符号、扩展和截断；`$signed()` 不扩宽。参数与循环下标可用整数常量。计数器检查边界，地址宽度检查深度为 1、非 2 的幂及非法参数。
- **时钟与复位**：普通 RTL 优先 clock enable；真时钟使用器件/工艺专用资源与时钟约束。异步复位按各接收域同步释放；控制状态确定初始化，数据通路是否复位按有效位和器件推断需求决定。
- **CDC/RDC**：单 bit 电平、脉冲和多 bit 总线分别选择同步器、握手或 FIFO。两级同步降低亚稳态传播概率，不保证绝无失效。Gray 指针还需要物理时延/skew 约束；握手与 FIFO 模板要求协调复位，不能默认支持任意单侧复位。
- **握手**：`valid && ready` 才传输；背压时保持 valid、数据和 sideband。源端不能等待 ready 才产生 valid；ready 可以依赖 valid，但避免组合环，AXI 边界遵守无输入到输出组合路径的要求。
- **FSM**：新模块默认三段式，已有实现保持协议与延迟。明确非法态策略；RTL 的 `default` 不等于综合后保留恢复逻辑，安全要求需目标综合器与网表验证。
- **可综合性**：综合源与 TB 分开。仿真断言、参数检查、延迟与打印需隔离；初始化、RAM、DSP 与原语按目标工具能力判断，不把可移植子集约定说成语言限制。
- **风格**：新手工模块默认一文件一模块、命名端口连接、4 空格、`default_nettype none` 并在文件末恢复 `wire`。沿用项目命名与接口；风格偏好不应改变电路行为。

规则编号 A–I、教材页码和完整例外见 [详细规则](references/15-coding-rules.md)。审查时先报正确性、协议、CDC 和位宽问题，风格建议单列。

## 3. 验证与交付

先使用项目已有的检查入口。对工具支持的独立 RTL，可运行本 skill 的脚本（以下命令在 skill 目录执行）：

```bash
python3 scripts/rtl_lint.py --v2001 --top fsm_3seg --synth --strict assets/templates/v2001/fsm_3seg.v
python3 scripts/rtl_lint.py --sv --top fsm_3seg_sv --synth --strict assets/templates/sv/fsm_3seg_sv.sv
```

`--v2001` 与 `--sv` 互斥；务必按项目显式选择。省略时沿用工具默认解析模式，不能据此声称符合 V2001。
`--inc DIR`、`--define NAME=VALUE` 可重复，传给两种引擎；`--waiver FILE.vlt` 只用于 Verilator。脚本不解析 filelist；使用项目入口，或准确展开路径、宏和 include，不要只过滤文件名而丢失构建配置。

通过条件是进程退出码 0 和已执行检查的通过结论；工具缺失、崩溃、解析失败都不能当成功。`--synth` 使用 Yosys `proc`、锁存器单元断言和 `check -assert`，属于结构冒烟，未映射的单元统计不是门数或物理面积。

Yosys 内置 SV 前端不能读取全部 SV/厂商 IP。此时用项目目标综合器，或检查可支持子模块，并明确报告范围与未完成项；不要为迁就工具改写正确设计。工具安装、完整实现和签核按任务范围决定，不强制每次小修复都跑 STA/DFT。

- 功能变更用自检仿真验证相关行为，包含边界、复位和背压；需要 X/Z 语义时明确选择四态工具/模式，不能从 lint 通过推断 X 传播正确。
- TB 正常完成用 `$finish`；纯 V2001 失败/超时用 `$stop` 并配 `vvp -N`，SV 可用 `$fatal(1, ...)`。`$finish(1)` 的参数不是进程退出码。至少验证一次失败路径能让运行器返回非零。
- 不靠全局关闭警告取得绿色。已有 waiver 可继承；新增 waiver 限定对象/范围、说明依据。刻意 latch 不适用脚本的无 latch 断言，应走项目检查并报告例外。
- 交付时说明改动、运行的命令/工具版本、结果和未验证范围；lint/结构检查不替代功能仿真、CDC/RDC、目标映射及 STA。

维护本 skill 时运行 `python3 -m unittest discover -s tests -v`，再用 skill-creator 的 `quick_validate.py` 验证入口。当前实跑证据见 [验证记录](assets/VERIFICATION.md)。

## 4. 按需阅读

| 场景 | 参考 |
|---|---|
| 规则编号、默认风格及出处 | [15-coding-rules](references/15-coding-rules.md)、[01-naming-and-format](references/01-naming-and-format.md) |
| 语言基线与综合子集 | [02-synthesizable-subset](references/02-synthesizable-subset.md) |
| 组合/时序、赋值与事件调度 | [03-combinational-logic](references/03-combinational-logic.md)、[04-sequential-logic](references/04-sequential-logic.md) |
| 状态机 | [05-fsm](references/05-fsm.md) |
| 时钟、复位、CDC/RDC 与约束 | [06-clock-reset-cdc](references/06-clock-reset-cdc.md) |
| 位宽、符号、流水线 | [07-datapath-and-width](references/07-datapath-and-width.md) |
| 接口、参数化、ready/valid | [08-hierarchy-and-interface](references/08-hierarchy-and-interface.md) |
| RAM/ROM/DSP/原语 | [09-memory-and-primitives](references/09-memory-and-primitives.md) |
| 自检、断言、回归 | [10-testbench](references/10-testbench.md) |
| 代码审查 | [11-lint-and-review-checklist](references/11-lint-and-review-checklist.md) |
| 工具命令与平台限制 | [12-toolchain](references/12-toolchain.md) |
| 教材溯源与争议 | [13-xiayuwen-source](references/13-xiayuwen-source.md)、[14-disputes](references/14-disputes.md) |

历史参考中 `_research/...`、Wxx/Gxx 是原调研索引，本目录不含原始调研档案。需要精确出处时查公开原文，不能把这些索引当成可读取的本地证据。旧参考与本入口冲突时以本入口的适用范围为准。

## 5. 模板选择

模板位于 `assets/templates/v2001/`；复制后按设计契约调整并重新验证。

| 文件 | 用途与边界 |
|---|---|
| `module_skeleton.v` | 单级 valid/ready 流水，ready 有组合回传 |
| `fsm_3seg.v` | 输出寄存的三段式 FSM，注意输出延迟 |
| `sync_2ff.v` / `reset_sync.v` | 单 bit 电平同步 / 异步复位同步释放 |
| `pulse_sync.v` | 开环 toggle 脉冲同步，事件间距必须有保证 |
| `handshake_mcp.v` | 单笔多 bit req/ack；忙时不接受请求，需数据路径约束 |
| `async_fifo.v` | Gray 指针 FIFO，`ASIZE >= 2`，异步读，协调复位 |
| `sdp_ram.v` | 同时钟简单双口 RAM，同步读、read-first，无存储阵列复位 |
| `skid_buffer.v` | 两槽弹性缓存，无背压时一拍延迟，可每拍传输 |
| `tb_fsm_3seg.v` | 自检 TB，成功/失败/超时可观测 |

SV FSM 位于 `assets/templates/sv/fsm_3seg_sv.sv`。模板通过 lint/结构冒烟不等于通过目标 FPGA 推断、CDC/STA 或全参数功能验证。
