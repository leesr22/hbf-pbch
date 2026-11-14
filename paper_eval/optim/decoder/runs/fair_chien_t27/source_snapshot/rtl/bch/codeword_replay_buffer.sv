`default_nettype none

// Optional decoder-local codeword storage.
//
// The first pass is sent directly to the syndrome block while the same bits are
// captured here.  When the decoder requests replay, this FIFO supplies the
// saved word.  DEPTH controls how many pipelined codewords can remain in flight.
module codeword_replay_buffer #(
    parameter integer N = 4200,
    parameter integer W = 64,
    parameter integer DEPTH = 4,
    parameter integer FIRST_COUNT = 0,
    parameter integer COUNT_W = $clog2(W + 1),
    parameter integer POS_W = $clog2(N + 1),
    parameter integer BEATS = (FIRST_COUNT == 0) ? ((N + W - 1) / W) :
                              (1 + (N - FIRST_COUNT + W - 1) / W),
    parameter integer BEAT_W = (BEATS <= 1) ? 1 : $clog2(BEATS),
    parameter integer PTR_W = (DEPTH <= 1) ? 1 : $clog2(DEPTH),
    parameter integer USED_W = $clog2(DEPTH + 1)
) (
    input  wire                 clk,
    input  wire                 reset_n,

    input  wire                 start_i,
    output wire                 start_ready_o,
    input  wire [W-1:0]         code_bits_i,
    input  wire [COUNT_W-1:0]   code_count_i,
    input  wire                 code_valid_i,
    output wire                 code_ready_o,

    output wire                 core_start_o,
    input  wire                 core_start_ready_i,
    output wire [W-1:0]         core_code_bits_o,
    output wire [COUNT_W-1:0]   core_code_count_o,
    output wire                 core_code_valid_o,
    input  wire                 core_code_ready_i,

    input  wire                 core_replay_req_i,
    output reg  [W-1:0]         core_replay_bits_o,
    output reg  [COUNT_W-1:0]   core_replay_count_o,
    output wire                 core_replay_valid_o,
    input  wire                 core_replay_ready_i,

    output wire                 busy_o
);
    // Store the stream exactly as W-bit beats.  A flat N-bit vector with
    // variable bit-selects synthesizes into a very large bit-level mux/write
    // decoder; beat addressing describes the intended small banked buffer.
    reg [W-1:0] word_q [0:DEPTH-1][0:BEATS-1];
    reg [PTR_W-1:0] write_q;
    reg [PTR_W-1:0] read_q;
    reg [USED_W-1:0] used_q;
    reg capture_q;
    reg replay_q;
    reg [POS_W-1:0] capture_pos_q;
    reg [POS_W-1:0] replay_pos_q;
    reg [BEAT_W-1:0] capture_beat_q;
    reg [BEAT_W-1:0] replay_beat_q;

    integer valid_now;
    wire start_fire = start_i && start_ready_o;
    wire capture_fire = code_valid_i && code_ready_o;
    wire capture_last = capture_fire && capture_pos_q + code_count_i == N;
    wire replay_fire = core_replay_valid_o && core_replay_ready_i;
    wire replay_last = replay_fire && replay_pos_q + core_replay_count_o == N;

    function automatic [PTR_W-1:0] next_pointer(input [PTR_W-1:0] pointer);
        begin
            next_pointer = (pointer == DEPTH-1) ? '0 : pointer + 1'b1;
        end
    endfunction

    assign start_ready_o = !capture_q && used_q < DEPTH && core_start_ready_i;
    assign core_start_o = start_fire;
    assign core_code_bits_o = code_bits_i;
    assign core_code_count_o = code_count_i;
    assign core_code_valid_o = code_valid_i && capture_q;
    assign code_ready_o = capture_q && core_code_ready_i;
    assign core_replay_valid_o = replay_q;
    assign busy_o = capture_q || replay_q || used_q != 0;

    always @* begin
        core_replay_bits_o = word_q[read_q][replay_beat_q];
        if (replay_pos_q == 0 && FIRST_COUNT != 0)
            valid_now = FIRST_COUNT;
        else
            valid_now = ((N - replay_pos_q) > W) ? W : (N - replay_pos_q);
        core_replay_count_o = valid_now[COUNT_W-1:0];
    end

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            write_q <= '0;
            read_q <= '0;
            used_q <= '0;
            capture_q <= 1'b0;
            replay_q <= 1'b0;
            capture_pos_q <= '0;
            replay_pos_q <= '0;
            capture_beat_q <= '0;
            replay_beat_q <= '0;
        end else begin
            if (start_fire) begin
                capture_q <= 1'b1;
                capture_pos_q <= '0;
                capture_beat_q <= '0;
            end

            if (capture_fire) begin
                word_q[write_q][capture_beat_q] <= code_bits_i;
                capture_pos_q <= capture_pos_q + code_count_i;
                capture_beat_q <= capture_beat_q + 1'b1;
                if (capture_last) begin
                    capture_q <= 1'b0;
                    write_q <= next_pointer(write_q);
                end
            end

            if (core_replay_req_i) begin
                replay_q <= 1'b1;
                replay_pos_q <= '0;
                replay_beat_q <= '0;
            end else if (replay_fire) begin
                replay_pos_q <= replay_pos_q + core_replay_count_o;
                replay_beat_q <= replay_beat_q + 1'b1;
                if (replay_last) begin
                    replay_q <= 1'b0;
                    read_q <= next_pointer(read_q);
                end
            end

            case ({capture_last,replay_last})
                2'b10: used_q <= used_q + 1'b1;
                2'b01: used_q <= used_q - 1'b1;
                default: used_q <= used_q;
            endcase
        end
    end

`ifndef SYNTHESIS
    always @(posedge clk) begin
        if (reset_n && core_replay_req_i && used_q == 0)
            $error("decoder requested an empty replay FIFO");
        if (reset_n && core_replay_req_i && replay_q)
            $error("overlapping replay requests require a deeper replay port");
    end
`endif
endmodule

`default_nettype wire
