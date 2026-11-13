`default_nettype none

module bch_paper_enc_w512 (
    input wire clk,input wire reset_n,input wire start_i,output wire start_ready_o,
    input wire [511:0] in_bits_i,input wire [$clog2(512+1)-1:0] in_count_i,
    input wire in_valid_i,output wire in_ready_o,
    output wire [511:0] out_bits_o,output wire [$clog2(512+1)-1:0] out_count_o,
    output wire out_valid_o,input wire out_ready_i,output wire out_last_o,
    output wire done_o,output wire busy_o
);
    bch_enc #(.K(4096),.R(351),.W(512),
        .GENERATOR(352'hb4e157247094cbaae72500117981ca4f6d8438e62186330511cb8e8cf32f8eedc89a5cbf72c7002ba84111f7)) core (.*);
endmodule
`default_nettype wire
