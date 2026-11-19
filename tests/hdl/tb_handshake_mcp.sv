`timescale 1ns/1ps
module tb_handshake_mcp #(parameter S_HALF = 3, D_HALF = 7);
    reg src_clk = 0, dst_clk = 0, src_rst_n = 0, dst_rst_n = 0, src_valid = 0;
    reg [15:0] src_data;
    wire src_busy, dst_valid;
    wire [15:0] dst_data;
    handshake_mcp #(.WIDTH(16)) dut(
        .src_clk(src_clk), .src_rst_n(src_rst_n), .src_valid(src_valid),
        .src_data(src_data), .src_busy(src_busy), .dst_clk(dst_clk),
        .dst_rst_n(dst_rst_n), .dst_valid(dst_valid), .dst_data(dst_data));
    always #(S_HALF) src_clk = ~src_clk;
    initial begin
        #1;
        forever #(D_HALF) dst_clk = ~dst_clk;
    end

    reg [15:0] expected [0:39];
    integer sent, delivered, while_busy;
    always @(posedge src_clk) begin
        if (src_rst_n && src_valid) begin
            if ($isunknown(src_busy)) $fatal(1, "unknown busy");
            if (src_busy) while_busy = while_busy + 1;
            else begin
                expected[sent] = src_data;
                sent = sent + 1;
            end
        end
    end
    always @(posedge dst_clk) begin
        if (dst_rst_n) begin
            if ($isunknown(dst_valid)) $fatal(1, "unknown destination valid");
            if (dst_valid) begin
                if (delivered >= sent) $fatal(1, "duplicate delivery");
                if (dst_data !== expected[delivered]) $fatal(1, "wrong MCP payload");
                delivered = delivered + 1;
            end
        end
    end
    task reset_link;
        src_valid = 0;
        src_rst_n = 0;
        dst_rst_n = 0;
        sent = 0;
        delivered = 0;
        while_busy = 0;
        fork
            begin repeat (3) @(posedge src_clk); src_rst_n <= 1; end
            begin repeat (3) @(posedge dst_clk); dst_rst_n <= 1; end
        join
        @(negedge src_clk);
        if (src_busy !== 1'b0) $fatal(1, "busy after reset");
    endtask
    task send(input [15:0] value);
        @(negedge src_clk);
        while (src_busy) @(negedge src_clk);
        src_valid = 1;
        src_data = value;
        @(negedge src_clk);
        src_valid = 0;
        src_data = ~value;
        if (src_busy !== 1'b1) $fatal(1, "missing busy");
    endtask

    initial begin
        reset_link();
        send(16'hdead);
        if (sent != 1 || delivered != 0) $fatal(1, "expected request in flight");
        reset_link();
        repeat (8) @(posedge dst_clk);
        for (int i = 0; i < 24; i++) begin
            send(16'h9231 + 37*i);
            // One extra request during busy. It must never reach the receiver.
            @(negedge src_clk);
            src_valid = 1;
            @(negedge src_clk);
            src_valid = 0;
        end
        wait (src_busy === 1'b0);
        repeat (8) @(posedge dst_clk);
        @(negedge dst_clk);
        if (sent != 24 || delivered != 24 || while_busy != 24)
            $fatal(1, "lost request or accepted while busy");
        $display("PASS handshake_mcp half-periods=%0d/%0d delivered=%0d", S_HALF, D_HALF, delivered);
        $finish;
    end
    initial #100000 $fatal(1, "MCP timeout");
endmodule
