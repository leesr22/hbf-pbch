`default_nettype none

// Exact sparse-input, blocked Walsh-Hadamard selector search.
//
// The paper defines F = W_8192 H.  With selector/label bits split into
// HIGH_L and LOW_L parts,
//
//   F[d_hi,d_lo] = sum_a H[a] (-1)^(d_hi.a_hi) (-1)^(d_lo.a_lo).
//
// For one d_lo, the sparse flagged-cell list is first projected into a
// 2^HIGH_L-entry partial histogram indexed by a_hi.  A conventional
// HIGH_L-stage butterfly FWHT then produces every d_hi score in parallel.
// Repeating this for all 2^LOW_L values produces all 2^L scores exactly.
//
// This is a factored implementation of the paper's FWHT, not a heuristic:
// it removes the dense 8192-entry H/scratch array but retains a real
// butterfly network and returns the same exhaustive-search optimum.
module selector_search_block_fwht #(
    parameter integer L = 13,
    parameter integer N = 4278,
    parameter integer MAX_FLAGS = 32,
    parameter integer HIGH_L = 7,
    parameter integer LOW_L = L - HIGH_L,
    parameter integer BLOCK = (1 << HIGH_L),
    parameter integer OUTER = (1 << LOW_L),
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

    // One 2^HIGH_L-vector enters the butterfly pipeline every cycle.
    reg signed [ACC_W-1:0] value_q [0:HIGH_L][0:BLOCK-1];
    reg [HIGH_L:0] valid_q;
    reg [LOW_L-1:0] low_q [0:HIGH_L];
    reg [LOW_L:0] feed_count_q;
    reg [LOW_L:0] result_count_q;
    reg signed [ACC_W-1:0] best_q;
    reg [L-1:0] best_index_q;

    wire signed [ACC_W-1:0] partial_h [0:BLOCK-1];
    integer stage;
    integer item;

    // Sparse projection for the current low-selector value.  Only stored
    // flagged cells contribute; all absent H entries are implicit zeros.
    // A narrow balanced tree replaces the former serial full-width sum.
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
                    (flag_number < flag_count_q) &&
                    (label_q[flag_number][L-1:LOW_L] ==
                     bucket_number[HIGH_L-1:0]);
                assign contribution_positive[flag_number] =
                    base_zero_q[flag_number] ^
                    ^(feed_count_q[LOW_L-1:0] &
                      label_q[flag_number][LOW_L-1:0]);
            end
            sparse_signed_sum_tree #(.COUNT(MAX_FLAGS)) sum_u (
                .valid_i(contribution_valid),
                .positive_i(contribution_positive),
                .sum_o(partial_h[bucket_number])
            );
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
            assign max_value_input[output_number] = value_q[HIGH_L][output_number];
            assign max_index_input[output_number] =
                {output_number[HIGH_L-1:0],low_q[HIGH_L]};
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
                    // Feed all low-selector values, one per cycle.
                    valid_q[0] <= feed_count_q < OUTER;
                    // A normal radix-2 Walsh-Hadamard butterfly per stage.
                    // Descending order allows blocking assignments to retain
                    // pipeline semantics: every source belongs to the old
                    // cycle because its lower stage has not been overwritten.
                    for (stage = HIGH_L-1; stage >= 0; stage = stage - 1) begin
                        valid_q[stage+1] <= valid_q[stage];
                        low_q[stage+1] <= low_q[stage];
                        for (item = 0; item < BLOCK; item = item + 1) begin
                            if ((item & (1 << stage)) == 0)
                                value_q[stage+1][item] =
                                    value_q[stage][item] +
                                    value_q[stage][item ^ (1 << stage)];
                            else
                                value_q[stage+1][item] =
                                    value_q[stage][item ^ (1 << stage)] -
                                    value_q[stage][item];
                        end
                    end
                    if (feed_count_q < OUTER) begin
                        for (item = 0; item < BLOCK; item = item + 1)
                            value_q[0][item] = partial_h[item];
                        low_q[0] <= feed_count_q[LOW_L-1:0];
                        feed_count_q <= feed_count_q + 1'b1;
                    end

                    if (valid_q[HIGH_L]) begin
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
            OUTER != (1 << LOW_L))
            $error("blocked FWHT parameters are inconsistent");
    end
`endif
endmodule

`default_nettype wire
