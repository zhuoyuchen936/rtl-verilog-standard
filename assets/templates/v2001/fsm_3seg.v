// -----------------------------------------------------------------------------
// fsm_3seg -- 三段式同步状态机模板
//
// 三段的分工（这是本规范推荐的默认状态机写法）：
//   第一段  时序：state <= next_state         —— 只做状态寄存，非阻塞赋值
//   第二段  组合：由 state + 输入算 next_state —— 阻塞赋值，必须有 default
//   第三段  时序：由 state/next_state 算输出   —— 输出寄存化，无组合毛刺
//
// 为什么不用一段式：一段式把状态转移和输出混在一个时序块里，状态多了以后
// 极难读、难改，且输出与状态的对应关系被埋在分支里。
// 为什么不用两段式（输出用组合）：组合输出会带毛刺，跨模块使用时容易出问题，
// 也会把本模块的组合延时接到下游的关键路径上。
//
// 关键纪律：
//   1. 第二段组合块开头先给 next_state 赋默认值（保持当前态），
//      再在分支里覆盖 —— 这样任何没写到的路径都不会推断出锁存器。
//   2. case 一定要有 default。对“存在非法状态”的状态机（状态数不是 2 的幂），
//      default 要把状态拉回安全态，否则一旦因单粒子翻转等原因进入非法状态就再也出不来。
//   3. 状态编码用 localparam，不要用 `define（`define 是全局的，会污染整个编译单元）。
// -----------------------------------------------------------------------------
`default_nettype none

module fsm_3seg (
    input  wire clk,
    input  wire rst_n,
    input  wire start,        // 请求开始
    input  wire done,         // 下游完成
    output reg  busy,         // 正在处理（已寄存）
    output reg  valid         // 本次处理完成，打一拍的脉冲（已寄存）
);

    // ---- 状态编码 -----------------------------------------------------------
    // 4 个状态用 2 bit 二进制编码。若状态数多且面向 FPGA，可考虑独热码
    // （触发器换组合逻辑，通常更快）；ASIC 上一般让综合器自己选。
    localparam [1:0] S_IDLE = 2'd0,
                     S_RUN  = 2'd1,
                     S_WAIT = 2'd2,
                     S_DONE = 2'd3;

    reg [1:0] state, next_state;

    // ---- 第一段：状态寄存（时序，非阻塞赋值） --------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= S_IDLE;
        else        state <= next_state;
    end

    // ---- 第二段：次态译码（组合，阻塞赋值） ----------------------------------
    always @(*) begin
        next_state = state;               // 默认保持，杜绝锁存器
        case (state)
            S_IDLE: if (start) next_state = S_RUN;
            S_RUN:             next_state = S_WAIT;
            S_WAIT: if (done)  next_state = S_DONE;
            S_DONE:            next_state = S_IDLE;
            default:           next_state = S_IDLE;   // 非法态回到安全态
        endcase
    end

    // ---- 第三段：输出寄存化（时序，非阻塞赋值） ------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy  <= 1'b0;
            valid <= 1'b0;
        end else begin
            // 用 next_state 译码可让输出与状态同拍到达；用 state 译码则晚一拍。
            busy  <= (next_state != S_IDLE);
            valid <= (state == S_DONE);
        end
    end

endmodule

`default_nettype wire
