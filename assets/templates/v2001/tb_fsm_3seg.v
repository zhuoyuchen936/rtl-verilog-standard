// -----------------------------------------------------------------------------
// tb_fsm_3seg -- 自检 testbench 模板
//
// 本模板要立的规矩：**testbench 必须自己判对错**。
// 靠人眼看波形的 testbench 在回归里没有任何价值——它跑一万遍也不会告诉你哪次错了。
// 判据是：仿真结束时打印 PASS/FAIL，并用非零退出码让 CI 能感知失败。
//
// 结构约定：
//   1. 时钟单独一个 always，复位单独一个 initial，互不纠缠。
//   2. 激励用 task 封装，让测试用例读起来像时序图。
//   3. 每个检查点用 check() 比对，累加错误数，不要中途 $finish 掩盖后续问题。
//   4. 加超时看门狗——挂死的仿真在 CI 里比失败更难查。
//   5. 激励在时钟**下降沿**驱动、在上升沿之后采样，天然避开与 DUT 的竞争。
//
// 运行：
//   $ iverilog -g2012 -o sim tb_fsm_3seg.v fsm_3seg.v && vvp sim
//   $ verilator --binary --timing --top-module tb_fsm_3seg tb_fsm_3seg.v fsm_3seg.v
//
// 注意：Verilator 会把「紧跟注释符的 verilator 一词」当成编译指示(metacomment)。
// 上面两行行首加了 `$ ` 就是为了避开这一点——写文档时踩过一次。
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

module tb_fsm_3seg;

    // ---- 参数 ---------------------------------------------------------------
    localparam integer CLK_PERIOD = 10;      // 100 MHz
    localparam integer TIMEOUT_NS = 10_000;

    // ---- DUT 接口 -----------------------------------------------------------
    reg  clk   = 1'b0;
    reg  rst_n = 1'b0;
    reg  start = 1'b0;
    reg  done  = 1'b0;
    wire busy;
    wire valid;

    integer errors = 0;
    integer checks = 0;

    fsm_3seg dut (
        .clk   (clk),
        .rst_n (rst_n),
        .start (start),
        .done  (done),
        .busy  (busy),
        .valid (valid)
    );

    // ---- 时钟 ---------------------------------------------------------------
    // 时钟发生器用阻塞赋值是 testbench 的标准写法（它不是被综合的时序逻辑）。
    // 注：BLKSEQ 规则不区分这种场景，所以这里显式豁免——
    // 豁免必须是"最小范围 + 写明理由"，而不是在命令行上全局 -Wno-BLKSEQ。
    // （另注：注释的第一个词若是 verilator，会被当成编译指示，所以上一行加了"注："）
    /* verilator lint_off BLKSEQ */
    always #(CLK_PERIOD/2) clk = ~clk;
    /* verilator lint_on BLKSEQ */

    // ---- 波形 ---------------------------------------------------------------
    initial begin
        $dumpfile("tb_fsm_3seg.vcd");
        $dumpvars(0, tb_fsm_3seg);
    end

    // ---- 看门狗：挂死也要有结论 ---------------------------------------------
    initial begin
        #TIMEOUT_NS;
        $display("[%0t] FATAL: simulation timeout after %0d ns", $time, TIMEOUT_NS);
        $display("=== TEST FAILED (timeout) ===");
        $finish(1);
    end

    // ---- 检查工具 -----------------------------------------------------------
    // Verilog-2001 没有 string 类型，消息只能塞进定长向量，**超长会被静默截断**。
    // MSG_CHARS 就是消息的字符上限，改消息前先数一下长度（这里 64 字符）。
    // SystemVerilog 里直接用 string 类型，没有这个坑。
    localparam integer MSG_CHARS = 64;

    task check;
        input                     actual;
        input                     expected;
        input [8*MSG_CHARS-1:0]   msg;
        begin
            checks = checks + 1;
            if (actual !== expected) begin
                errors = errors + 1;
                $display("[%0t] FAIL: %0s  expected=%b actual=%b",
                         $time, msg, expected, actual);
            end
        end
    endtask

    // 在下降沿驱动激励，避开与 DUT 在上升沿的采样竞争
    task step;
        input integer n;
        integer i;
        begin
            for (i = 0; i < n; i = i + 1) @(negedge clk);
        end
    endtask

    // ---- 测试主体 -----------------------------------------------------------
    initial begin
        // 复位
        rst_n = 1'b0;
        step(3);
        check(busy,  1'b0, "busy must be low during reset");
        check(valid, 1'b0, "valid must be low during reset");

        rst_n = 1'b1;
        step(2);

        // 用例 1：一次完整的 start -> done 流程
        start = 1'b1;
        step(1);
        start = 1'b0;
        step(1);
        check(busy, 1'b1, "busy should assert after start");

        // 时序要数清楚：valid <= (state == S_DONE)，所以 valid 在“进入 DONE 的
        // 那个时钟沿之后一拍”才拉高，而且只高一拍。多等一拍就会错过它——
        // 这个 off-by-one 正是自检 testbench 存在的意义（第一版就是这么写错的）。
        done = 1'b1;
        step(1);        // 本沿：WAIT -> DONE
        done = 1'b0;
        step(1);        // 本沿：DONE -> IDLE，同时 valid 拉高
        check(valid, 1'b1, "valid should pulse one cycle after DONE state");
        check(busy,  1'b0, "busy should deassert back in IDLE");

        step(1);        // valid 应当已经落回 0
        check(valid, 1'b0, "valid must be a single-cycle pulse");

        // 用例 2：没有 start 时必须保持空闲
        step(5);
        check(busy,  1'b0, "busy must stay low without start");
        check(valid, 1'b0, "valid must stay low without start");

        // ---- 结论 -----------------------------------------------------------
        $display("--------------------------------------------------");
        $display("checks run : %0d", checks);
        $display("failures   : %0d", errors);
        if (errors == 0) begin
            $display("=== TEST PASSED ===");
            $finish;
        end else begin
            $display("=== TEST FAILED ===");
            // ⚠️ 实测过的坑：$finish 的参数是"打印多少统计信息"，不是退出码。
            // 注：两种仿真器跑完都返回 exit code 0，CI 会把失败的用例判成通过。
            // 所以失败路径必须做两件事：
            //   1. 打印固定的 "=== TEST FAILED ===" 供脚本 grep（唯一可移植的判据）；
            //   2. 在支持的仿真器上用 $fatal 真正异常退出。
            // （本行注释刻意不以工具名开头——首词是那个名字会被当成编译指示。）
            `ifdef VERILATOR
                $fatal(1, "self-check reported %0d failure(s)", errors);
            `else
                $finish;
            `endif
        end
    end

endmodule
