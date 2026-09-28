# 模板与检查脚本验证记录

日期：2026-09-28。本记录由本次维护中的实际命令结果整理；可用下列命令复现。

环境：macOS / Apple Silicon，Python 3.9.6，Verilator 5.050（2026-07-01），
Yosys 0.68+post（c12172fbae8af5e20f6fb52e3d4e92d56ed587b6，启用 Tcl），Icarus Verilog 13.0。

```bash
python3 -m unittest discover -s tests -v
```

结果：**11 个测试全部通过，0 skip**。全程生成文件位于临时目录。

| 检查 | 结果 |
|---|---|
| 9 个 V2001 RTL 模板，逐个 `--v2001 --strict --synth` | 全通过，lint 零警告，结构检查无 latch |
| `fsm_3seg_sv.sv`，`--sv --strict --synth` | 通过 |
| TB：Icarus `-g2001` + `vvp -N` | 正常完成 8/8 检查；强制失败、超时均非零退出 |
| TB：Verilator `--binary --timing -Wall --language 1364-2001 --timescale 1ns/1ps` | 正常完成；强制失败、超时均非零退出 |
| Verilator 无标准诊断的非零退出（mock） | 不再错误报告成功 |
| 工具缺失与 warning/strict 组合（mock） | 按退出码与 strict 策略报告 |
| include、宏、含空格/分号路径（真实工具） | 同一设计在两个引擎都通过 |
| Verilator 局部豁免的真实 latch（负向用例） | Yosys 单元断言仍拒绝 |
| 文件/模块名为 `dlatch` 的纯组合电路 | 不再被日志关键字误判 |
| SV 源用 V2001 检查、互斥语言参数 | 正确失败 |

另外：skill-creator `quick_validate.py` 通过；入口与 README 本地链接检查通过；
`git diff --check` 通过。入口从 296 行缩短为 88 行，详细规则保留在 `references/15-coding-rules.md`。
验证器所需 PyYAML 装在一次性临时目录，未修改系统 Python 或项目依赖。

## 范围

这不是全部模板的完整功能或全参数验证：FIFO/握手/脉冲同步器只执行 lint/结构冒烟。
未执行 Vivado/Quartus 映射、CDC/RDC、STA、DFT 或硬件验证；Windows/WSL 未在本次重跑。
CDC 模板要求协调复位与物理约束；依赖条件见模板头和 `references/06-clock-reset-cdc.md`。
Yosys `stat` 为未映射向量单元统计，不等价于门数、触发器位数或目标器件资源数。

原 2026-08-12 的 WSL 验证叙述已保留在 Git 初始提交 `e7bcd6f` 中，不能当作本次跨平台复测。
