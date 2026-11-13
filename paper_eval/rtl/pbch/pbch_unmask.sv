`default_nettype none

// Removes the selected fixed masks from corrected PBCH user data.
// MASK_COLUMNS is a compile-time constant, so no matrix flip-flops are built.
module pbch_unmask #(
    parameter integer K = 4096,
    parameter integer L = 13,
    parameter integer W = 64,
    parameter [(K*L)-1:0] MASK_COLUMNS = '0,
    parameter integer COUNT_W = $clog2(W + 1),
    parameter integer BEATS = K / W,
    parameter integer BEAT_W = (BEATS <= 1) ? 1 : $clog2(BEATS)
) (
    input  wire                 clk,
    input  wire                 reset_n,
    input  wire                 start_i,
    input  wire [L-1:0]         selector_i,
    input  wire [W-1:0]         in_bits_i,
    input  wire [COUNT_W-1:0]   in_count_i,
    input  wire                 in_valid_i,
    output wire                 in_ready_o,
    output reg  [W-1:0]         out_bits_o,
    output wire [COUNT_W-1:0]   out_count_o,
    output wire                 out_valid_o,
    input  wire                 out_ready_i
);
    reg [BEAT_W-1:0] beat_q;
    reg [L-1:0] column;
    reg mask_bit;
    reg [(W*L)-1:0] column_chunk;
    integer lane;
    integer bit_index;

    assign in_ready_o = out_ready_i;
    assign out_valid_o = in_valid_i;
    assign out_count_o = in_count_i;

    always @* begin
        out_bits_o = in_bits_i;
        // Message bits always arrive as aligned W-bit beats.  Select one
        // constant W-column chunk, rather than W independent 4096:1 bit muxes.
        column_chunk = MASK_COLUMNS[beat_q*W*L +: W*L];
        for (lane = 0; lane < W; lane = lane + 1) begin
            if (lane < in_count_i) begin
                column = column_chunk[lane*L +: L];
                mask_bit = 1'b0;
                for (bit_index = 0; bit_index < L; bit_index = bit_index + 1)
                    mask_bit = mask_bit ^
                               (selector_i[bit_index] & column[bit_index]);
                out_bits_o[W-1-lane] = in_bits_i[W-1-lane] ^ mask_bit;
            end
        end
    end

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            beat_q <= '0;
        else if (start_i)
            beat_q <= '0;
        else if (in_valid_i && in_ready_o)
            beat_q <= beat_q + 1'b1;
    end

`ifndef SYNTHESIS
    initial begin
        if (K % W != 0)
            $error("PBCH message length must be an integer number of W-bit beats");
    end
`endif
endmodule

`default_nettype wire
