`default_nettype none

// PBCH2 encoder with selectable exhaustive selector-search architecture.
//
// The module keeps one message; the pre-read bitmap remains in the upstream
// page/cache buffer and is requested one beat at a time.  The encoder builds
// the all-zero-selector BCH word, scans flagged positions, runs either the
// full FHT or sparse exhaustive engine, and emits c(0) XOR G0*d.  G0 is a
// compile-time constant, not a flip-flop RAM.
module pbch_fht_enc #(
    parameter integer K = 4096,
    parameter integer L = 13,
    parameter integer R = 169,
    parameter integer N = K + L + R,
    parameter integer W = 64,
    parameter integer FHT_PARALLEL = 8,
    parameter integer FHT_ARCH = 0,
    parameter integer SPARSE_MAX_FLAGS = 32,
    parameter integer LOCAL_MESSAGE = 1,
    parameter integer DATA_BEATS = K / W,
    parameter integer PARITY_BEATS = (R + W - 1) / W,
    parameter integer EMIT_BEATS = 1 + DATA_BEATS + PARITY_BEATS,
    parameter [R:0] BCH_GENERATOR = '0,
    parameter [(N*L)-1:0] G0_COLUMNS = '0,
    parameter [(EMIT_BEATS*W*L)-1:0] G0_BEAT_COLUMNS = '0,
    parameter integer COUNT_W = $clog2(W + 1),
    parameter integer DATA_W = $clog2(K + 1),
    parameter integer CODE_W = $clog2(N + 1),
    parameter integer SCORE_W = $clog2(N + 1) + 1,
    parameter integer DATA_BEAT_W = $clog2(DATA_BEATS + 1),
    parameter integer EMIT_BEAT_W = $clog2(EMIT_BEATS),
    parameter integer LANE_W = $clog2(W)
) (
    input  wire                         clk,
    input  wire                         reset_n,
    input  wire                         start_i,
    output wire                         start_ready_o,

    input  wire [W-1:0]                 data_bits_i,
    input  wire [COUNT_W-1:0]           data_count_i,
    input  wire                         data_valid_i,
    output wire                         data_ready_o,

    input  wire [W-1:0]                 probe_bits_i,
    input  wire [COUNT_W-1:0]           probe_count_i,
    input  wire                         probe_valid_i,
    output wire                         probe_ready_o,

    output reg  [DATA_BEAT_W-1:0]       message_addr_o,
    input  wire [W-1:0]                 external_message_bits_i,

    output reg  [W-1:0]                 out_bits_o,
    output reg  [COUNT_W-1:0]           out_count_o,
    output wire                         out_valid_o,
    input  wire                         out_ready_i,
    output reg                          out_last_o,

    output reg  [L-1:0]                 selector_o,
    output reg  [CODE_W-1:0]            mask_failures_o,
    output wire                         flag_overflow_o,
    output reg                          done_o,
    output wire                         busy_o
);
    localparam [2:0] IDLE = 3'd0, CAPTURE = 3'd1, SCAN = 3'd2,
                     WAIT_FHT = 3'd3, EMIT = 3'd4;

    reg [2:0] state_q;
    reg [W-1:0] message_q [0:DATA_BEATS-1];
    reg [R-1:0] remainder_q;
    reg [DATA_W-1:0] data_seen_q;
    reg [DATA_BEAT_W-1:0] data_beat_q;
    reg data_done_q;
    reg [EMIT_BEAT_W-1:0] emit_beat_q;

    reg [R-1:0] remainder_next;
    reg feedback;
    integer lane;
    integer valid_now;
    integer selector_bit;
    integer parity_beat;
    reg base_bit;
    reg mask_bit;
    reg [L-1:0] column;
    reg [W-1:0] base_chunk;
    reg [(W*L)-1:0] column_chunk;

    wire fht_start = start_i && start_ready_o;
    wire fht_add_ready;
    wire fht_done;
    wire [L-1:0] fht_selector;
    wire signed [SCORE_W-1:0] fht_best_score;
    wire search_overflow;
    wire [CODE_W-1:0] scan_position;
    wire [CODE_W-1:0] scan_total;
    wire scan_flag_valid;
    wire scan_finish;
    wire scan_start = (state_q == CAPTURE) && data_done_q && fht_add_ready;
    wire [L-1:0] scan_column = G0_COLUMNS[scan_position*L +: L];
    wire [CODE_W-1:0] scan_message_offset = scan_position - L;
    wire scan_base_bit = (scan_position < L) ? 1'b0 :
                         (scan_position < L+K) ?
                         (LOCAL_MESSAGE ?
                          message_q[scan_message_offset >> LANE_W]
                                   [W-1-scan_message_offset[LANE_W-1:0]] :
                          external_message_bits_i
                                   [W-1-scan_message_offset[LANE_W-1:0]]) :
                         remainder_q[R-1-(scan_position-L-K)];
    wire signed [SCORE_W:0] failure_delta =
        $signed({2'b00,scan_total}) - $signed(fht_best_score);

    assign start_ready_o = state_q == IDLE;
    assign data_ready_o = (state_q == CAPTURE) && !data_done_q;
    assign out_valid_o = state_q == EMIT;
    assign busy_o = state_q != IDLE;

    // Address-only read port to the existing upstream write-data buffer.
    // Local-buffer builds constant-fold this logic and ignore the input.
    always @* begin
        message_addr_o = '0;
        if (!LOCAL_MESSAGE) begin
            if (state_q == SCAN && scan_position >= L &&
                scan_position < L+K)
                message_addr_o = scan_message_offset >> LANE_W;
            else if (state_q == EMIT && emit_beat_q > 0 &&
                     emit_beat_q <= DATA_BEATS)
                message_addr_o = emit_beat_q - 1'b1;
        end
    end

    // The all-zero selector precedes the message.  Leading zeros do not change
    // the BCH remainder, so capture can update the remainder from data directly.
    always @* begin
        remainder_next = remainder_q;
        for (lane = 0; lane < W; lane = lane + 1) begin
            feedback = data_bits_i[W-1-lane] ^ remainder_next[R-1];
            remainder_next = {remainder_next[R-2:0],1'b0};
            if (feedback)
                remainder_next = remainder_next ^ BCH_GENERATOR[R-1:0];
        end
    end

    // Final selected codeword, W positions at a time.
    always @* begin
        out_bits_o = '0;
        out_count_o = '0;
        out_last_o = 1'b0;
        base_chunk = '0;
        column_chunk = G0_BEAT_COLUMNS[emit_beat_q*W*L +: W*L];
        valid_now = 0;
        parity_beat = 0;
        if (state_q == EMIT) begin
            if (emit_beat_q == 0) begin
                valid_now = L;
            end else if (emit_beat_q <= DATA_BEATS) begin
                valid_now = W;
                base_chunk = LOCAL_MESSAGE ?
                             message_q[emit_beat_q-1] :
                             external_message_bits_i;
            end else begin
                parity_beat = emit_beat_q - 1 - DATA_BEATS;
                valid_now = ((R - parity_beat*W) > W) ?
                            W : (R - parity_beat*W);
                for (lane = 0; lane < W; lane = lane + 1)
                    if (lane < valid_now)
                        base_chunk[W-1-lane] =
                            remainder_q[R-1-parity_beat*W-lane];
            end
            out_count_o = valid_now[COUNT_W-1:0];
            out_last_o = emit_beat_q == EMIT_BEATS-1;
            for (lane = 0; lane < W; lane = lane + 1) begin
                if (lane < valid_now) begin
                    base_bit = base_chunk[W-1-lane];
                    column = column_chunk[lane*L +: L];
                    mask_bit = 1'b0;
                    for (selector_bit = 0; selector_bit < L;
                         selector_bit = selector_bit + 1)
                        mask_bit = mask_bit ^
                                   (selector_o[selector_bit] & column[selector_bit]);
                    out_bits_o[W-1-lane] = base_bit ^ mask_bit;
                end
            end
        end
    end

    generate
        if (FHT_ARCH == 0) begin : fixed_bank_search
            fht_search #(
                .L(L), .N(N), .PARALLEL(FHT_PARALLEL)
            ) search_u (
                .clk(clk), .reset_n(reset_n), .start_i(fht_start),
                .start_ready_o(), .label_i(scan_column),
                .base_is_zero_i(!scan_base_bit),
                .add_valid_i(scan_flag_valid),
                .add_ready_o(fht_add_ready), .finish_i(scan_finish),
                .selector_o(fht_selector), .best_score_o(fht_best_score),
                .done_o(fht_done), .busy_o()
            );
            assign search_overflow = 1'b0;
        end else if (FHT_ARCH == 1) begin : xor_banked_search
            fht_search_xor_banked #(
                .L(L), .N(N), .BUTTERFLIES(FHT_PARALLEL)
            ) search_u (
                .clk(clk), .reset_n(reset_n), .start_i(fht_start),
                .start_ready_o(), .label_i(scan_column),
                .base_is_zero_i(!scan_base_bit),
                .add_valid_i(scan_flag_valid),
                .add_ready_o(fht_add_ready), .finish_i(scan_finish),
                .selector_o(fht_selector), .best_score_o(fht_best_score),
                .done_o(fht_done), .busy_o()
            );
            assign search_overflow = 1'b0;
        end else begin : sparse_gray_search
            selector_search_sparse_gray #(
                .L(L), .N(N), .MAX_FLAGS(SPARSE_MAX_FLAGS),
                .LANES(FHT_PARALLEL)
            ) search_u (
                .clk(clk), .reset_n(reset_n), .start_i(fht_start),
                .start_ready_o(), .label_i(scan_column),
                .base_is_zero_i(!scan_base_bit),
                .add_valid_i(scan_flag_valid),
                .add_ready_o(fht_add_ready), .finish_i(scan_finish),
                .selector_o(fht_selector), .best_score_o(fht_best_score),
                .overflow_o(search_overflow),
                .done_o(fht_done), .busy_o()
            );
        end
    endgenerate

    assign flag_overflow_o = search_overflow;

    probe_scan #(
        .N(N), .W(W)
    ) scan_u (
        .clk(clk), .reset_n(reset_n), .start_i(scan_start),
        .bits_i(probe_bits_i), .count_i(probe_count_i),
        .valid_i(probe_valid_i), .ready_o(probe_ready_o),
        .position_o(scan_position), .flag_valid_o(scan_flag_valid),
        .finish_o(scan_finish), .total_o(scan_total), .busy_o()
    );

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state_q <= IDLE;
            remainder_q <= '0;
            data_seen_q <= '0;
            data_beat_q <= '0;
            data_done_q <= 1'b0;
            emit_beat_q <= '0;
            selector_o <= '0;
            mask_failures_o <= '0;
            done_o <= 1'b0;
        end else begin
            done_o <= 1'b0;
            case (state_q)
                IDLE: if (start_i) begin
                    remainder_q <= '0;
                    data_seen_q <= '0;
                    data_beat_q <= '0;
                    data_done_q <= 1'b0;
                    selector_o <= '0;
                    mask_failures_o <= '0;
                    state_q <= CAPTURE;
                end

                CAPTURE: begin
                    if (data_valid_i && data_ready_o) begin
                        if (LOCAL_MESSAGE)
                            message_q[data_beat_q] <= data_bits_i;
                        remainder_q <= remainder_next;
                        data_seen_q <= data_seen_q + data_count_i;
                        data_beat_q <= data_beat_q + 1'b1;
                        if (data_seen_q + data_count_i == K)
                            data_done_q <= 1'b1;
                    end
                    if (data_done_q && fht_add_ready)
                        state_q <= SCAN;
                end

                SCAN: if (scan_finish)
                    state_q <= WAIT_FHT;

                WAIT_FHT: if (fht_done) begin
                    selector_o <= fht_selector;
                    // delta is always a non-negative even value:
                    // flags - (masked-unmasked) = 2*unmasked.
                    mask_failures_o <= search_overflow ?
                                       {CODE_W{1'b1}} :
                                       failure_delta[CODE_W:1];
                    emit_beat_q <= '0;
                    state_q <= EMIT;
                end

                EMIT: if (out_ready_i) begin
                    if (emit_beat_q == EMIT_BEATS-1) begin
                        done_o <= 1'b1;
                        state_q <= IDLE;
                    end else begin
                        emit_beat_q <= emit_beat_q + 1'b1;
                    end
                end

                default: state_q <= IDLE;
            endcase
        end
    end

`ifndef SYNTHESIS
    always @(posedge clk) begin
        if (reset_n && data_valid_i && data_ready_o && data_count_i != W)
            $error("PBCH data beats must contain W bits");
        if (reset_n && state_q == SCAN && !fht_add_ready)
            $error("FHT input unexpectedly not ready during scan");
    end
`endif
endmodule

`default_nettype wire
