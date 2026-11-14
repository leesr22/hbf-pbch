`default_nettype none

// Exact sparse-input blocked FWHT with grouped butterfly pipeline stages.
//
// The mathematical transform is identical to selector_search_block_fwht:
// one 2^HIGH_L point FWHT is evaluated for every low-selector value.  The
// only difference is physical pipelining.  PIPE_GROUP consecutive butterfly
// stages are combinationally cascaded between register banks, reducing the
// large vector-register cost while preserving every FWHT stage and score.
module selector_search_block_fwht_grouped #(
    parameter integer L = 13,
    parameter integer N = 4278,
    parameter integer MAX_FLAGS = 32,
    parameter integer HIGH_L = 7,
    parameter integer LOW_L = L - HIGH_L,
    parameter integer PIPE_GROUP = 2,
    parameter integer BLOCK = (1 << HIGH_L),
    parameter integer OUTER = (1 << LOW_L),
    parameter integer PIPE_COUNT = (HIGH_L + PIPE_GROUP - 1) / PIPE_GROUP,
    // Direct constant comparisons synthesize 0.018% smaller than the explicit
    // shared predecoder in the target UMC28 flow.  Keep the predecoder as a
    // reproducible DSE option, but use the measured-better direct form.
    parameter integer HIST_PREDECODE = 0,
    parameter integer FLAG_COUNT_W = $clog2(MAX_FLAGS + 1),
    parameter integer SCORE_W = $clog2(N + 1) + 1,
    parameter integer ACC_W = $clog2(MAX_FLAGS + 1) + 1
) (
    input  wire                      clk,
    input  wire                      reset_n,
    input  wire                      start_i,
    output wire                      start_ready_o,
    input  wire [L-1:0]              label_i,
    input  wire                      base_is_zero_i,
    input  wire                      add_valid_i,
    output wire                      add_ready_o,
    input  wire                      finish_i,
    output reg  [L-1:0]              selector_o,
    output reg signed [SCORE_W-1:0] best_score_o,
    output reg                       overflow_o,
    output reg                       done_o,
    output wire                      busy_o
);
    localparam [1:0] IDLE = 2'd0, LOAD = 2'd1, SEARCH = 2'd2;
    localparam signed [ACC_W-1:0] MIN_SCORE =
        {1'b1,{(ACC_W-1){1'b0}}};

    reg [1:0] state_q;
    reg [FLAG_COUNT_W-1:0] flag_count_q;
    reg [L-1:0] label_q [0:MAX_FLAGS-1];
    reg base_zero_q [0:MAX_FLAGS-1];

    // value_q[0] is the registered partial histogram.  Each following bank
    // holds the result after PIPE_GROUP more mathematical FWHT stages.
    reg signed [ACC_W-1:0] value_q [0:PIPE_COUNT][0:BLOCK-1];
    reg [PIPE_COUNT:0] valid_q;
    reg [LOW_L-1:0] low_q [0:PIPE_COUNT];
    reg [LOW_L:0] feed_count_q;
    reg [LOW_L:0] result_count_q;
    reg signed [ACC_W-1:0] best_q;
    reg [L-1:0] best_index_q;

    wire signed [ACC_W-1:0] partial_h [0:BLOCK-1];

    // Decode each flag label once, then share the one-hot result across all
    // histogram buckets.  Splitting the HIGH_L decode into two small
    // predecoders avoids re-building a HIGH_L-bit equality comparator in
    // every (bucket,flag) contribution cell.
    localparam integer DEC_LO_W = HIGH_L / 2;
    localparam integer DEC_HI_W = HIGH_L - DEC_LO_W;
    localparam integer DEC_LO_N = (1 << DEC_LO_W);
    localparam integer DEC_HI_N = (1 << DEC_HI_W);
    wire [BLOCK-1:0] flag_bucket_onehot [0:MAX_FLAGS-1];
    wire [MAX_FLAGS-1:0] flag_active;
    wire [MAX_FLAGS-1:0] flag_positive;

    genvar decode_flag;
    genvar decode_value;
    generate
        for (decode_flag = 0; decode_flag < MAX_FLAGS;
             decode_flag = decode_flag + 1) begin : flag_decode
            wire [HIGH_L-1:0] bucket_label =
                label_q[decode_flag][L-1:LOW_L];
            if (HIST_PREDECODE != 0) begin : shared_predecode
                wire [DEC_LO_N-1:0] low_match;
                wire [DEC_HI_N-1:0] high_match;
                for (decode_value = 0; decode_value < DEC_LO_N;
                     decode_value = decode_value + 1) begin : low
                    assign low_match[decode_value] =
                        bucket_label[DEC_LO_W-1:0] ==
                        decode_value[DEC_LO_W-1:0];
                end
                for (decode_value = 0; decode_value < DEC_HI_N;
                     decode_value = decode_value + 1) begin : high
                    assign high_match[decode_value] =
                        bucket_label[HIGH_L-1:DEC_LO_W] ==
                        decode_value[DEC_HI_W-1:0];
                end
                for (decode_value = 0; decode_value < BLOCK;
                     decode_value = decode_value + 1) begin : combine
                    assign flag_bucket_onehot[decode_flag][decode_value] =
                        low_match[decode_value % DEC_LO_N] &
                        high_match[decode_value / DEC_LO_N];
                end
            end else begin : direct_decode
                for (decode_value = 0; decode_value < BLOCK;
                     decode_value = decode_value + 1) begin : compare
                    assign flag_bucket_onehot[decode_flag][decode_value] =
                        bucket_label == decode_value[HIGH_L-1:0];
                end
            end
            assign flag_active[decode_flag] = decode_flag < flag_count_q;
            assign flag_positive[decode_flag] =
                base_zero_q[decode_flag] ^
                ^(feed_count_q[LOW_L-1:0] &
                  label_q[decode_flag][LOW_L-1:0]);
        end
    endgenerate

    // The combinational wires expose every physical butterfly stage.  Stages
    // beyond HIGH_L in the final group are compile-time pass-through wires.
    wire signed [ACC_W-1:0] group_value
        [0:PIPE_COUNT-1][0:PIPE_GROUP][0:BLOCK-1];

    genvar bucket_number;
    genvar flag_number;
    generate
        for (bucket_number = 0; bucket_number < BLOCK;
             bucket_number = bucket_number + 1) begin : partial_histogram
            wire [MAX_FLAGS-1:0] contribution_valid;
            wire [MAX_FLAGS-1:0] contribution_positive;
            for (flag_number = 0; flag_number < MAX_FLAGS;
                 flag_number = flag_number + 1) begin : flag_contribution
                assign contribution_valid[flag_number] =
                    flag_active[flag_number] &&
                    flag_bucket_onehot[flag_number][bucket_number];
                assign contribution_positive[flag_number] =
                    flag_positive[flag_number];
            end
            sparse_signed_sum_tree #(.COUNT(MAX_FLAGS)) sum_u (
                .valid_i(contribution_valid),
                .positive_i(contribution_positive),
                .sum_o(partial_h[bucket_number])
            );
        end
    endgenerate

    genvar group_number;
    genvar local_stage;
    genvar item_number;
    generate
        for (group_number = 0; group_number < PIPE_COUNT;
             group_number = group_number + 1) begin : butterfly_group
            for (item_number = 0; item_number < BLOCK;
                 item_number = item_number + 1) begin : group_input
                assign group_value[group_number][0][item_number] =
                    value_q[group_number][item_number];
            end
            for (local_stage = 0; local_stage < PIPE_GROUP;
                 local_stage = local_stage + 1) begin : stage
                localparam integer GLOBAL_STAGE =
                    group_number * PIPE_GROUP + local_stage;
                for (item_number = 0; item_number < BLOCK;
                     item_number = item_number + 1) begin : butterfly
                    if (GLOBAL_STAGE < HIGH_L) begin : active
                        localparam integer PARTNER =
                            item_number ^ (1 << GLOBAL_STAGE);
                        if ((item_number & (1 << GLOBAL_STAGE)) == 0) begin : sum
                            assign group_value[group_number][local_stage+1]
                                              [item_number] =
                                group_value[group_number][local_stage][item_number] +
                                group_value[group_number][local_stage][PARTNER];
                        end else begin : difference
                            assign group_value[group_number][local_stage+1]
                                              [item_number] =
                                group_value[group_number][local_stage][PARTNER] -
                                group_value[group_number][local_stage][item_number];
                        end
                    end else begin : bypass
                        assign group_value[group_number][local_stage+1]
                                          [item_number] =
                            group_value[group_number][local_stage][item_number];
                    end
                end
            end
        end
    endgenerate

    wire signed [ACC_W-1:0] block_max_value;
    wire [L-1:0] block_max_index;
    wire signed [ACC_W-1:0] max_value_input [0:BLOCK-1];
    wire [L-1:0] max_index_input [0:BLOCK-1];
    genvar output_number;
    generate
        for (output_number = 0; output_number < BLOCK;
             output_number = output_number + 1) begin : max_inputs
            assign max_value_input[output_number] =
                value_q[PIPE_COUNT][output_number];
            assign max_index_input[output_number] =
                {output_number[HIGH_L-1:0],low_q[PIPE_COUNT]};
        end
    endgenerate

    fht_max_tree #(
        .COUNT(BLOCK), .SCORE_W(ACC_W), .INDEX_W(L)
    ) max_u (
        .value_i(max_value_input), .index_i(max_index_input),
        .value_o(block_max_value), .index_o(block_max_index)
    );

    wire block_max_is_better =
        ($signed(block_max_value) > $signed(best_q)) ||
        (($signed(block_max_value) == $signed(best_q)) &&
         (block_max_index < best_index_q));

    assign start_ready_o = state_q == IDLE;
    assign add_ready_o = state_q == LOAD;
    assign busy_o = state_q != IDLE;

    integer pipe_index;
    integer item;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state_q <= IDLE;
            flag_count_q <= '0;
            valid_q <= '0;
            feed_count_q <= '0;
            result_count_q <= '0;
            best_q <= MIN_SCORE;
            best_index_q <= '0;
            selector_o <= '0;
            best_score_o <= '0;
            overflow_o <= 1'b0;
            done_o <= 1'b0;
        end else begin
            done_o <= 1'b0;
            case (state_q)
                IDLE: if (start_i) begin
                    flag_count_q <= '0;
                    valid_q <= '0;
                    overflow_o <= 1'b0;
                    state_q <= LOAD;
                end

                LOAD: begin
                    if (add_valid_i) begin
                        if (flag_count_q < MAX_FLAGS) begin
                            label_q[flag_count_q] <= label_i;
                            base_zero_q[flag_count_q] <= base_is_zero_i;
                            flag_count_q <= flag_count_q + 1'b1;
                        end else begin
                            overflow_o <= 1'b1;
                        end
                    end
                    if (finish_i) begin
                        valid_q <= '0;
                        feed_count_q <= '0;
                        result_count_q <= '0;
                        best_q <= MIN_SCORE;
                        best_index_q <= '0;
                        state_q <= SEARCH;
                    end
                end

                SEARCH: begin
                    valid_q[0] <= feed_count_q < OUTER;
                    if (feed_count_q < OUTER) begin
                        for (item = 0; item < BLOCK; item = item + 1)
                            value_q[0][item] <= partial_h[item];
                        low_q[0] <= feed_count_q[LOW_L-1:0];
                        feed_count_q <= feed_count_q + 1'b1;
                    end

                    for (pipe_index = 0; pipe_index < PIPE_COUNT;
                         pipe_index = pipe_index + 1) begin
                        valid_q[pipe_index+1] <= valid_q[pipe_index];
                        low_q[pipe_index+1] <= low_q[pipe_index];
                        for (item = 0; item < BLOCK; item = item + 1)
                            value_q[pipe_index+1][item] <=
                                group_value[pipe_index][PIPE_GROUP][item];
                    end

                    if (valid_q[PIPE_COUNT]) begin
                        if (block_max_is_better) begin
                            best_q <= block_max_value;
                            best_index_q <= block_max_index;
                        end
                        if (result_count_q == OUTER-1) begin
                            selector_o <= block_max_is_better ?
                                          block_max_index : best_index_q;
                            best_score_o <= block_max_is_better ?
                                {{(SCORE_W-ACC_W){block_max_value[ACC_W-1]}},
                                 block_max_value} :
                                {{(SCORE_W-ACC_W){best_q[ACC_W-1]}},best_q};
                            done_o <= 1'b1;
                            valid_q <= '0;
                            state_q <= IDLE;
                        end else begin
                            result_count_q <= result_count_q + 1'b1;
                        end
                    end
                end
                default: state_q <= IDLE;
            endcase
        end
    end

`ifndef SYNTHESIS
    initial begin
        if (HIGH_L + LOW_L != L || BLOCK != (1 << HIGH_L) ||
            OUTER != (1 << LOW_L) || PIPE_GROUP < 1)
            $error("grouped blocked FWHT parameters are inconsistent");
    end
`endif
endmodule

`default_nettype wire
