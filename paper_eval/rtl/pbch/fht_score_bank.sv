`default_nettype none

// One explicitly separated score bank for the exact Walsh-Hadamard search.
// Keeping each 128-entry bank in its own module prevents synthesis from
// constructing a multiported 8192-entry register file.
module fht_score_bank #(
    parameter integer DEPTH = 128,
    parameter integer SCORE_W = 14,
    parameter integer ADDR_W = $clog2(DEPTH)
) (
    input  wire                         clk,
    input  wire [ADDR_W-1:0]            read_a_i,
    input  wire [ADDR_W-1:0]            read_b_i,
    output wire signed [SCORE_W-1:0]    data_a_o,
    output wire signed [SCORE_W-1:0]    data_b_o,
    input  wire                         write_a_i,
    input  wire                         write_b_i,
    input  wire signed [SCORE_W-1:0]    write_data_a_i,
    input  wire signed [SCORE_W-1:0]    write_data_b_i
);
    reg signed [SCORE_W-1:0] score_q [0:DEPTH-1];

    assign data_a_o = score_q[read_a_i];
    assign data_b_o = score_q[read_b_i];

    always @(posedge clk) begin
        if (write_a_i)
            score_q[read_a_i] <= write_data_a_i;
        if (write_b_i)
            score_q[read_b_i] <= write_data_b_i;
    end
endmodule

`default_nettype wire
