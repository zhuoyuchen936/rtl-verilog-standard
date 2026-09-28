# 10 · Testbench 与验证规范

一条规矩统领全篇：**testbench 必须自己判对错。**

靠人眼看波形的 testbench 在回归里没有任何价值——它跑一万遍也不会告诉你哪一次错了。
教材第 2 章一开始就把"模块的测试"和模块本身并列讲，第五部分更直接指出
"Verilog HDL 属于硬件描述语言，而 testbench 属于软件测试激励范畴，两者原则上是有差别的"（p.491）。
写 RTL 的思维和写 testbench 的思维不是一回事，本篇的规则和主规范的「铁律」也因此不同。

---

## 本篇速览

1. 结束时必须打印 **PASS / FAIL**，并用**非零退出码**让 CI 能感知失败。
2. 必须有**超时看门狗**——挂死的仿真在 CI 里比失败更难查。
3. 激励在**时钟下降沿**驱动，天然避开与 DUT 在上升沿的采样竞争。
4. testbench 里**可以**用 `#` 延迟、`initial`、`fork/join`、`while`——主规范 I 节的禁令只针对可综合 RTL。
5. 看非阻塞赋值的结果用 `$strobe`，不要用 `$display`。

---

## 一、结构

### R-10-01 自检是底线 `[通用]`

```verilog
// 见 assets/templates/v2001/tb_fsm_3seg.v（实际编译运行通过，8/8 checks PASS）
integer errors = 0;
integer checks = 0;

task check;
    input                   actual;
    input                   expected;
    input [8*MSG_CHARS-1:0] msg;
    begin
        checks = checks + 1;
        if (actual !== expected) begin
            errors = errors + 1;
            $display("[%0t] FAIL: %0s  expected=%b actual=%b", $time, msg, expected, actual);
        end
    end
endtask
```

结尾：

```verilog
$display("checks run : %0d", checks);
$display("failures   : %0d", errors);
if (errors == 0) begin
    $display("=== TEST PASSED ===");
    $finish;
end else begin
    $display("=== TEST FAILED ===");
    // Icarus 运行器必须带 vvp -N；SV 工程可改用 $fatal(1, ...)。
    $stop;
end
```

### R-10-01b 正确传播仿真失败 `[通用]` `[工具]` 实测

**`$finish(1)` 的参数不是退出码**，它是"打印多少统计信息"（0/1/2）。实测结果：

| 写法 | Verilator 5.024 退出码 |
|---|---|
| `$finish;` / `$finish(1);` | **0** |
| `$fatal(1, ...)` | 非 0（abort） |

也就是说，一个打印了 `=== TEST FAILED ===` 的仿真，用 `$finish(1)` 结束时**退出码仍然是 0**，
CI 会把它判成通过——这是一条会让整条回归形同虚设的坑。

退出码是主判据，PASS 标记可作附加检查。纯 V2001 用 `$stop` 配 `vvp -N`；SV 用 `$fatal`。下面示例同时保留进程失败和缺少 PASS 的失败：

```bash
# Linux / macOS
set -o pipefail
./sim | tee sim.log || exit 1
grep -q "=== TEST PASSED ===" sim.log || { echo "REGRESSION FAILED"; exit 1; }
```

```powershell
# Windows PowerShell
.\sim.exe | Tee-Object sim.log
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
if (-not (Select-String -Path sim.log -Pattern '=== TEST PASSED ===' -Quiet)) {
    Write-Error "REGRESSION FAILED"; exit 1
}
```

本模板打印固定判据串，失败和超时都用 `$stop`；Icarus 用 `vvp -N`，Verilator 默认将 `$stop` 作为失败。运行器必须实测负向用例。

注意两点：
- 用 **`!==`** 而不是 `!=`。`!=` 遇到 x/z 会返回 x（被当成假），于是"信号是 X"这种错误会被漏掉。
  `!==` 是四态全等比较，X 也能被抓出来。
- **不要在第一个错误处就 `$finish`**。让它跑完，一次拿到全部失败点。

### R-10-02 消息长度有硬上限 `[V2001]`

Verilog-2001 没有 `string` 类型，消息只能塞进定长向量，**超长会被静默截断**。
`input [255:0] msg` 只能装 32 个字符。本模板用 `MSG_CHARS = 64` 并把它写成 localparam，
改消息前先数长度。

`[SV]` 直接用 `string` 类型，没有这个坑。

### R-10-03 时钟、复位、激励各自独立 `[通用]`

```verilog
// 时钟：独立一个 always。用阻塞赋值是 testbench 的标准写法。
// 注：BLKSEQ 规则不区分这种场景，需要最小范围豁免。
/* verilator lint_off BLKSEQ */
always #(CLK_PERIOD/2) clk = ~clk;
/* verilator lint_on BLKSEQ */
```

教材 p.24 给的范式是 `always #50 clock = ~clock;`（周期 = 2×延迟），一致。

### R-10-04 超时看门狗 `[通用]`

```verilog
initial begin
    #TIMEOUT_NS;
    $display("[%0t] FATAL: simulation timeout", $time);
    $display("=== TEST FAILED (timeout) ===");
    $stop;  // Icarus: vvp -N
end
```

没有它，一个握手死锁会让 CI 一直挂到超时被杀，且没有任何有用输出。

### R-10-05 激励在下降沿驱动 `[通用]`

DUT 在上升沿采样，testbench 在下降沿驱动，两者天然错开半个周期，
不需要靠 `#1` 这种脆弱的小延迟去躲竞争。

