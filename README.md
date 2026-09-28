# rtl-verilog-standard

面向 Verilog/SystemVerilog RTL 和自检 testbench 的编码与检查 skill。
先读 [SKILL.md](SKILL.md)；详细条款按需加载，项目约定与接口契约优先。

## 内容

- `SKILL.md`：适用范围、核心约束、验证流程和导航。
- `references/`：15 篇参考，含详细编码条款、CDC、存储器与工具链。
- `assets/templates/`：10 个 RTL 模板、1 个自检 testbench。
- `scripts/rtl_lint.py`：Verilator lint 和可选 Yosys 结构冒烟。
- `tests/test_regression.py`：退出码、构建参数、模板和 TB 失败路径回归。
- [验证记录](assets/VERIFICATION.md)：当前工具版本、实跑结果与未覆盖范围。

## 运行

以下从本目录执行；从其他目录使用脚本的实际路径，设计文件相对调用目录。
需 Python 3、Verilator；`--synth` 另需启用 Tcl 的 Yosys。功能回归需 Icarus Verilog/vvp。
Windows 可调用已安装这些工具的 WSL；脚本保留 Homebrew 路径回退。

```bash
python3 scripts/rtl_lint.py --v2001 --top fsm_3seg --strict --synth assets/templates/v2001/fsm_3seg.v
python3 scripts/rtl_lint.py --sv --top fsm_3seg_sv --strict --synth assets/templates/sv/fsm_3seg_sv.sv
python3 -m unittest discover -s tests -v
```

`--inc`、`--define` 同时传给两个引擎；`--waiver` 只传给 Verilator。
不直接解析 `.f`，不要在展开清单时丢失宏、include 或相对路径语义。
工具缺失时回归会明确 skip；skip 不是对应能力已经通过的证据。

## 来源与范围

原版本保留了夏宇闻《Verilog 数字系统设计教程（第 4 版）》页码以及业界来源索引。
原始 `_research` 调研档案不在此目录，本次未重新取得教材扫描件；历史交叉审查叙述不作为当前可复现证据。
命令与 CDC 更新所用公开官方来源在相应参考文档中。

当前验证覆盖 lint、结构冒烟及 FSM TB，不替代其他模板的完整功能验证、目标器件映射、
CDC/RDC、STA 或 DFT。Quartus 历史条目仍有未逐字核实的部分。

教材与引用版权归各原作者/出版方。本目录沿用团队内部使用许可。
