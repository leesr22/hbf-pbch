`default_nettype none

// BCH decoder variant that stores sensed codewords locally for correction.
// Arithmetic is identical to bch_dec; only the replay source is different.
module bch_dec_buffered #(
    parameter integer M = 13,
    parameter integer T = 8,
    parameter integer K = 4096,
    parameter integer N = 4200,
    parameter integer W = 64,
    parameter integer BM_LANES = 1,
    parameter integer BUFFER_DEPTH = 4,
    parameter integer PARTIAL_A = 0,
    parameter integer PARTIAL_B = 0,
    parameter [M:0] PRIMITIVE_POLYNOMIAL = 14'h201b,
    parameter [(T*M)-1:0] SYN_FULL_STATE = '0,
    parameter [(T*W*M)-1:0] SYN_FULL_INPUT = '0,
    parameter [(T*M)-1:0] SYN_PARTIAL_A_STATE = '0,
    parameter [(T*W*M)-1:0] SYN_PARTIAL_A_INPUT = '0,
    parameter [(T*M)-1:0] SYN_PARTIAL_B_STATE = '0,
    parameter [(T*W*M)-1:0] SYN_PARTIAL_B_INPUT = '0,
    parameter [((T+1)*M)-1:0] CHIEN_INIT = '0,
    parameter [((T+1)*W*M)-1:0] CHIEN_LANE = '0,
    parameter [((T+1)*M)-1:0] CHIEN_ADVANCE_FULL = '0,
    parameter [((T+1)*M)-1:0] CHIEN_ADVANCE_PARTIAL_A = '0,
    parameter [((T+1)*M)-1:0] CHIEN_ADVANCE_PARTIAL_B = '0,
    parameter integer COUNT_W = $clog2(W + 1),
    parameter integer DEG_W = $clog2(T + 1)
) (
    input  wire                 clk,
    input  wire                 reset_n,
    input  wire                 start_i,
    output wire                 start_ready_o,
    input  wire [W-1:0]         code_bits_i,
    input  wire [COUNT_W-1:0]   code_count_i,
    input  wire                 code_valid_i,
    output wire                 code_ready_o,
    output wire [W-1:0]         info_bits_o,
    output wire [COUNT_W-1:0]   info_count_o,
    output wire                 info_valid_o,
    input  wire                 info_ready_i,
    output wire                 done_o,
    output wire                 success_o,
    output wire [DEG_W-1:0]     error_count_o,
    output wire                 busy_o
);
    wire core_start;
    wire core_start_ready;
    wire [W-1:0] core_code_bits;
    wire [COUNT_W-1:0] core_code_count;
    wire core_code_valid;
    wire core_code_ready;
    wire replay_req;
    wire [W-1:0] replay_bits;
    wire [COUNT_W-1:0] replay_count;
    wire replay_valid;
    wire replay_ready;
    wire buffer_busy;
    wire decoder_busy;

    assign busy_o = buffer_busy || decoder_busy;

    codeword_replay_buffer #(
        .N(N), .W(W), .DEPTH(BUFFER_DEPTH)
    ) buffer_u (
        .clk(clk), .reset_n(reset_n), .start_i(start_i),
        .start_ready_o(start_ready_o), .code_bits_i(code_bits_i),
        .code_count_i(code_count_i), .code_valid_i(code_valid_i),
        .code_ready_o(code_ready_o), .core_start_o(core_start),
        .core_start_ready_i(core_start_ready), .core_code_bits_o(core_code_bits),
        .core_code_count_o(core_code_count), .core_code_valid_o(core_code_valid),
        .core_code_ready_i(core_code_ready), .core_replay_req_i(replay_req),
        .core_replay_bits_o(replay_bits), .core_replay_count_o(replay_count),
        .core_replay_valid_o(replay_valid), .core_replay_ready_i(replay_ready),
        .busy_o(buffer_busy)
    );

    bch_dec #(
        .M(M), .T(T), .K(K), .N(N), .W(W), .BM_LANES(BM_LANES),
        .PARTIAL_A(PARTIAL_A), .PARTIAL_B(PARTIAL_B),
        .PRIMITIVE_POLYNOMIAL(PRIMITIVE_POLYNOMIAL),
        .SYN_FULL_STATE(SYN_FULL_STATE), .SYN_FULL_INPUT(SYN_FULL_INPUT),
        .SYN_PARTIAL_A_STATE(SYN_PARTIAL_A_STATE),
        .SYN_PARTIAL_A_INPUT(SYN_PARTIAL_A_INPUT),
        .SYN_PARTIAL_B_STATE(SYN_PARTIAL_B_STATE),
        .SYN_PARTIAL_B_INPUT(SYN_PARTIAL_B_INPUT),
        .CHIEN_INIT(CHIEN_INIT), .CHIEN_LANE(CHIEN_LANE),
        .CHIEN_ADVANCE_FULL(CHIEN_ADVANCE_FULL),
        .CHIEN_ADVANCE_PARTIAL_A(CHIEN_ADVANCE_PARTIAL_A),
        .CHIEN_ADVANCE_PARTIAL_B(CHIEN_ADVANCE_PARTIAL_B)
    ) decoder_u (
        .clk(clk), .reset_n(reset_n), .start_i(core_start),
        .start_ready_o(core_start_ready), .code_bits_i(core_code_bits),
        .code_count_i(core_code_count), .code_valid_i(core_code_valid),
        .code_ready_o(core_code_ready), .replay_req_o(replay_req),
        .replay_bits_i(replay_bits), .replay_count_i(replay_count),
        .replay_valid_i(replay_valid), .replay_ready_o(replay_ready),
        .info_bits_o(info_bits_o), .info_count_o(info_count_o),
        .info_valid_o(info_valid_o), .info_ready_i(info_ready_i),
        .done_o(done_o), .success_o(success_o),
        .error_count_o(error_count_o), .busy_o(decoder_busy)
    );
endmodule

`default_nettype wire
