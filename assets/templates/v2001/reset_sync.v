// -----------------------------------------------------------------------------
// reset_sync -- 异步复位、同步释放（reset synchronizer）
//
// 这是 ASIC 流程里复位的默认写法，理由是它同时避开了两种复位各自的坑：
//   - 纯同步复位：复位有效期间必须有时钟，上电/时钟未起振时无法复位。
//   - 纯异步复位（异步释放）：复位撤销的时刻若正好落在时钟有效沿的
//     recovery/removal 窗口内，触发器可能进入亚稳态，而且各触发器
//     退出复位的时刻不一致，状态机可能落进非法状态。
//
// 本模块的做法：复位的“到来”是异步的（立刻生效，不依赖时钟），
// 复位的“撤销”被两级触发器同步到 clk 上，于是整个时钟域里所有触发器
// 在同一个时钟沿一起退出复位。
//
// 用法：每个时钟域实例化一个，把它的 rst_n_sync 作为该域所有触发器的复位。
//
// [FPGA] Xilinx 器件上多数触发器的复位是同步的，Vivado 更推荐直接用同步复位、
//        甚至对数据通路不加复位以省资源；本模块在 FPGA 上主要用于需要
//        “上电即可靠复位”的控制路径。
// -----------------------------------------------------------------------------
`default_nettype none

module reset_sync #(
    parameter integer STAGES = 2
) (
    input  wire clk,
    input  wire arst_n,        // 异步复位输入，低有效
    output wire rst_n_sync     // 同步释放后的复位，低有效，喂给本时钟域
);

    (* ASYNC_REG = "TRUE" *) reg [STAGES-1:0] rst_pipe;

    // 注意 always 块的敏感表里带 arst_n：复位一到立刻把整条链清零（异步生效）；
    // 复位撤销后 1'b1 需要走满 STAGES 拍才出现在输出上（同步释放）。
    always @(posedge clk or negedge arst_n) begin
        if (!arst_n) rst_pipe <= {STAGES{1'b0}};
        else         rst_pipe <= {rst_pipe[STAGES-2:0], 1'b1};
    end

    assign rst_n_sync = rst_pipe[STAGES-1];

endmodule

`default_nettype wire
