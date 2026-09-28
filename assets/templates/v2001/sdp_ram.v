// -----------------------------------------------------------------------------
// sdp_ram -- 简单双口 RAM（一个写口 + 一个读口，同一时钟）
//
// 这是能被综合器识别成片上 RAM 的**标准推断模板**，写法上有几处不能改：
//
//   1. 写和读放在同一个 `always @(posedge clk)` 里，且**都不带复位**。
//      片上 RAM 的存储阵列本身没有复位端；一旦给 mem 或 rdata 写了复位分支，
//      综合器就只能改用触发器实现，资源会爆炸。
//   2. 读输出必须寄存（`rdata <= mem[raddr]`）。组合读会被实现成分布式 RAM/LUT。
//   3. 存储体声明成 `reg [DW-1:0] mem [0:DEPTH-1];`，不要在别处再赋值。
//
// 读写同地址时的行为是“先读后写”(read-first)：本模块 rdata 拿到的是**旧值**，
// 因为非阻塞赋值在同一时刻统一更新。若需要 write-first（读到新值），
// 要显式加旁路逻辑。不同厂商默认行为不同，跨平台移植时务必确认。
//
// [FPGA] Xilinx 可加 (* ram_style = "block" *) 或 "distributed" 强制指定；
//        Intel 用 ramstyle 属性。留空则由综合器按容量自行决定。
// [ASIC] 一般不用推断，而是直接实例化 memory compiler 生成的 SRAM 宏；
//        本模块此时仅用作仿真替身（behavioral model）。
// -----------------------------------------------------------------------------
`default_nettype none

module sdp_ram #(
    parameter integer DW = 32,        // 数据位宽
    parameter integer AW = 10         // 地址位宽，深度 = 2**AW
) (
    input  wire           clk,
    // 写口
    input  wire           we,
    input  wire [AW-1:0]  waddr,
    input  wire [DW-1:0]  wdata,
    // 读口
    input  wire           re,
    input  wire [AW-1:0]  raddr,
    output reg  [DW-1:0]  rdata
);

    reg [DW-1:0] mem [0:(2**AW)-1];

    always @(posedge clk) begin
        if (we) mem[waddr] <= wdata;
        if (re) rdata      <= mem[raddr];
    end

endmodule

`default_nettype wire
