`default_nettype none

module bch_equal_r_enc_w512 (
    input wire clk,input wire reset_n,input wire start_i,output wire start_ready_o,
    input wire [511:0] in_bits_i,input wire [$clog2(512+1)-1:0] in_count_i,
    input wire in_valid_i,output wire in_ready_o,
    output wire [511:0] out_bits_o,output wire [$clog2(512+1)-1:0] out_count_o,
    output wire out_valid_o,input wire out_ready_i,output wire out_last_o,
    output wire done_o,output wire busy_o
);
    bch_enc #(.K(4096),.R(117),.W(512),
        .GENERATOR(118'h2d8aa10efe51eb9ccab1b3e6b626e1)) core (.*);
endmodule
`default_nettype wire
