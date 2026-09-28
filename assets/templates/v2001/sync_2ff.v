// -----------------------------------------------------------------------------
// sync_2ff -- 两级触发器同步器（单 bit 电平信号跨时钟域）
//
// 用途：把一个来自其它时钟域的 *单 bit* 信号安全地搬到 clk 域。
//
// 只对以下情况有效，用错就是设计缺陷：
//   - 只能同步 1 bit。多 bit 数据各自打两拍会因各 bit 收敛时刻不同而撕裂，
//     必须改用格雷码 / 握手 / 异步 FIFO（见 handshake_mcp.v、async_fifo.v）。
//   - 输入 d_async 必须是源时钟域某个触发器的输出，不能是组合逻辑的输出，
//     否则组合毛刺会被采样成一个真实的脉冲。
//   - 电平信号用本模块；单周期脉冲跨域请用 pulse_sync.v（慢时钟域会漏采脉冲）。
//
// 为什么是两级：第一级采到亚稳态时，第二级给它一整个时钟周期解析，
// 把 MTBF 推高到工程可接受的量级。极高频或高可靠场景用三级。
//
// [FPGA] 综合属性 ASYNC_REG=TRUE 让 Vivado 把两个触发器摆在同一个 slice 里
//        并禁止它们被优化/复制，同时告诉时序引擎这条路径不必满足 setup。
// [ASIC] 换成库里的同步器单元或加 set_false_path / dont_touch 约束。
// -----------------------------------------------------------------------------
`default_nettype none

module sync_2ff #(
    parameter integer STAGES   = 2,      // 同步级数，2 或 3
    parameter         RST_VAL  = 1'b0    // 复位后的输出值
) (
    input  wire clk,
    input  wire rst_n,
    input  wire d_async,                 // 来自其它时钟域，必须是寄存器输出
    output wire q_sync
);

    (* ASYNC_REG = "TRUE" *) reg [STAGES-1:0] sync_q;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) sync_q <= {STAGES{RST_VAL}};
        else        sync_q <= {sync_q[STAGES-2:0], d_async};
    end

    assign q_sync = sync_q[STAGES-1];

endmodule

`default_nettype wire
