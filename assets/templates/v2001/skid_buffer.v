// -----------------------------------------------------------------------------
// skid_buffer -- ready/valid 握手的流水打拍器（AXI-Stream 风格）
//
// 解决的问题：valid/ready 握手里，ready 是从下游一路组合回传到上游的。链路一长，
// ready 就成了关键路径。要打断它就得把 ready 也寄存，但一旦 ready 寄存，
// 上游在看到 ready 拉低之前还会再送一拍数据进来 —— 这一拍必须有地方接住，
// 否则就丢数据。skid buffer 就是那个“接住一拍”的备用寄存器。
//
// 性质：
//   - 输出 m_valid / m_data 都是寄存器输出，s_ready 也是寄存器输出，
//     上下游之间没有组合直通路径，可以随便级联。
//   - 满吞吐：下游不停的话，每周期都能收一个数（不像简单打拍会掉一半带宽）。
//   - 代价：无背压时 1 拍延迟、2 组数据寄存器；背压会增加等待时间。
//
// 握手约定（AXI 规则，必须遵守）：valid 一旦拉高，在 ready 到来之前不能撤，
// 且 data 必须保持不变；源端不能等待 ready 才拉高 valid；接收端 ready 可以依赖 valid，避免组合环。
// -----------------------------------------------------------------------------
`default_nettype none

module skid_buffer #(
    parameter integer WIDTH = 32
) (
    input  wire              clk,
    input  wire              rst_n,
    // 上游
    input  wire              s_valid,
    output wire              s_ready,
    input  wire [WIDTH-1:0]  s_data,
    // 下游
    output wire              m_valid,
    input  wire              m_ready,
    output wire [WIDTH-1:0]  m_data
);

    reg              out_valid;
    reg [WIDTH-1:0]  out_data;
    reg              skid_valid;
    reg [WIDTH-1:0]  skid_data;

    // 备用寄存器空着就能收 —— 这就是被寄存的 ready，无组合直通。
    assign s_ready = ~skid_valid;
    assign m_valid = out_valid;
    assign m_data  = out_data;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid  <= 1'b0;
            out_data   <= {WIDTH{1'b0}};
            skid_valid <= 1'b0;
            skid_data  <= {WIDTH{1'b0}};
        end else begin
            // 下游卡住且输出寄存器已占用时，把这一拍先塞进备用寄存器
            if (s_valid && s_ready && out_valid && !m_ready) begin
                skid_valid <= 1'b1;
                skid_data  <= s_data;
            end

            // 输出寄存器空出来了：优先排空备用寄存器，保证数据不乱序
            if (m_ready || !out_valid) begin
                if (skid_valid) begin
                    out_valid  <= 1'b1;
                    out_data   <= skid_data;
                    skid_valid <= 1'b0;
                end else begin
                    out_valid  <= s_valid & s_ready;
                    out_data   <= s_data;
                end
            end
        end
    end

endmodule

`default_nettype wire
