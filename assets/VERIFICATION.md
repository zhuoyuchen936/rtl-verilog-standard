# 模板验证记录

本文件由 `scripts/rtl_lint.py` 实跑生成，用于支撑 README 中"所有模板均经验证"的说法。

- 生成时间：2026-08-12 22:18
- Verilator 5.024 / Yosys 0.33（经 WSL Ubuntu 调用）
- 判据：`verilator --lint-only -Wall` 零错零警 **且** `yosys hierarchy/proc/opt/check -assert` 通过且未推断出 `$dlatch`

- 语言基线：v2001 目录下的模板全部在 **`--v2001`（即 `--language 1364-2001`）** 下复验通过，
  确保它们是真正的 Verilog-2001，而不是"因为 Verilator 默认按 SystemVerilog 解析所以碰巧过了"。

复现命令：

```bash
# Verilog-2001 模板：加 --v2001 才是真正的基线检查
python3 scripts/rtl_lint.py --v2001 --top fsm_3seg --synth assets/templates/v2001/fsm_3seg.v

# SystemVerilog 模板
python3 scripts/rtl_lint.py --sv --top fsm_3seg_sv --synth assets/templates/sv/fsm_3seg_sv.sv
```

反向验证（证明 `--v2001` 确实在起作用）：把 SV 模板喂给 `--v2001`，
Verilator 会立刻报 6 个 syntax error（`always_ff` / `always_comb` / `typedef enum` 全部不被接受）。
不加这个开关时它 lint 全绿——这正是本规范要求项目显式声明语言基线的原因。

| 模板 | 语言 | lint | 综合 | 结论 |
|---|---|---|---|---|
| `module_skeleton.v` | Verilog-2001 | 0 错 / 0 警 | 无 latch | **通过** |
| `fsm_3seg.v` | Verilog-2001 | 0 错 / 0 警 | 无 latch | **通过** |
| `sync_2ff.v` | Verilog-2001 | 0 错 / 0 警 | 无 latch | **通过** |
| `reset_sync.v` | Verilog-2001 | 0 错 / 0 警 | 无 latch | **通过** |
| `pulse_sync.v` | Verilog-2001 | 0 错 / 0 警 | 无 latch | **通过** |
| `handshake_mcp.v` | Verilog-2001 | 0 错 / 0 警 | 无 latch | **通过** |
| `async_fifo.v` | Verilog-2001 | 0 错 / 0 警 | 无 latch | **通过** |
| `sdp_ram.v` | Verilog-2001 | 0 错 / 0 警 | 无 latch | **通过** |
| `skid_buffer.v` | Verilog-2001 | 0 错 / 0 警 | 无 latch | **通过** |
| `fsm_3seg_sv.sv` | SystemVerilog | 0 错 / 0 警 | 无 latch | **通过** |

## Testbench 实跑

`tb_fsm_3seg.v` 用 `verilator --binary --timing -Wall` 编译并运行：

```
checks run : 8
failures   : 0
=== TEST PASSED ===
```

> 该 testbench 的第一版曾因多等一拍而错过只持续一个周期的 `valid` 脉冲，被自身的自检机制抓出（`FAIL: valid should pulse one cycle after DONE state`）。这正是本规范要求 testbench 必须自检的理由。
