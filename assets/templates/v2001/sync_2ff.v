// -----------------------------------------------------------------------------
// sync_2ff -- 两级触发器同步器（单 bit 电平信号跨时钟域）
//
// 用途：把一个来自其它时钟域的 *单 bit* 信号安全地搬到 clk 域。
//
// 只对以下情况有效，用错就是设计缺陷：
//   - 只能同步 1 bit。多 bit 数据各自打两拍会因各 bit 收敛时刻不同而撕裂，
//     必须改用格雷码 / 握手 / 异步 FIFO（见 handshake_mcp.v、async_fifo.v）。
//   - 片内信号优先在源域寄存以消除毛刺。外部异步输入按电气特性滤波，
//     并保证需要观测的电平保持足够长。
//   - 电平信号用本模块；单周期脉冲跨域请用 pulse_sync.v（慢时钟域会漏采脉冲）。
//
// 按接收时钟、输入翻转率、器件和可用解析时间核对 MTBF，选择同步级数。
//
// [FPGA] Vivado 用 ASYNC_REG 标识、保护同步链并引导紧邻布局。另行约束
//        异步输入到首级 D 的路径。首级 Q 到次级 D 按接收时钟检查 setup/hold。
// [ASIC] 按工艺库选择同步器单元，并核对级间布线及解析时间。
// -----------------------------------------------------------------------------
`default_nettype none

module sync_2ff #(
    parameter integer STAGES   = 2,      // 同步级数，2 或 3
    parameter         RST_VAL  = 1'b0    // 复位后的输出值
) (
    input  wire clk,
    input  wire rst_n,
    input  wire d_async,                 // 满足保持时间要求的异步电平
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
