`timescale 1ns/1ps
module tb_async_fifo #(parameter ASIZE = 2, W_HALF = 3, R_HALF = 7, PHASE = 1);
    localparam DEPTH = 1 << ASIZE;
    reg wr_clk = 0, rd_clk = 0, wr_rst_n = 0, rd_rst_n = 0;
    reg wr_en = 0, rd_en = 0;
    reg [15:0] wr_data;
    wire [15:0] rd_data;
    wire wr_full, rd_empty;
    async_fifo #(.DSIZE(16), .ASIZE(ASIZE)) dut(
        .wr_clk(wr_clk), .wr_rst_n(wr_rst_n), .wr_en(wr_en), .wr_data(wr_data), .wr_full(wr_full),
        .rd_clk(rd_clk), .rd_rst_n(rd_rst_n), .rd_en(rd_en), .rd_data(rd_data), .rd_empty(rd_empty));
    always #(W_HALF) wr_clk = ~wr_clk;
    initial begin
        #(PHASE);
        forever #(R_HALF) rd_clk = ~rd_clk;
    end

    // The tested half-periods and phase are odd. Read and write sampling edges
    // never coincide, so these independent interface monitors have a defined order.
    reg [15:0] expected [0:32*DEPTH+31];
    integer written = 0, consumed = 0, serial = 0;
    always @(posedge wr_clk) begin
        if (wr_rst_n && wr_en) begin
            if ($isunknown(wr_full)) $fatal(1, "unknown full");
            if (!wr_full) begin
                if (written-consumed >= DEPTH) $fatal(1, "accepted a write while full");
                expected[written] = wr_data;
                written = written + 1;
            end
        end
    end
    always @(posedge rd_clk) begin
        if (rd_rst_n && rd_en) begin
            if ($isunknown(rd_empty)) $fatal(1, "unknown empty");
            if (!rd_empty) begin
                if (consumed >= written) $fatal(1, "accepted an empty read");
                if (rd_data !== expected[consumed]) $fatal(1, "FIFO payload or order");
                consumed = consumed + 1;
            end
        end
    end

    task reset_fifo;
        wr_en = 0;
        rd_en = 0;
        wr_rst_n = 0;
        rd_rst_n = 0;
        written = 0;
        consumed = 0;
        fork
            begin repeat (3) @(posedge wr_clk); wr_rst_n <= 1; end
            begin repeat (3) @(posedge rd_clk); rd_rst_n <= 1; end
        join
        @(negedge rd_clk);
        if (rd_empty !== 1'b1 || wr_full !== 1'b0) $fatal(1, "FIFO reset flags");
    endtask
    task write_step(input bit enable);
        @(negedge wr_clk);
        serial = serial + 1;
        wr_data = serial[15:0];
        wr_en = enable;
    endtask
    task read_step(input bit enable);
        @(negedge rd_clk);
        rd_en = enable;
    endtask
    task fill;
        integer before_write;
        before_write = written;
        repeat (DEPTH+6) write_step(1);
        write_step(0);
        if (written-before_write != DEPTH || wr_full !== 1'b1) $fatal(1, "FIFO fill");
    endtask
    task drain;
        repeat (DEPTH+8) read_step(1);
        read_step(0);
        if (consumed != written || rd_empty !== 1'b1) $fatal(1, "FIFO drain");
    endtask

    initial begin
        reset_fifo();
        drain();                       // attempted reads on empty
        fill();                        // attempted writes on full
        reset_fifo();                  // discard a full FIFO in both domains
        drain();
        fill();
        drain();
        fork
            begin
                for (int i = 0; i < 24*DEPTH; i++) write_step(i % 7 != 3);
                write_step(0);
            end
            begin
                for (int i = 0; i < 24*DEPTH; i++) read_step(i % 9 < 7);
                read_step(0);
            end
        join
        drain();
        if (written < 3*DEPTH) $fatal(1, "insufficient wraparound coverage");
        $display("PASS async_fifo depth=%0d half-periods=%0d/%0d transfers=%0d",
                 DEPTH, W_HALF, R_HALF, consumed);
        $finish;
    end
    initial #100000 $fatal(1, "FIFO timeout");
endmodule
