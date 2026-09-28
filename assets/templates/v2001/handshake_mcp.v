// -----------------------------------------------------------------------------
// handshake_mcp -- 多 bit 数据跨时钟域（req/ack 握手 + 多周期路径）
//
// 适用：需要把一个 *多 bit* 的值从 src 域搬到 dst 域，但数据更新不频繁
// （配置寄存器、状态快照、测量结果）。相比异步 FIFO，它省掉了整块 RAM。
//
// 原理（MCP, Multi-Cycle Path formulation）：
//   数据总线本身**不加任何同步器**，只靠协议保证 dst 采样时它已经稳定了很久：
//     1. src 把数据锁进 data_q，然后翻转 req。
//     2. req 经两级同步到达 dst，dst 做边沿检测 —— 此时控制链提供了数据稳定窗口；
//        仍需约束数据物理延迟在最早捕获时刻之前完成。
//     3. dst 采样后翻转 ack，ack 同步回 src，src 才允许更新下一个数据。
//   这是异步 bundled-data 握手，不应直接套用同步时钟的 multicycle 例外。
//
// 约束（必须写进 SDC，否则时序工具会按单周期去修它，或者更糟：漏掉它）：
//   set_max_delay -datapath_only <derived_capture_budget> -from [get_pins data_q_reg*/C] \
//                                             -to   [get_pins dst_data_reg*/D]
//   set_false_path 是常见但更粗糙的做法：它完全放弃约束，数据可能晚到得离谱。
//
// 代价：一次传输要往返 4~6 个周期，吞吐低。需要连续高吞吐请用 async_fifo。
// -----------------------------------------------------------------------------
// 复位契约：两域协调复位并丢弃在途数据/事件，各域同步释放；恢复前保持输入无效。
// 不支持传输中任意单侧复位：可能产生伪事件、丢数或握手卡死。
// CDC 物理约束与复位细节见 references/06-clock-reset-cdc.md。
`default_nettype none

module handshake_mcp #(
    parameter integer WIDTH = 32
) (
    // 源域
    input  wire              src_clk,
    input  wire              src_rst_n,
    input  wire              src_valid,     // 请求发送一个新数据（单周期脉冲）
    input  wire [WIDTH-1:0]  src_data,
    output wire              src_busy,      // 高电平期间不接受新的 src_valid
    // 目的域
    input  wire              dst_clk,
    input  wire              dst_rst_n,
    output reg               dst_valid,     // 单周期脉冲，指示 dst_data 有效
    output reg  [WIDTH-1:0]  dst_data
);

    // ---- 源域：锁存数据 + 翻转 req ------------------------------------------
    reg [WIDTH-1:0] data_q;     // 跨域数据，握手期间保持不动
    reg             req_tgl;
    reg             busy;

    always @(posedge src_clk or negedge src_rst_n) begin
        if (!src_rst_n) begin
            data_q  <= {WIDTH{1'b0}};
            req_tgl <= 1'b0;
            busy    <= 1'b0;
        end else if (src_valid && !busy) begin
            data_q  <= src_data;
            req_tgl <= ~req_tgl;
            busy    <= 1'b1;
        end else if (busy && ack_edge) begin
            busy    <= 1'b0;
        end
    end

    assign src_busy = busy;

    // ---- req 同步到目的域 + 边沿检测 ----------------------------------------
    (* ASYNC_REG = "TRUE" *) reg req_s1, req_s2;
    reg req_s3;
    wire req_edge = req_s2 ^ req_s3;

    always @(posedge dst_clk or negedge dst_rst_n) begin
        if (!dst_rst_n) begin
            req_s1 <= 1'b0;
            req_s2 <= 1'b0;
            req_s3 <= 1'b0;
        end else begin
            req_s1 <= req_tgl;
            req_s2 <= req_s1;
            req_s3 <= req_s2;
        end
    end

    // 采样 data_q：握手保持数据，物理约束保证其在此沿之前稳定
    always @(posedge dst_clk or negedge dst_rst_n) begin
        if (!dst_rst_n) begin
            dst_valid <= 1'b0;
            dst_data  <= {WIDTH{1'b0}};
        end else begin
            dst_valid <= req_edge;
            if (req_edge) dst_data <= data_q;
        end
    end

    // ---- ack 翻转并同步回源域 -----------------------------------------------
    reg ack_tgl;
    always @(posedge dst_clk or negedge dst_rst_n) begin
        if (!dst_rst_n)   ack_tgl <= 1'b0;
        else if (req_edge) ack_tgl <= ~ack_tgl;
    end

    (* ASYNC_REG = "TRUE" *) reg ack_s1, ack_s2;
    reg ack_s3;
    wire ack_edge = ack_s2 ^ ack_s3;

    always @(posedge src_clk or negedge src_rst_n) begin
        if (!src_rst_n) begin
            ack_s1 <= 1'b0;
            ack_s2 <= 1'b0;
            ack_s3 <= 1'b0;
        end else begin
            ack_s1 <= ack_tgl;
            ack_s2 <= ack_s1;
            ack_s3 <= ack_s2;
        end
    end

endmodule

`default_nettype wire
