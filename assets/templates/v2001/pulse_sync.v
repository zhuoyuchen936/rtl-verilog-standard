// -----------------------------------------------------------------------------
// pulse_sync -- 单周期脉冲跨时钟域（toggle 同步器）
//
// 为什么不能直接用 sync_2ff：sync_2ff 同步的是*电平*。源域一个只持续 1 个周期的
// 脉冲，如果目的域时钟更慢，采样时很可能整个错过它。
//
// 做法：把“脉冲”变成“电平翻转”——源域每来一个脉冲就把 toggle 取反。电平能被
// 稳稳同步过去，目的域再对同步后的电平做边沿检测，还原成 1 个周期的脉冲。
//
// 使用限制（重要）：两次输入脉冲之间必须至少间隔目的域的 2~3 个时钟周期，
// 否则 toggle 翻转过快，目的域会漏掉。若源域快、目的域慢且脉冲密集，
// 应改用带 ack 的握手（handshake_mcp.v）或异步 FIFO。
// -----------------------------------------------------------------------------
// 复位契约：两域协调复位并丢弃在途数据/事件，各域同步释放；恢复前保持输入无效。
// 不支持传输中任意单侧复位：可能产生伪事件、丢数或握手卡死。
// CDC 物理约束与复位细节见 references/06-clock-reset-cdc.md。
`default_nettype none

module pulse_sync (
    input  wire src_clk,
    input  wire src_rst_n,
    input  wire src_pulse,     // src_clk 域，单周期脉冲
    input  wire dst_clk,
    input  wire dst_rst_n,
    output reg  dst_pulse      // dst_clk 域，单周期脉冲
);

    // 源域：脉冲 -> 电平翻转
    reg toggle;
    always @(posedge src_clk or negedge src_rst_n) begin
        if (!src_rst_n) toggle <= 1'b0;
        else if (src_pulse) toggle <= ~toggle;
    end

    // 目的域：两级同步 + 第三级用于边沿检测
    (* ASYNC_REG = "TRUE" *) reg sync1, sync2;
    reg sync3;
    always @(posedge dst_clk or negedge dst_rst_n) begin
        if (!dst_rst_n) begin
            sync1 <= 1'b0;
            sync2 <= 1'b0;
            sync3 <= 1'b0;
        end else begin
            sync1 <= toggle;
            sync2 <= sync1;
            sync3 <= sync2;
        end
    end

    // 电平翻转的任一方向都代表一次脉冲，所以用异或做边沿检测
    always @(posedge dst_clk or negedge dst_rst_n) begin
        if (!dst_rst_n) dst_pulse <= 1'b0;
        else            dst_pulse <= sync2 ^ sync3;
    end

endmodule

`default_nettype wire
