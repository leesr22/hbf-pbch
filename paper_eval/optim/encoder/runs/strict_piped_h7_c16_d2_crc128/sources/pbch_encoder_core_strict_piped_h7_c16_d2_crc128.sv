`default_nettype none

// Exact frozen PBCH(t=8,l=13) encoder with codeword-stage overlap.
// The unchanged seed62 mask matrix is represented by an exact recurrence.
// Blocked FWHT preserves every candidate score and the smallest-selector tie
// break. EARLY_EXIT, when enabled, stops only at the proven maximum score;
// otherwise the complete 8192-selector space is traversed.
// The upstream multi-context buffer supplies one shared message-read port.
// This generated core is intended only for its fixed-profile wrapper.
module pbch_encoder_core_strict_piped_h7_c16_d2_crc128 #(
    parameter integer K = 4096,
    parameter integer L = 13,
    parameter integer R = 169,
    parameter integer N = K + L + R,
    parameter integer W = 128,
    parameter integer LANES = 64,
    parameter integer MAX_FLAGS = 32,
    // 0: sparse Gray recurrence.
    // 1: sparse-input blocked butterfly FWHT, one register per stage.
    // 2: exact blocked FWHT with multiple butterfly stages per register bank.
    parameter integer SEARCH_IMPL = 0,
    parameter integer FWHT_HIGH_L = 7,
    parameter integer FWHT_PIPE_GROUP = 2,
    parameter integer CONTEXT_W = 3,
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
    parameter integer LANE_W = $clog2(W),
    parameter integer FLAG_COUNT_W = $clog2(MAX_FLAGS + 1)
) (
    input  wire                         clk,
    input  wire                         reset_n,
    input  wire                         start_i,
    input  wire [CONTEXT_W-1:0]         context_i,
    output wire                         start_ready_o,

    input  wire [W-1:0]                 data_bits_i,
    input  wire [COUNT_W-1:0]           data_count_i,
    input  wire                         data_valid_i,
    output wire                         data_ready_o,

    input  wire [W-1:0]                 probe_bits_i,
    input  wire [COUNT_W-1:0]           probe_count_i,
    input  wire                         probe_valid_i,
    output wire                         probe_ready_o,

    output reg  [CONTEXT_W-1:0]         message_context_o,
    output reg  [DATA_BEAT_W-1:0]       message_addr_o,
    input  wire [W-1:0]                 external_message_bits_i,

    output reg  [W-1:0]                 out_bits_o,
    output reg  [COUNT_W-1:0]           out_count_o,
    output wire                         out_valid_o,
    input  wire                         out_ready_i,
    output reg                          out_last_o,
    output wire [CONTEXT_W-1:0]         result_context_o,
    output wire [L-1:0]                 selector_o,
    output wire [CODE_W-1:0]            mask_failures_o,
    output wire                         flag_overflow_o,
    output reg                          done_o,
    output wire                         busy_o
);
    // synthesis translate_off
    initial begin
        if (K != 4096 || L != 13 || R != 104 || N != 4213 || W != 512 || MAX_FLAGS != 32)
            $fatal(1, "This generated encoder supports only k4096/t8/l13/W512/max32");
    end
    // synthesis translate_on
    localparam [1:0] FRONT_IDLE = 2'd0, FRONT_CAPTURE = 2'd1,
                     FRONT_WAIT_SCAN = 2'd2, FRONT_SCAN = 2'd3;
    localparam        LOAD_IDLE = 1'b0, LOAD_FLAGS = 1'b1;

    reg [1:0] crc_phase_q;
    reg [1:0] front_state_q;
    reg load_state_q;

    reg [CONTEXT_W-1:0] front_context_q;
    reg [R-1:0] front_remainder_q;
    reg [DATA_W-1:0] data_seen_q;

    reg pending_valid_q;
    reg [L-1:0] pending_label_q [0:MAX_FLAGS-1];
    reg pending_base_zero_q [0:MAX_FLAGS-1];
    reg [FLAG_COUNT_W-1:0] pending_count_q;
    reg [CODE_W-1:0] pending_total_q;
    reg pending_overflow_q;
    reg [R-1:0] pending_remainder_q;
    reg [CONTEXT_W-1:0] pending_context_q;

    reg [FLAG_COUNT_W:0] load_index_q;
    reg [R-1:0] search_remainder_q;
    reg [CODE_W-1:0] search_total_q;
    reg [CONTEXT_W-1:0] search_context_q;

    reg result_valid_q;
    reg output_active_q;
    reg [R-1:0] result_remainder_q;
    reg [CONTEXT_W-1:0] result_context_q;
    reg [L-1:0] result_selector_q;
    reg [CODE_W-1:0] result_failures_q;
    reg result_overflow_q;
    reg [EMIT_BEAT_W-1:0] emit_beat_q;

    reg [R-1:0] remainder_next;
    reg feedback;
    reg [W-1:0] base_chunk;
    reg [(W*L)-1:0] column_chunk;
    reg [L-1:0] column;
    reg base_bit;
    reg mask_bit;
    integer lane;
    integer selector_bit;
    integer valid_now;
    integer parity_beat;

    wire scan_start = (front_state_q == FRONT_WAIT_SCAN) &&
                      !result_valid_q && !output_active_q;
    wire [CODE_W-1:0] scan_position;
    wire [CODE_W-1:0] scan_total;
    wire scan_flag_valid;
    wire scan_finish;
    reg [CODE_W-1:0] label_position_q;
    reg label_valid_q, label_base_q, label_finish_q;
    wire [L-1:0] scan_column;
    pbch_scan_label_b32 label_u (.position_i(label_position_q), .label_o(scan_column));
    wire [CODE_W-1:0] scan_message_offset = scan_position - L;
    wire scan_base_bit = (scan_position < L) ? 1'b0 :
                         (scan_position < L+K) ?
                         external_message_bits_i
                           [W-1-scan_message_offset[LANE_W-1:0]] :
                         front_remainder_q[R-1-(scan_position-L-K)];

    reg search_result_pending_q;
    wire search_done;
    wire search_start_ready;
    wire search_start = (load_state_q == LOAD_IDLE) && pending_valid_q &&
                        search_start_ready && !search_done && !search_result_pending_q;
    wire [FLAG_COUNT_W:0] load_count =
        {1'b0,pending_count_q} + pending_overflow_q;
    wire search_add_valid = (load_state_q == LOAD_FLAGS) &&
                            (load_index_q < load_count);
    wire search_add_is_real = load_index_q < pending_count_q;
    wire [L-1:0] search_add_label = search_add_is_real ?
                                    pending_label_q[load_index_q] : '0;
    wire search_add_base_zero = search_add_is_real ?
                                pending_base_zero_q[load_index_q] : 1'b0;
    wire search_finish = (load_state_q == LOAD_FLAGS) &&
                         ((load_count == 0) ||
                          (search_add_valid && load_index_q + 1'b1 == load_count));
    wire search_busy;
    wire [L-1:0] search_selector;
    wire signed [SCORE_W-1:0] search_best_score;
    wire search_overflow;
    wire signed [SCORE_W:0] failure_delta =
        $signed({2'b00,search_total_q}) - $signed(search_best_score);

    assign start_ready_o = (front_state_q == FRONT_IDLE) && !pending_valid_q;
    assign data_ready_o = front_state_q == FRONT_CAPTURE && crc_phase_q == 3;
    assign out_valid_o = output_active_q;
    assign result_context_o = result_context_q;
    assign selector_o = result_selector_q;
    assign mask_failures_o = result_failures_q;
    assign flag_overflow_o = result_overflow_q;
    assign busy_o = (front_state_q != FRONT_IDLE) || pending_valid_q ||
                    (load_state_q != LOAD_IDLE) || search_busy || search_done ||
                    search_result_pending_q || result_valid_q || output_active_q;

    // One upstream message-buffer read port is shared.  Probe scan never runs
    // while output is active, so no multiport memory is assumed.
    always @* begin
        message_context_o = front_context_q;
        message_addr_o = '0;
        if (output_active_q) begin
            message_context_o = result_context_q;
            if (emit_beat_q > 0 && emit_beat_q <= DATA_BEATS)
                message_addr_o = emit_beat_q - 1'b1;
        end else if (front_state_q == FRONT_SCAN && scan_position >= L &&
                     scan_position < L+K) begin
            message_context_o = front_context_q;
            message_addr_o = scan_message_offset >> LANE_W;
        end
    end

    // Systematic parent-BCH remainder for the all-zero selector word.
    always @* begin
        remainder_next = front_remainder_q;
        for (lane = 0; lane < 128; lane = lane + 1) begin
            feedback = data_bits_i[W-1-crc_phase_q*128-lane] ^ remainder_next[R-1];
            remainder_next = {remainder_next[R-2:0],1'b0};
            if (feedback)
                remainder_next = remainder_next ^ BCH_GENERATOR[R-1:0];
        end
    end

    wire [W-1:0] payload_mask, parity_mask;
    pbch_mask_stream_cse mask_stream_u (
        .clk(clk), .load_i(output_active_q && out_ready_i && emit_beat_q == 0),
        .advance_i(output_active_q && out_ready_i && emit_beat_q > 0 && emit_beat_q <= DATA_BEATS),
        .selector_i(result_selector_q), .payload_mask_o(payload_mask),
        .parity_mask_o(parity_mask)
    );
    // Selector, payload and parity retain exactly the original bit order.
    always @* begin
        out_bits_o = '0;
        out_count_o = '0;
        out_last_o = 1'b0;
        if (output_active_q) begin
            out_last_o = emit_beat_q == EMIT_BEATS-1;
            if (emit_beat_q == 0) begin
                out_bits_o[W-1 -: L] = result_selector_q;
                out_count_o = L;
            end else if (emit_beat_q <= DATA_BEATS) begin
                out_bits_o = external_message_bits_i ^ payload_mask;
                out_count_o = W;
            end else begin
                out_bits_o[W-1 -: R] = result_remainder_q;
                out_bits_o = out_bits_o ^ parity_mask;
                out_count_o = R;
            end
        end
    end

    generate
        if (SEARCH_IMPL == 0) begin : sparse_gray_search
            selector_search_sparse_gray #(
                .L(L), .N(N), .MAX_FLAGS(MAX_FLAGS), .LANES(LANES)
            ) search_u (
                .clk(clk), .reset_n(reset_n), .start_i(search_start),
                .start_ready_o(search_start_ready), .label_i(search_add_label),
                .base_is_zero_i(search_add_base_zero),
                .add_valid_i(search_add_valid), .add_ready_o(),
                .finish_i(search_finish), .selector_o(search_selector),
                .best_score_o(search_best_score), .overflow_o(search_overflow),
                .done_o(search_done), .busy_o(search_busy)
            );
        end else if (SEARCH_IMPL == 1) begin : block_fwht_search
            selector_search_block_fwht #(
                .L(L), .N(N), .MAX_FLAGS(MAX_FLAGS), .HIGH_L(FWHT_HIGH_L)
            ) search_u (
                .clk(clk), .reset_n(reset_n), .start_i(search_start),
                .start_ready_o(search_start_ready), .label_i(search_add_label),
                .base_is_zero_i(search_add_base_zero),
                .add_valid_i(search_add_valid), .add_ready_o(),
                .finish_i(search_finish), .selector_o(search_selector),
                .best_score_o(search_best_score), .overflow_o(search_overflow),
                .done_o(search_done), .busy_o(search_busy)
            );
        end else begin : grouped_block_fwht_search
            selector_search_fwht_compact #(
                .L(L), .N(N), .MAX_FLAGS(MAX_FLAGS),
                .HIGH_L(FWHT_HIGH_L), .PIPE_GROUP(FWHT_PIPE_GROUP), .CHUNK(16), .EARLY_EXIT(0), .FUSE_INPUT(1), .MODULAR6(1), .HIST_STYLE(3), .DIRECT_STAGES(2)
            ) search_u (
                .clk(clk), .reset_n(reset_n), .start_i(search_start),
                .start_ready_o(search_start_ready), .label_i(search_add_label),
                .base_is_zero_i(search_add_base_zero),
                .add_valid_i(search_add_valid), .add_ready_o(),
                .finish_i(search_finish), .selector_o(search_selector),
                .best_score_o(search_best_score), .overflow_o(search_overflow),
                .done_o(search_done), .busy_o(search_busy)
            );
        end
    endgenerate

    probe_scan #(.N(N), .W(W)) scan_u (
        .clk(clk), .reset_n(reset_n), .start_i(scan_start),
        .bits_i(probe_bits_i), .count_i(probe_count_i),
        .valid_i(probe_valid_i), .ready_o(probe_ready_o),
        .position_o(scan_position), .flag_valid_o(scan_flag_valid),
        .finish_o(scan_finish), .total_o(scan_total), .busy_o()
    );

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            label_position_q <= '0;
            label_valid_q <= 1'b0;
            label_base_q <= 1'b0;
            label_finish_q <= 1'b0;
        end else begin
            label_valid_q <= scan_flag_valid;
            label_finish_q <= scan_finish;
            if (scan_flag_valid) begin
                label_position_q <= scan_position;
                label_base_q <= scan_base_bit;
            end
        end
    end

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) crc_phase_q <= '0;
        else if (start_i && start_ready_o) crc_phase_q <= '0;
        else if (front_state_q == FRONT_CAPTURE && data_valid_i)
            crc_phase_q <= crc_phase_q + 1'b1;
    end

    // Front end and pending exact-search context.
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            front_state_q <= FRONT_IDLE;
            front_context_q <= '0;
            front_remainder_q <= '0;
            data_seen_q <= '0;
            pending_count_q <= '0;
            pending_total_q <= '0;
            pending_overflow_q <= 1'b0;
            pending_remainder_q <= '0;
            pending_context_q <= '0;
        end else begin
            case (front_state_q)
                FRONT_IDLE: if (start_i && start_ready_o) begin
                    front_context_q <= context_i;
                    front_remainder_q <= '0;
                    data_seen_q <= '0;
                    pending_count_q <= '0;
                    pending_total_q <= '0;
                    pending_overflow_q <= 1'b0;
                    front_state_q <= FRONT_CAPTURE;
                end

                // The source holds a valid 512-bit beat until ready. Each
                // phase folds one slice into the exact BCH remainder.
                FRONT_CAPTURE: if (data_valid_i) begin
                    front_remainder_q <= remainder_next;
                    if (crc_phase_q == 3) begin
                        data_seen_q <= data_seen_q + data_count_i;
                        if (data_seen_q + data_count_i == K)
                            front_state_q <= FRONT_WAIT_SCAN;
                    end
                end

                FRONT_WAIT_SCAN: if (scan_start)
                    front_state_q <= FRONT_SCAN;

                FRONT_SCAN: begin
                    if (label_valid_q) begin
                        if (pending_count_q < MAX_FLAGS) begin
                            pending_label_q[pending_count_q] <= scan_column;
                            pending_base_zero_q[pending_count_q] <= !label_base_q;
                            pending_count_q <= pending_count_q + 1'b1;
                        end else begin
                            pending_overflow_q <= 1'b1;
                        end
                    end
                    if (label_finish_q) begin
                        pending_total_q <= scan_total;
                        pending_remainder_q <= front_remainder_q;
                        pending_context_q <= front_context_q;
                        front_state_q <= FRONT_IDLE;
                    end
                end
                default: front_state_q <= FRONT_IDLE;
            endcase
        end
    end

    // Pending-valid ownership and serialized context transfer into the exact
    // search core.  Overflow is reproduced with one extra dummy add so the
    // existing search core raises its explicit overflow output.
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            pending_valid_q <= 1'b0;
            load_state_q <= LOAD_IDLE;
            load_index_q <= '0;
            search_remainder_q <= '0;
            search_total_q <= '0;
            search_context_q <= '0;
        end else begin
            if (label_finish_q && front_state_q == FRONT_SCAN)
                pending_valid_q <= 1'b1;

            if (search_start) begin
                load_state_q <= LOAD_FLAGS;
                load_index_q <= '0;
                search_remainder_q <= pending_remainder_q;
                search_total_q <= pending_total_q;
                search_context_q <= pending_context_q;
            end else if (load_state_q == LOAD_FLAGS) begin
                if (search_finish) begin
                    load_state_q <= LOAD_IDLE;
                    pending_valid_q <= 1'b0;
                end else if (search_add_valid) begin
                    load_index_q <= load_index_q + 1'b1;
                end
            end
        end
    end

    // Reuse the search core's stable output registers as one completion slot.
    // Metadata cannot change until this slot is transferred to output.
    wire capture_result = (search_done || search_result_pending_q) &&
        (!result_valid_q || (output_active_q && out_ready_i && emit_beat_q == EMIT_BEATS-1));
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) search_result_pending_q <= 1'b0;
        else if (capture_result) search_result_pending_q <= 1'b0;
        else if (search_done) search_result_pending_q <= 1'b1;
    end

    // A result slot and the search completion slot absorb output stalls.
    // W=512 emits ten beats; an active probe scan owns the message port first.
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            result_valid_q <= 1'b0;
            output_active_q <= 1'b0;
            result_remainder_q <= '0;
            result_context_q <= '0;
            result_selector_q <= '0;
            result_failures_q <= '0;
            result_overflow_q <= 1'b0;
            emit_beat_q <= '0;
            done_o <= 1'b0;
        end else begin
            done_o <= 1'b0;
            if (capture_result) begin
                result_valid_q <= 1'b1;
                result_remainder_q <= search_remainder_q;
                result_context_q <= search_context_q;
                result_selector_q <= search_selector;
                result_failures_q <= search_overflow ? {CODE_W{1'b1}} :
                                     failure_delta[CODE_W:1];
                result_overflow_q <= search_overflow;
            end

            if (result_valid_q && !output_active_q &&
                front_state_q != FRONT_SCAN) begin
                output_active_q <= 1'b1;
                emit_beat_q <= '0;
            end else if (output_active_q && out_ready_i) begin
                if (emit_beat_q == EMIT_BEATS-1) begin
                    output_active_q <= 1'b0;
                    // A new search result may arrive on the same edge that
                    // the previous word's last beat is accepted.
                    if (!capture_result)
                        result_valid_q <= 1'b0;
                    done_o <= 1'b1;
                end else begin
                    emit_beat_q <= emit_beat_q + 1'b1;
                end
            end
        end
    end

`ifndef SYNTHESIS
    always @(posedge clk) begin
        if (reset_n && data_valid_i && data_ready_o && data_count_i != W)
            $error("PBCH pipeline data beats must contain W bits");
        if (reset_n && search_done && search_result_pending_q)
            $error("PBCH pipeline result context overflow");
        if (reset_n && output_active_q && front_state_q == FRONT_SCAN)
            $error("PBCH pipeline external message port conflict");
    end
`endif
endmodule

`default_nettype wire
