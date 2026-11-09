`default_nettype none

// Exact exhaustive selector search for PBCH(l=13), capped at 32 flags.
//
// The 13-bit label and selector are split as [high 7 | low 6].  For each of
// the 64 low-selector values, the first six logical FWHT stages are evaluated
// directly from the sparse flag list.  A real 128-point, seven-stage butterfly
// then evaluates all 128 high-selector values.  Thus 64*128=8192 selectors are
// scored exactly.  The seven stages are one combinational group (G7), so only
// the input and output vectors are registered.
module fwht_search_h7 (
    input  wire              clk,
    input  wire              reset_n,
    input  wire              start_i,
    output wire              start_ready_o,
    input  wire [12:0]       label_i,
    input  wire              base_is_zero_i,
    input  wire              add_valid_i,
    input  wire              finish_i,
    output reg  [12:0]       selector_o,
    output reg signed [6:0]  best_score_o,
    output reg               done_o,
    output wire              busy_o
);
    localparam integer MAX_FLAGS = 32;
    localparam integer BLOCK = 128;
    localparam integer GROUPS = 64;
    localparam signed [6:0] MIN_SCORE = -7'sd64;
    localparam [1:0] IDLE = 2'd0, LOAD = 2'd1, SEARCH = 2'd2;

    reg [1:0] state_q;
    reg [5:0] flag_count_q;
    reg [12:0] label_q [0:MAX_FLAGS-1];
    reg base_zero_q [0:MAX_FLAGS-1];

    reg signed [6:0] fwht_input_q [0:BLOCK-1];
    reg signed [6:0] fwht_output_q [0:BLOCK-1];
    reg input_valid_q;
    reg output_valid_q;
    reg [5:0] input_group_q;
    reg [5:0] output_group_q;
    reg [6:0] groups_started_q;
    reg [6:0] groups_finished_q;
    reg signed [6:0] best_q;
    reg [12:0] best_index_q;

    // Sparse projection: this is mathematically the first six FWHT stages.
    wire signed [6:0] partial_h [0:BLOCK-1];
    wire [MAX_FLAGS-1:0] flag_active;
    wire [MAX_FLAGS-1:0] flag_positive;

    genvar f;
    generate
        for (f = 0; f < MAX_FLAGS; f = f + 1) begin : flag_sign
            assign flag_active[f] = f < flag_count_q;
            assign flag_positive[f] = base_zero_q[f] ^
                ^(groups_started_q[5:0] & label_q[f][5:0]);
        end
    endgenerate

    genvar bucket;
    genvar flag;
    generate
        for (bucket = 0; bucket < BLOCK; bucket = bucket + 1) begin : histogram
            wire [MAX_FLAGS-1:0] valid_contribution;
            for (flag = 0; flag < MAX_FLAGS; flag = flag + 1) begin : item
                assign valid_contribution[flag] = flag_active[flag] &&
                    (label_q[flag][12:6] == bucket[6:0]);
            end
            signed_sum_tree #(.COUNT(MAX_FLAGS), .SUM_W(7)) sum_u (
                .valid_i(valid_contribution),
                .positive_i(flag_positive),
                .sum_o(partial_h[bucket])
            );
        end
    endgenerate

    // Seven explicit FWHT butterfly stages, all combinationally grouped.
    wire signed [6:0] stage [0:7][0:BLOCK-1];
    genvar item;
    generate
        for (item = 0; item < BLOCK; item = item + 1)
            assign stage[0][item] = fwht_input_q[item];
    endgenerate

    genvar s;
    generate
        for (s = 0; s < 7; s = s + 1) begin : fwht_stage
            for (item = 0; item < BLOCK; item = item + 1) begin : butterfly
                localparam integer PARTNER = item ^ (1 << s);
                if ((item & (1 << s)) == 0) begin : add
                    assign stage[s+1][item] = stage[s][item] + stage[s][PARTNER];
                end else begin : subtract
                    assign stage[s+1][item] = stage[s][PARTNER] - stage[s][item];
                end
            end
        end
    endgenerate

    wire signed [6:0] group_best_score;
    wire [12:0] group_best_selector;
    wire signed [6:0] score_to_compare [0:BLOCK-1];
    wire [12:0] selector_to_compare [0:BLOCK-1];
    genvar candidate;
    generate
        for (candidate = 0; candidate < BLOCK; candidate = candidate + 1) begin : candidates
            assign score_to_compare[candidate] = fwht_output_q[candidate];
            assign selector_to_compare[candidate] = {candidate[6:0],output_group_q};
        end
    endgenerate

    fwht_max_tree #(.COUNT(BLOCK), .SCORE_W(7), .INDEX_W(13)) max_u (
        .value_i(score_to_compare), .index_i(selector_to_compare),
        .value_o(group_best_score), .index_o(group_best_selector)
    );

    wire group_wins =
        ($signed(group_best_score) > $signed(best_q)) ||
        (($signed(group_best_score) == $signed(best_q)) &&
         (group_best_selector < best_index_q));

    assign start_ready_o = state_q == IDLE;
    assign busy_o = state_q != IDLE;

    integer i;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state_q <= IDLE;
            flag_count_q <= '0;
            input_valid_q <= 1'b0;
            output_valid_q <= 1'b0;
            groups_started_q <= '0;
            groups_finished_q <= '0;
            best_q <= MIN_SCORE;
            best_index_q <= '0;
            selector_o <= '0;
            best_score_o <= '0;
            done_o <= 1'b0;
        end else begin
            done_o <= 1'b0;
            case (state_q)
                IDLE: if (start_i) begin
                    flag_count_q <= '0;
                    state_q <= LOAD;
                end

                LOAD: begin
                    if (add_valid_i && flag_count_q < MAX_FLAGS) begin
                        label_q[flag_count_q] <= label_i;
                        base_zero_q[flag_count_q] <= base_is_zero_i;
                        flag_count_q <= flag_count_q + 1'b1;
                    end
                    if (finish_i) begin
                        input_valid_q <= 1'b0;
                        output_valid_q <= 1'b0;
                        groups_started_q <= '0;
                        groups_finished_q <= '0;
                        best_q <= MIN_SCORE;
                        best_index_q <= '0;
                        state_q <= SEARCH;
                    end
                end

                SEARCH: begin
                    // Feed one low-selector group per cycle.
                    input_valid_q <= groups_started_q < GROUPS;
                    if (groups_started_q < GROUPS) begin
                        for (i = 0; i < BLOCK; i = i + 1)
                            fwht_input_q[i] <= partial_h[i];
                        input_group_q <= groups_started_q[5:0];
                        groups_started_q <= groups_started_q + 1'b1;
                    end

                    // One G7 register boundary after the seven stages.
                    output_valid_q <= input_valid_q;
                    if (input_valid_q) begin
                        for (i = 0; i < BLOCK; i = i + 1)
                            fwht_output_q[i] <= stage[7][i];
                        output_group_q <= input_group_q;
                    end

                    if (output_valid_q) begin
                        if (group_wins) begin
                            best_q <= group_best_score;
                            best_index_q <= group_best_selector;
                        end
                        if (groups_finished_q == GROUPS-1) begin
                            selector_o <= group_wins ?
                                          group_best_selector : best_index_q;
                            best_score_o <= group_wins ?
                                            group_best_score : best_q;
                            done_o <= 1'b1;
                            state_q <= IDLE;
                        end else begin
                            groups_finished_q <= groups_finished_q + 1'b1;
                        end
                    end
                end
                default: state_q <= IDLE;
            endcase
        end
    end
endmodule

`default_nettype wire
