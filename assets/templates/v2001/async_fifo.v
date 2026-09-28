// -----------------------------------------------------------------------------
// async_fifo -- 异步 FIFO（格雷码指针，跨时钟域传数据的标准手段）
//
// 结构沿用 Cliff Cummings 的经典设计（SNUG 2002, "Simulation and Synthesis
// Techniques for Asynchronous FIFO Design"）。要点：
//
//   1. 读写指针都比地址多 1 bit。多出来的最高位用来区分“写满一圈”和“读空”，
//      因为满和空的低位地址是一样的。
//   2. 指针跨域前转成格雷码。格雷码相邻两个值只差 1 bit；源端须寄存、逐步递增，
//      并对跨域到第一级同步器的路径约束 skew/最大延迟，防止不同次更新交叠。
//      接收端可跳过中间计数；两级同步降低亚稳态传播概率，不提供绝对保证。
//   3. 满/空判断各自在自己的时钟域算，用的是“本域真指针”与“对域同步过来的指针”，
//      因此判断是保守的：可能短暂地虚报满/空，但绝不会漏报（不会溢出/读空）。
//
//      空： rgray_next == 同步过来的 wgray          （读指针追上写指针）
//      满： wgray_next == {~rgray_sync[MSB:MSB-1], rgray_sync[MSB-2:0]}
//           （高两位取反 == 写指针比读指针多绕了一圈）
//
// 参数约束：ASIZE >= 2（满判断要用到 [ASIZE-2:0]）。深度固定为 2**ASIZE。
//
// 读数据口是**异步读**（组合读出），会推断成分布式 RAM/LUTRAM。
// [FPGA] 若要推断 Block RAM 以省 LUT，需改成寄存输出的变体（读延迟 +1，
//        或加 FWFT 输出寄存器），见 sdp_ram.v 的寄存读法。
// -----------------------------------------------------------------------------
// 复位契约：两域协调复位并丢弃在途数据/事件，各域同步释放；恢复前保持输入无效。
// 不支持传输中任意单侧复位：可能产生伪事件、丢数或握手卡死。
// CDC 物理约束与复位细节见 references/06-clock-reset-cdc.md。
`default_nettype none

module async_fifo #(
    parameter integer DSIZE = 8,     // 数据位宽
    parameter integer ASIZE = 4      // 地址位宽，深度 = 2**ASIZE，要求 >= 2
) (
    // 写时钟域
    input  wire              wr_clk,
    input  wire              wr_rst_n,
    input  wire              wr_en,
    input  wire [DSIZE-1:0]  wr_data,
    output wire              wr_full,
    // 读时钟域
    input  wire              rd_clk,
    input  wire              rd_rst_n,
    input  wire              rd_en,
    output wire [DSIZE-1:0]  rd_data,
    output wire              rd_empty
);

    reg [DSIZE-1:0] mem [0:(2**ASIZE)-1];

    // ---- 写指针（写时钟域） -------------------------------------------------
    reg  [ASIZE:0] wbin, wgray;
    wire [ASIZE:0] wbin_next  = wbin + {{ASIZE{1'b0}}, (wr_en & ~wr_full)};
    wire [ASIZE:0] wgray_next = (wbin_next >> 1) ^ wbin_next;

    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            wbin  <= {(ASIZE+1){1'b0}};
            wgray <= {(ASIZE+1){1'b0}};
        end else begin
            wbin  <= wbin_next;
            wgray <= wgray_next;
        end
    end

    always @(posedge wr_clk) begin
        if (wr_en && !wr_full) mem[wbin[ASIZE-1:0]] <= wr_data;
    end

    // ---- 读指针（读时钟域） -------------------------------------------------
    reg  [ASIZE:0] rbin, rgray;
    wire [ASIZE:0] rbin_next  = rbin + {{ASIZE{1'b0}}, (rd_en & ~rd_empty)};
    wire [ASIZE:0] rgray_next = (rbin_next >> 1) ^ rbin_next;

    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rbin  <= {(ASIZE+1){1'b0}};
            rgray <= {(ASIZE+1){1'b0}};
        end else begin
            rbin  <= rbin_next;
            rgray <= rgray_next;
        end
    end

    assign rd_data = mem[rbin[ASIZE-1:0]];

    // ---- 指针跨域同步（各两级） ---------------------------------------------
    (* ASYNC_REG = "TRUE" *) reg [ASIZE:0] rgray_s1, rgray_s2;  // r -> wr_clk
    (* ASYNC_REG = "TRUE" *) reg [ASIZE:0] wgray_s1, wgray_s2;  // w -> rd_clk

    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            rgray_s1 <= {(ASIZE+1){1'b0}};
            rgray_s2 <= {(ASIZE+1){1'b0}};
        end else begin
            rgray_s1 <= rgray;
            rgray_s2 <= rgray_s1;
        end
    end

    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            wgray_s1 <= {(ASIZE+1){1'b0}};
            wgray_s2 <= {(ASIZE+1){1'b0}};
        end else begin
            wgray_s1 <= wgray;
            wgray_s2 <= wgray_s1;
        end
    end

    // ---- 满 / 空 ------------------------------------------------------------
    // 空：读指针（下一拍值）与同步过来的写指针完全相等。
    reg rd_empty_r;
    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) rd_empty_r <= 1'b1;      // 复位后是空的
        else           rd_empty_r <= (rgray_next == wgray_s2);
    end
    assign rd_empty = rd_empty_r;

    // 满：写指针（下一拍值）的高两位与同步过来的读指针高两位相反，低位相同。
    reg wr_full_r;
    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) wr_full_r <= 1'b0;
        else           wr_full_r <= (wgray_next ==
                                     {~rgray_s2[ASIZE:ASIZE-1],
                                       rgray_s2[ASIZE-2:0]});
    end
    assign wr_full = wr_full_r;

endmodule

`default_nettype wire
