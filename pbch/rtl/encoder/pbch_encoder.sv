`default_nettype none

// PBCH(k=4096,t=13,l=13) encoder with codeword-level stage overlap.
//
// At most the first 32 pre-read flags are retained.  Those flags are searched
// exactly across all 8192 selectors by fwht_search_h7.  Later flags are ignored
// by selector selection and only raise flags_truncated_o; encoding still
// completes normally.
//
// Message data remains in an upstream multi-context write buffer.  The context
// output selects that buffer entry for probe scoring or final codeword replay.
module pbch_fwht_encoder #(
    parameter integer K = 4096,
    parameter integer L = 13,
    parameter integer R = 169,
    parameter integer N = K + L + R,
    parameter integer W = 128,
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
    parameter integer DATA_BEAT_W = $clog2(DATA_BEATS + 1),
    parameter integer EMIT_BEAT_W = $clog2(EMIT_BEATS),
    parameter integer LANE_W = $clog2(W)
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
    output wire [CODE_W-1:0]            selected_failures_o,
    output wire                         flags_truncated_o,
    output reg                          done_o,
    output wire                         busy_o
);
    localparam integer MAX_FLAGS = 32;
    localparam [1:0] FRONT_IDLE = 2'd0, FRONT_CAPTURE = 2'd1,
                     FRONT_WAIT_SCAN = 2'd2, FRONT_SCAN = 2'd3;
    localparam        LOAD_IDLE = 1'b0, LOAD_FLAGS = 1'b1;

    reg [1:0] front_state_q;
    reg load_state_q;

    reg [CONTEXT_W-1:0] front_context_q;
    reg [R-1:0] front_remainder_q;
    reg [DATA_W-1:0] data_seen_q;

    reg pending_valid_q;
    reg [L-1:0] pending_label_q [0:MAX_FLAGS-1];
    reg pending_base_zero_q [0:MAX_FLAGS-1];
    reg [5:0] pending_count_q;
    reg pending_truncated_q;
    reg [R-1:0] pending_remainder_q;
    reg [CONTEXT_W-1:0] pending_context_q;

    reg [5:0] load_index_q;
    reg [R-1:0] search_remainder_q;
    reg [5:0] search_count_q;
    reg search_truncated_q;
    reg [CONTEXT_W-1:0] search_context_q;

    reg result_valid_q;
    reg output_active_q;
    reg [R-1:0] result_remainder_q;
    reg [CONTEXT_W-1:0] result_context_q;
    reg [L-1:0] result_selector_q;
    reg [CODE_W-1:0] result_failures_q;
    reg result_truncated_q;
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
    wire scan_flag_valid;
    wire scan_finish;
    wire [L-1:0] scan_column = G0_COLUMNS[scan_position*L +: L];
    wire [CODE_W-1:0] scan_message_offset = scan_position - L;
    wire scan_base_bit = (scan_position < L) ? 1'b0 :
                         (scan_position < L+K) ?
                         external_message_bits_i
                           [W-1-scan_message_offset[LANE_W-1:0]] :
                         front_remainder_q[R-1-(scan_position-L-K)];

    wire search_start_ready;
    wire search_start = (load_state_q == LOAD_IDLE) && pending_valid_q &&
                        search_start_ready;
    wire [5:0] load_count = pending_count_q;
    wire search_add_valid = (load_state_q == LOAD_FLAGS) &&
                            (load_index_q < load_count);
    wire [L-1:0] search_add_label = pending_label_q[load_index_q];
    wire search_add_base_zero = pending_base_zero_q[load_index_q];
    wire search_finish = (load_state_q == LOAD_FLAGS) &&
                         ((load_count == 0) ||
                          (search_add_valid && load_index_q + 1'b1 == load_count));
    wire search_done;
    wire search_busy;
    wire [L-1:0] search_selector;
    wire signed [6:0] search_best_score;
    wire signed [7:0] failure_delta =
        $signed({2'b00,search_count_q}) - $signed(search_best_score);

    assign start_ready_o = (front_state_q == FRONT_IDLE) && !pending_valid_q;
    assign data_ready_o = front_state_q == FRONT_CAPTURE;
    assign out_valid_o = output_active_q;
    assign result_context_o = result_context_q;
    assign selector_o = result_selector_q;
    assign selected_failures_o = result_failures_q;
    assign flags_truncated_o = result_truncated_q;
    assign busy_o = (front_state_q != FRONT_IDLE) || pending_valid_q ||
                    (load_state_q != LOAD_IDLE) || search_busy ||
                    result_valid_q || output_active_q;

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
        for (lane = 0; lane < W; lane = lane + 1) begin
            feedback = data_bits_i[W-1-lane] ^ remainder_next[R-1];
            remainder_next = {remainder_next[R-2:0],1'b0};
            if (feedback)
                remainder_next = remainder_next ^ BCH_GENERATOR[R-1:0];
        end
    end

    // Final selected codeword.  The upstream context buffer supplies message
    // beats; selector and parity are held in the result context.
    always @* begin
        out_bits_o = '0;
        out_count_o = '0;
        out_last_o = 1'b0;
        base_chunk = '0;
        column_chunk = G0_BEAT_COLUMNS[emit_beat_q*W*L +: W*L];
        valid_now = 0;
        parity_beat = 0;
        if (output_active_q) begin
            if (emit_beat_q == 0) begin
                valid_now = L;
            end else if (emit_beat_q <= DATA_BEATS) begin
                valid_now = W;
                base_chunk = external_message_bits_i;
            end else begin
                parity_beat = emit_beat_q - 1 - DATA_BEATS;
                valid_now = ((R - parity_beat*W) > W) ?
                            W : (R - parity_beat*W);
                for (lane = 0; lane < W; lane = lane + 1)
                    if (lane < valid_now)
                        base_chunk[W-1-lane] =
                            result_remainder_q[R-1-parity_beat*W-lane];
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
                            (result_selector_q[selector_bit] & column[selector_bit]);
                    out_bits_o[W-1-lane] = base_bit ^ mask_bit;
                end
            end
        end
    end

    fwht_search_h7 search_u (
        .clk(clk), .reset_n(reset_n), .start_i(search_start),
        .start_ready_o(search_start_ready), .label_i(search_add_label),
        .base_is_zero_i(search_add_base_zero),
        .add_valid_i(search_add_valid), .finish_i(search_finish),
        .selector_o(search_selector), .best_score_o(search_best_score),
        .done_o(search_done), .busy_o(search_busy)
    );

    probe_scan #(.N(N), .W(W)) scan_u (
        .clk(clk), .reset_n(reset_n), .start_i(scan_start),
        .bits_i(probe_bits_i), .count_i(probe_count_i),
        .valid_i(probe_valid_i), .ready_o(probe_ready_o),
        .position_o(scan_position), .flag_valid_o(scan_flag_valid),
        .finish_o(scan_finish), .busy_o()
    );

    // Front end and pending exact-search context.
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            front_state_q <= FRONT_IDLE;
            front_context_q <= '0;
            front_remainder_q <= '0;
            data_seen_q <= '0;
            pending_count_q <= '0;
            pending_truncated_q <= 1'b0;
            pending_remainder_q <= '0;
            pending_context_q <= '0;
        end else begin
            case (front_state_q)
                FRONT_IDLE: if (start_i && start_ready_o) begin
                    front_context_q <= context_i;
                    front_remainder_q <= '0;
                    data_seen_q <= '0;
                    pending_count_q <= '0;
                    pending_truncated_q <= 1'b0;
                    front_state_q <= FRONT_CAPTURE;
                end

                FRONT_CAPTURE: if (data_valid_i && data_ready_o) begin
                    front_remainder_q <= remainder_next;
                    data_seen_q <= data_seen_q + data_count_i;
                    if (data_seen_q + data_count_i == K)
                        front_state_q <= FRONT_WAIT_SCAN;
                end

                FRONT_WAIT_SCAN: if (scan_start)
                    front_state_q <= FRONT_SCAN;

                FRONT_SCAN: begin
                    if (scan_flag_valid) begin
                        if (pending_count_q < MAX_FLAGS) begin
                            pending_label_q[pending_count_q] <= scan_column;
                            pending_base_zero_q[pending_count_q] <= !scan_base_bit;
                            pending_count_q <= pending_count_q + 1'b1;
                        end else begin
                            pending_truncated_q <= 1'b1;
                        end
                    end
                    if (scan_finish) begin
                        pending_remainder_q <= front_remainder_q;
                        pending_context_q <= front_context_q;
                        front_state_q <= FRONT_IDLE;
                    end
                end
                default: front_state_q <= FRONT_IDLE;
            endcase
        end
    end

    // Transfer the retained flag list into the exact H7 search core.
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            pending_valid_q <= 1'b0;
            load_state_q <= LOAD_IDLE;
            load_index_q <= '0;
            search_remainder_q <= '0;
            search_count_q <= '0;
            search_truncated_q <= 1'b0;
            search_context_q <= '0;
        end else begin
            if (scan_finish && front_state_q == FRONT_SCAN)
                pending_valid_q <= 1'b1;

            if (search_start) begin
                load_state_q <= LOAD_FLAGS;
                load_index_q <= '0;
                search_remainder_q <= pending_remainder_q;
                search_count_q <= pending_count_q;
                search_truncated_q <= pending_truncated_q;
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

    // Hold one completed result while its codeword is streamed.  Emission waits
    // for an active probe scan because both use the same upstream message port.
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            result_valid_q <= 1'b0;
            output_active_q <= 1'b0;
            result_remainder_q <= '0;
            result_context_q <= '0;
            result_selector_q <= '0;
            result_failures_q <= '0;
            result_truncated_q <= 1'b0;
            emit_beat_q <= '0;
            done_o <= 1'b0;
        end else begin
            done_o <= 1'b0;
            if (search_done) begin
                result_valid_q <= 1'b1;
                result_remainder_q <= search_remainder_q;
                result_context_q <= search_context_q;
                result_selector_q <= search_selector;
                // This count covers only the retained (at most 32) flags.
                result_failures_q <= {{(CODE_W-7){1'b0}},failure_delta[7:1]};
                result_truncated_q <= search_truncated_q;
            end

            if (result_valid_q && !output_active_q &&
                front_state_q != FRONT_SCAN &&
                front_state_q != FRONT_WAIT_SCAN) begin
                output_active_q <= 1'b1;
                emit_beat_q <= '0;
            end else if (output_active_q && out_ready_i) begin
                if (emit_beat_q == EMIT_BEATS-1) begin
                    output_active_q <= 1'b0;
                    // A new search result may arrive on the same edge that
                    // the previous word's last beat is accepted.
                    if (!search_done)
                        result_valid_q <= 1'b0;
                    done_o <= 1'b1;
                end else begin
                    emit_beat_q <= emit_beat_q + 1'b1;
                end
            end
        end
    end

`ifndef SYNTHESIS
    initial begin
        if (K != 4096 || L != 13 || R != 169 || N != 4278)
            $error("pbch_fwht_encoder supports only k=4096,t=13,l=13");
    end

    always @(posedge clk) begin
        if (reset_n && data_valid_i && data_ready_o && data_count_i != W)
            $error("PBCH pipeline data beats must contain W bits");
        if (reset_n && search_done && result_valid_q && !output_active_q)
            $error("PBCH pipeline result context overflow");
        if (reset_n && output_active_q && front_state_q == FRONT_SCAN)
            $error("PBCH pipeline external message port conflict");
    end
`endif
endmodule

`default_nettype wire
