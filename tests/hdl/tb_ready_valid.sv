`timescale 1ns/1ps
module tb_ready_valid #(parameter CAPACITY = 2);
    reg clk = 0, rst_n = 0, s_valid = 0, m_ready = 0;
    reg [8:0] s_data;
    wire s_ready, m_valid;
    wire [8:0] m_data;
    always #5 clk = ~clk;

    if (CAPACITY == 2) begin : gen_skid
        skid_buffer #(.WIDTH(9)) dut(.clk(clk), .rst_n(rst_n),
            .s_valid(s_valid), .s_ready(s_ready), .s_data(s_data),
            .m_valid(m_valid), .m_ready(m_ready), .m_data(m_data));
    end else begin : gen_single
        module_skeleton #(.DATA_W(9)) dut(.clk(clk), .rst_n(rst_n),
            .in_valid(s_valid), .in_ready(s_ready), .in_data(s_data),
            .out_valid(m_valid), .out_ready(m_ready), .out_data(m_data));
    end

    reg [8:0] expected [0:15];
    integer sent, received, transfers = 0;
    reg waiting, stalled;
    reg [8:0] held;

    task reset_buffer;
        @(negedge clk);
        s_valid = 0;
        m_ready = 0;
        rst_n = 0;
        @(negedge clk);
        if (m_valid !== 1'b0) $fatal(1, "flush retained a transaction");
        rst_n = 1;
        sent = 0;
        received = 0;
        waiting = 0;
        stalled = 0;
    endtask

    task cycle(input bit offer, input bit accept);
        @(negedge clk);
        if (!waiting) begin
            s_valid = offer;
            // Carry a changing last-bit sideband together with the data.
            s_data = {sent[0], 8'h53 ^ sent[7:0]};
        end
        m_ready = accept;
        @(posedge clk);
        if (s_ready !== 1'b0 && s_ready !== 1'b1) $fatal(1, "unknown input ready");
        if (m_valid !== (sent != received)) $fatal(1, "wrong output valid or latency");
        if (stalled && (m_valid !== 1'b1 || m_data !== held))
            $fatal(1, "stalled output changed");
        if (m_valid && m_ready) begin
            if (m_data !== expected[received]) $fatal(1, "output order or payload");
            received = received + 1;
            transfers = transfers + 1;
        end
        if (s_valid && s_ready) begin
            expected[sent] = s_data;
            sent = sent + 1;
        end
        if (sent - received > CAPACITY) $fatal(1, "accepted beyond capacity");
        waiting = s_valid && !s_ready;
        stalled = m_valid && !m_ready;
        held = m_data;
    endtask

    integer pattern, i;
    initial begin
        reset_buffer();
        repeat (CAPACITY) cycle(1, 0);
        if (sent != CAPACITY || received != 0) $fatal(1, "capacity before flush");
        reset_buffer();
        repeat (6) cycle(1, 1);
        if (sent != 6 || received != 5) $fatal(1, "one-stage latency or II=1");
        cycle(0, 1);
        for (pattern = 0; pattern < 4096; pattern = pattern + 1) begin
            reset_buffer();
            for (i = 0; i < 6; i = i + 1) cycle(pattern[2*i], pattern[2*i+1]);
            repeat (4) cycle(0, 1);
            if (sent != received || waiting || m_valid !== 1'b0) $fatal(1, "drain lost data");
        end
        $display("PASS ready_valid capacity=%0d patterns=4096 transfers=%0d", CAPACITY, transfers);
        $finish;
    end
    initial #1000000 $fatal(1, "ready/valid timeout");
endmodule
