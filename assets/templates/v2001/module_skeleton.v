// =============================================================================
// 模块名   : module_skeleton
// 功能     : <一句话说清这个模块干什么>
// 作者     : <name>
// 时钟域   : clk（单一时钟域）
// 复位     : rst_n，低有效，异步复位 / 同步释放（由 reset_sync 产生）
// 依赖     : <被例化的子模块>
// -----------------------------------------------------------------------------
// 设计要点 :
//   - 单级 valid/ready 流水，in_ready 在下游可收或输出寄存器为空时拉高
//   - 上游必须遵守：valid 拉高后在 ready 到来前不得撤销，且 data 保持不变
// CDC      : 无跨时钟域路径。若引入，必须走 sync_2ff / handshake_mcp / async_fifo
// =============================================================================

// `default_nettype none 让任何未声明的标识符变成编译错误，而不是被默默当成
// 1 bit wire。打错一个信号名就地报错，是最便宜的一道防线。
// 文件末尾改回 wire，否则会污染后续被编译的文件。
`default_nettype none

module module_skeleton #(
    // 对外可调的用 parameter；模块内部推导量一律用 localparam，
    // 免得被上层 #() 意外改掉而破坏内部一致性。
    parameter integer DATA_W = 32
) (
    // 时钟与复位永远排最前，全项目统一命名 clk / rst_n
    input  wire                 clk,
    input  wire                 rst_n,

    // 上游
    input  wire                 in_valid,
    input  wire [DATA_W-1:0]    in_data,
    output wire                 in_ready,

    // 下游
    output reg                  out_valid,
    output reg  [DATA_W-1:0]    out_data,
    input  wire                 out_ready
);

    // ---- 内部信号：集中声明，一行一个，写清用途 ------------------------------
    wire handshake;   // 本拍成功收下一个数据

    // ---- 组合逻辑：连续赋值 / always @(*) 内用阻塞赋值 = ----------------------
    assign in_ready  = out_ready | ~out_valid;
    assign handshake = in_valid & in_ready;

    // ---- 时序逻辑：always @(posedge clk ...) 内用非阻塞赋值 <= ----------------
    // 一个 always 块只做一件事，且只被一个时钟沿驱动。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid <= 1'b0;
            out_data  <= {DATA_W{1'b0}};
        end else if (in_ready) begin
            // in_ready 为高时输出寄存器可被覆盖：要么下游收走了，要么本来就是空的
            out_valid <= in_valid;
            if (handshake) out_data <= in_data;
        end
    end

    // ---- 参数合法性检查（详细展开时机：elaboration，综合器会忽略 initial） ----
    // 注意：$error/$fatal/assert 属于 SystemVerilog。纯 Verilog-2001 用
    // $display + $finish，可移植性最好。
    // synthesis translate_off
    initial begin
        if (DATA_W <= 0) begin
            $display("ERROR: %m: DATA_W must be positive, got %0d", DATA_W);
            $finish;
        end
    end
    // synthesis translate_on

endmodule

`default_nettype wire
