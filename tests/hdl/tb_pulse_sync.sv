`timescale 1ns/1ps
module tb_pulse_sync;
    reg src_clk = 0, dst_clk = 0, src_rst_n = 0, dst_rst_n = 0, src_pulse = 0;
    wire dst_pulse;
    pulse_sync dut(.src_clk(src_clk), .src_rst_n(src_rst_n), .src_pulse(src_pulse),
                   .dst_clk(dst_clk), .dst_rst_n(dst_rst_n), .dst_pulse(dst_pulse));
    always #3 src_clk = ~src_clk;
    initial begin
        #1;
        forever #7 dst_clk = ~dst_clk;
    end
    integer received = 0;
    reg last_pulse;
    always @(posedge dst_clk) begin
        if (!dst_rst_n) begin
            last_pulse = 0;
            received = 0;
        end else begin
            if ($isunknown(dst_pulse)) $fatal(1, "unknown pulse");
            if (dst_pulse && last_pulse) $fatal(1, "pulse wider than one cycle");
            if (dst_pulse) received = received + 1;
            last_pulse = dst_pulse;
        end
    end
    task reset_link;
        src_pulse = 0;
        src_rst_n = 0;
        dst_rst_n = 0;
        fork
            begin repeat (3) @(posedge src_clk); src_rst_n <= 1; end
            begin repeat (3) @(posedge dst_clk); dst_rst_n <= 1; end
        join
        repeat (6) @(negedge dst_clk);
        if (received != 0) $fatal(1, "spurious pulse after reset");
    endtask
    task pulse;
        @(negedge src_clk);
        src_pulse = 1;
        @(negedge src_clk);
        src_pulse = 0;
    endtask
    initial begin
        reset_link();
        pulse();                     // flush an event still in the destination pipeline
        reset_link();
        for (int i = 1; i <= 16; i++) begin
            pulse();
            repeat (7) @(negedge dst_clk);
            if (received != i) $fatal(1, "event count");
        end
        $display("PASS pulse_sync events=%0d", received);
        $finish;
    end
    initial #10000 $fatal(1, "pulse timeout");
endmodule
