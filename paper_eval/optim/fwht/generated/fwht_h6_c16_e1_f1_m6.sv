module fwht_h6_c16_e1_f1_m6 (
input wire clk,reset_n,start_i,
output wire start_ready_o,
input wire [12:0] label_i,
input wire base_is_zero_i,add_valid_i,
output wire add_ready_o,
input wire finish_i,
output wire [12:0] selector_o,
output wire signed [13:0] best_score_o,
output wire overflow_o,done_o,busy_o
);
selector_search_fwht_compact #(.HIGH_L(6),.CHUNK(16),.EARLY_EXIT(1),.FUSE_INPUT(1),.MODULAR6(1)) core(.*);
endmodule