```verilog
task step;
    input integer n;
    integer i;
    begin
        for (i = 0; i < n; i = i + 1) @(negedge clk);
    end
endtask
```

> ⚠️ **数清楚周期**。`tb_fsm_3seg.v` 的第一版就是因为多等了一拍，
> 错过了只持续一个周期的 `valid` 脉冲，被自检抓了出来——这正好证明了自检的价值。

---

## 二、显示与调试系统任务

### R-10-06 看非阻塞赋值的结果要用 `$strobe` `[通用]` `[教材]` p.197 原则(7)

教材 8 条要点的第 (7) 条就是"用 `$strobe` 系统任务来显示用非阻塞赋值的变量值"。

**为什么**：`$display` 属于动态事件队列，可能在非阻塞赋值更新左值**之前**执行，
于是你看到的是上一拍的旧值。`$strobe` 排在监控事件队列，
保证在当前时间片所有赋值都完成之后才执行。

| 任务 | 何时执行 | 用途 |
|---|---|---|
| `$display` | 立即 | 打印阻塞赋值结果、事件日志 |
| `$strobe` | 当前时间片末尾 | 打印非阻塞赋值结果 |
| `$monitor` | 任一参数变化时 | 全程跟踪；**整个仿真只需调用一次** |

### R-10-07 `$monitor` 只调用一次 `[通用]` `[教材]` p.116

教材小结里是强否定表述："不需要、也不能在 always 过程块中调用"。
放在 `initial` 里调一次即可，它会自动持续监视。

### R-10-08 `$random` 是带符号的 `[通用]` `[教材]` p.105

```verilog
// 反例：$random % 60 得到的是 -59 ~ 59
addr = $random % 60;

// 正例：用位并接取绝对值，得到 0 ~ 59
addr = {$random} % 60;
```

### R-10-09 `timescale 与波形 `[通用]`

```verilog
`timescale 1ns / 1ps        // 时间单位 / 时间精度
```

教材 p.116 提醒：`timescale 不同的多个模块最好分开编译，以免把时间单位搞混。

波形：

```verilog
initial begin
    $dumpfile("tb_top.vcd");
    $dumpvars(0, tb_top);    // 0 = 递归转储所有层次
end
```

大型设计用 FST（`--trace-fst`）比 VCD 小一个数量级。

---

## 三、验证策略

### R-10-10 三种测试都要有 `[通用]` `[教材]` p.496-497

教材第五部分主张：**定向测试 + 受约束的随机测试 + 异常测试**三者兼备。

- **定向测试**：把设计意图逐条翻译成用例，覆盖协议的正常路径。
- **约束随机**：用随机激励撞出你没想到的组合。`[SV]` 用 `randomize()` + `constraint`。
- **异常测试**（作者特别强调的一条）：非法输入、协议违例、复位中途拉低、
  背压持续拉死——要求模块**不能异常挂死或崩溃**。

### R-10-11 边界条件清单 `[通用]`

每个模块至少覆盖：复位期间与复位释放瞬间、空/满、第一个和最后一个数据、
背压（ready 一直为 0）、连续满吞吐、单拍脉冲输入、计数器回绕、参数取最小值和最大值。

### R-10-12 RTL 与参考模型比对 `[通用]` `[教材]` p.491

大型设计要走"RTL 与算法 C 模型逐用例比对"的闭环，所有用例回归通过才算前仿结束。
`[工具]` Verilator 的 C++ testbench 天然适合做这件事；cocotb 则可以用 Python 写参考模型。

### R-10-13 综合前必须先仿真 `[通用]` `[教材]` p.180 13.3(1)

教材"综合的一般原则"第一条：综合之前一定要进行仿真。
逻辑错误如果没在仿真里暴露，会原封不动地进入综合结果。

同样地，教材要求**布局布线之后还要再仿真一次**（门级仿真），
`[ASIC]` 这一步不可跳过；`[FPGA]` 通常用时序仿真或直接上板验证替代。

---

## 四、运行

```bash
# Icarus Verilog
iverilog -g2001 -s tb_fsm_3seg -o sim tb_fsm_3seg.v fsm_3seg.v && vvp -N sim

# Verilator（需要 --timing 支持 # 延迟）
verilator --binary --timing -Wall --top-module tb_fsm_3seg tb_fsm_3seg.v fsm_3seg.v
./obj_dir/Vtb_fsm_3seg
```

更完整的命令与 CI 集成见 `12-toolchain.md`。

---

## 本篇检查清单

- [ ] 仿真结束打印 PASS/FAIL，失败与超时时 `$stop` + `vvp -N`（或 SV `$fatal`）返回非零码
- [ ] 比较用 `!==` 而不是 `!=`（能抓到 X）
- [ ] 第一个错误不中断仿真，跑完统计总数
- [ ] 有超时看门狗
- [ ] 激励在 `negedge` 驱动
- [ ] `[V2001]` 消息长度没超过 msg 向量容量
- [ ] 看非阻塞赋值结果用的是 `$strobe` 不是 `$display`
- [ ] `$monitor` 只在 initial 里调了一次
- [ ] 用了 `{$random}` 而不是裸 `$random` 取模
- [ ] 覆盖了复位、空/满、背压、满吞吐、回绕、参数极值
- [ ] 有异常/协议违例用例，且 DUT 不挂死
- [ ] testbench 本身也过了 lint（时钟发生器的 BLKSEQ 用最小范围豁免）
