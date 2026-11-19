`timescale 1ns/1ps
module tb_sdp_ram;
    localparam AW = 2, DW = 8, DEPTH = 1 << AW;
    reg clk = 0, we = 0, re = 0;
    reg [AW-1:0] waddr, raddr;
    reg [DW-1:0] wdata;
    wire [DW-1:0] rdata;
    always #5 clk = ~clk;
    sdp_ram #(.AW(AW), .DW(DW)) dut(.clk(clk), .we(we), .waddr(waddr), .wdata(wdata),
                                      .re(re), .raddr(raddr), .rdata(rdata));
    reg [DW-1:0] memory [0:DEPTH-1];
    reg [DW-1:0] held;
    bit known = 0;
    integer checks = 0;

    // Called on a falling edge. Sample both before and after the active edge.
    task cycle(input bit write_en, read_en, input [AW-1:0] wa, ra, input [DW-1:0] data);
        we = write_en;
        re = read_en;
        waddr = wa;
        raddr = ra;
        wdata = data;
        #1;
        if (known && rdata !== held) $fatal(1, "read output changed before clock");
        if (re) begin
            held = memory[ra];       // old value on same-address read/write
            known = 1;
        end
        if (we) memory[wa] = data;
        @(negedge clk);
        if (known && rdata !== held) $fatal(1, "RAM read-first or hold");
        checks = checks + 1;
    endtask
    initial begin
        @(negedge clk);
        for (int a = 0; a < DEPTH; a++) cycle(1, 0, a, 0, 8'h41 + a);
        cycle(0, 1, 0, 0, 0);
        for (int enables = 0; enables < 4; enables++)
            for (int w = 0; w < DEPTH; w++)
                for (int r = 0; r < DEPTH; r++)
                    cycle(enables[1], enables[0], w, r, checks+8'h90);
        $display("PASS sdp_ram cycles=%0d", checks);
        $finish;
    end
    initial #5000 $fatal(1, "RAM timeout");
endmodule
