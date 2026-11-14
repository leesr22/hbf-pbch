`default_nettype none

// One-address score bank for the XOR-banked exact FWHT engine.
//
// The fixed banking function guarantees that both operands of every
// butterfly live in different banks.  Each bank therefore needs only one
// asynchronous read and one synchronous write to the same addressed row.
module fht_score_bank_1rw #(
    parameter integer DEPTH = 64,
    parameter integer SCORE_W = 14,
    parameter integer ADDR_W = $clog2(DEPTH)
) (
    input  wire                         clk,
    input  wire [ADDR_W-1:0]            addr_i,
    output wire signed [SCORE_W-1:0]    data_o,
    input  wire                         write_i,
    input  wire signed [SCORE_W-1:0]    write_data_i
);
    reg signed [SCORE_W-1:0] score_q [0:DEPTH-1];

    assign data_o = score_q[addr_i];

    always @(posedge clk)
        if (write_i)
            score_q[addr_i] <= write_data_i;
endmodule

`default_nettype wire
