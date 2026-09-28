// -----------------------------------------------------------------------------
// fsm_3seg_sv -- 三段式状态机的 SystemVerilog 可综合子集写法
//
// 相对 Verilog-2001 版本，SV 在这里带来的是**可检查性**，不是语法糖：
//
//   always_ff  / always_comb  向工具声明了意图，工具因此能反查"意图与结果不符"：
//                             Design Compiler 在 always_comb 里推出 latch 时报 ELAB-974，
//                             Vivado 报 [Synth 8-327]。
//                             ⚠️ 但这两条都是 **WARNING 不是 ERROR**——IEEE 1800 对这类
//                             检查用的措辞是 "recommended that software tools perform
//                             additional checks"，并非强制。所以 always_comb **不是**
//                             锁存器防火墙。消 latch 唯一可靠的手段仍然是像下面第二段
//                             那样在块首给所有输出赋默认值；并且要在 CI 里把
//                             ELAB-974 / Synth 8-327 升级成 error。
//   always_comb               敏感表由工具推导，彻底消灭"敏感表写漏"这类 bug，
//                             而且它会在时刻 0 自动执行一次。
//   enum logic [N-1:0]        状态变量有了类型。波形里直接显示 S_RUN 而不是 2'b01，
//                             并且把状态变量误当数用（state + 1）会被工具挡下。
//   unique case               告诉工具分支互斥且已覆盖全部合法取值；仿真时若同时
//                             命中多个分支或一个都没命中，会立刻报错。
//
// 注意 unique case 与 default 的关系：加了 unique 仍然建议保留 default。
// unique 只在**仿真**时报错，综合时它等价于 full_case+parallel_case 的承诺；
// 若真的进入了未列举的状态（例如单粒子翻转），没有 default 就无法回到安全态。
// 对安全关键设计，用 default 显式回 IDLE 比依赖 unique 更稳妥。
// -----------------------------------------------------------------------------
`default_nettype none

module fsm_3seg_sv (
    input  logic clk,
    input  logic rst_n,
    input  logic start,
    input  logic done,
    output logic busy,
    output logic valid
);

    typedef enum logic [1:0] {
        S_IDLE = 2'd0,
        S_RUN  = 2'd1,
        S_WAIT = 2'd2,
        S_DONE = 2'd3
    } state_e;

    state_e state, next_state;

    // ---- 第一段：状态寄存 ----------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= S_IDLE;
        else        state <= next_state;
    end

    // ---- 第二段：次态译码（纯组合） ------------------------------------------
    always_comb begin
        next_state = state;                 // 默认保持，杜绝锁存器
        unique case (state)
            S_IDLE: if (start) next_state = S_RUN;
            S_RUN:             next_state = S_WAIT;
            S_WAIT: if (done)  next_state = S_DONE;
            S_DONE:            next_state = S_IDLE;
            default:           next_state = S_IDLE;   // 非法态回安全态
        endcase
    end

    // ---- 第三段：输出寄存化 --------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy  <= 1'b0;
            valid <= 1'b0;
        end else begin
            busy  <= (next_state != S_IDLE);
            valid <= (state == S_DONE);
        end
    end

endmodule

`default_nettype wire
