`default_nettype none

// Exact exhaustive selector search for a sparse probe result.
//
// Rather than materializing the 2^L-entry H array, this engine stores only
// the labels of flagged cells.  LANES aligned Gray-code walks collectively
// visit every selector exactly once.  Adjacent items in each walk differ in
// one selector bit, so a flag contribution changes only when that bit is set
// in the stored label.
//
// The result is bit-for-bit equal to exhaustive search while the number of
// flags is at most MAX_FLAGS.  overflow_o is explicit; callers must use an
// exact slow path or another policy when it is asserted.
module selector_search_sparse_gray #(
    parameter integer L = 13,
    parameter integer N = 4278,
    parameter integer MAX_FLAGS = 32,
    parameter integer LANES = 32,
    parameter integer SIZE = (1 << L),
    parameter integer ITEMS_PER_LANE = SIZE / LANES,
    parameter integer OFFSET_W = $clog2(ITEMS_PER_LANE),
    parameter integer FLAG_COUNT_W = $clog2(MAX_FLAGS + 1),
    parameter integer SCORE_W = $clog2(N + 1) + 1,
    parameter integer ACC_W = $clog2(MAX_FLAGS + 1) + 1,
    parameter integer DELTA_W = ACC_W + 1
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
    reg [OFFSET_W-1:0] offset_q;
    reg [L-1:0] label_q [0:MAX_FLAGS-1];
    // phase_q combines the required base value with the parity accumulated
    // along the low-bit Gray walk.  Keeping one phase bit instead of separate
    // preference and low-parity bits saves both state and a replicated XOR.
    reg phase_q [0:MAX_FLAGS-1];
    reg signed [ACC_W-1:0] lane_score_q [0:LANES-1];
    reg signed [ACC_W-1:0] best_q;
    reg [L-1:0] best_index_q;

    function automatic [L-1:0] lane_start_selector;
        input integer lane_number;
        reg [L-1:0] binary_start;
        begin
            binary_start = lane_number * ITEMS_PER_LANE;
            lane_start_selector = binary_start ^ (binary_start >> 1);
        end
    endfunction

    wire [OFFSET_W-1:0] offset_plus_one = offset_q + 1'b1;
    // Gray(x) to Gray(x+1) toggles the least-significant set bit of x+1.
    wire [OFFSET_W-1:0] changed_onehot =
        offset_plus_one & (~offset_q);
    wire [OFFSET_W-1:0] gray_offset = offset_q ^ (offset_q >> 1);

    integer lane;
    integer flag;
    reg initial_match;
    wire toggle_flag [0:MAX_FLAGS-1];
    genvar toggle_number;
    generate
        for (toggle_number = 0; toggle_number < MAX_FLAGS;
             toggle_number = toggle_number + 1) begin : flag_toggle
            assign toggle_flag[toggle_number] =
                (toggle_number < flag_count_q) &&
                |(label_q[toggle_number][OFFSET_W-1:0] & changed_onehot);
        end
    endgenerate

    wire signed [DELTA_W-1:0] lane_delta [0:LANES-1];
    wire lane_match [0:LANES-1][0:MAX_FLAGS-1];
    genvar delta_lane;
    genvar delta_flag;
    generate
        for (delta_lane = 0; delta_lane < LANES;
             delta_lane = delta_lane + 1) begin : lane_delta_tree
            for (delta_flag = 0; delta_flag < MAX_FLAGS;
                 delta_flag = delta_flag + 1) begin : match_value
                assign lane_match[delta_lane][delta_flag] =
                    phase_q[delta_flag] ^
                    ^(label_q[delta_flag] &
                      lane_start_selector(delta_lane));
            end
            sparse_delta_tree #(
                .COUNT(MAX_FLAGS), .SCORE_W(DELTA_W)
            ) delta_u (
                .toggle_i(toggle_flag), .match_i(lane_match[delta_lane]),
                .delta_o(lane_delta[delta_lane])
            );
        end
    endgenerate

    wire signed [ACC_W-1:0] lane_value [0:LANES-1];
    wire [L-1:0] lane_index [0:LANES-1];
    genvar lane_number;
    generate
        for (lane_number = 0; lane_number < LANES;
             lane_number = lane_number + 1) begin : lane_outputs
            assign lane_value[lane_number] = lane_score_q[lane_number];
            assign lane_index[lane_number] =
                lane_start_selector(lane_number) ^
                {{(L-OFFSET_W){1'b0}},gray_offset};
        end
    endgenerate

    wire signed [ACC_W-1:0] cycle_max_value;
    wire [L-1:0] cycle_max_index;
    fht_max_tree #(
        .COUNT(LANES), .SCORE_W(ACC_W), .INDEX_W(L)
    ) max_u (
        .value_i(lane_value), .index_i(lane_index),
        .value_o(cycle_max_value), .index_o(cycle_max_index)
    );

    wire cycle_max_is_better =
        ($signed(cycle_max_value) > $signed(best_q)) ||
        (($signed(cycle_max_value) == $signed(best_q)) &&
         (cycle_max_index < best_index_q));

    assign start_ready_o = state_q == IDLE;
    assign add_ready_o = state_q == LOAD;
    assign busy_o = state_q != IDLE;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state_q <= IDLE;
            flag_count_q <= '0;
            offset_q <= '0;
            selector_o <= '0;
            best_score_o <= '0;
            best_q <= MIN_SCORE;
            best_index_q <= '0;
            overflow_o <= 1'b0;
            done_o <= 1'b0;
            for (lane = 0; lane < LANES; lane = lane + 1) begin
                lane_score_q[lane] <= '0;
            end
        end else begin
            done_o <= 1'b0;
            case (state_q)
                IDLE: if (start_i) begin
                    flag_count_q <= '0;
                    offset_q <= '0;
                    best_q <= MIN_SCORE;
                    best_index_q <= '0;
                    overflow_o <= 1'b0;
                    for (lane = 0; lane < LANES; lane = lane + 1) begin
                        lane_score_q[lane] <= '0;
                    end
                    state_q <= LOAD;
                end

                LOAD: begin
                    if (add_valid_i) begin
                        if (flag_count_q < MAX_FLAGS) begin
                            label_q[flag_count_q] <= label_i;
                            phase_q[flag_count_q] <= base_is_zero_i;
                            for (lane = 0; lane < LANES; lane = lane + 1) begin
                                initial_match = base_is_zero_i ^
                                    ^(label_i & lane_start_selector(lane));
                                lane_score_q[lane] <= lane_score_q[lane] +
                                    (initial_match ? 1 : -1);
                            end
                            flag_count_q <= flag_count_q + 1'b1;
                        end else begin
                            overflow_o <= 1'b1;
                        end
                    end
                    if (finish_i) begin
                        offset_q <= '0;
                        best_q <= MIN_SCORE;
                        best_index_q <= '0;
                        state_q <= SEARCH;
                    end
                end

                SEARCH: begin
                    if (cycle_max_is_better) begin
                        best_q <= cycle_max_value;
                        best_index_q <= cycle_max_index;
                    end
                    if (offset_q == ITEMS_PER_LANE-1) begin
                        selector_o <= cycle_max_is_better ?
                                      cycle_max_index : best_index_q;
                        best_score_o <= cycle_max_is_better ?
                            {{(SCORE_W-ACC_W){cycle_max_value[ACC_W-1]}},
                             cycle_max_value} :
                            {{(SCORE_W-ACC_W){best_q[ACC_W-1]}},best_q};
                        done_o <= 1'b1;
                        state_q <= IDLE;
                    end else begin
                        offset_q <= offset_q + 1'b1;
                        for (lane = 0; lane < LANES; lane = lane + 1) begin
                            lane_score_q[lane] <= lane_score_q[lane] +
                                                  lane_delta[lane];
                        end
                        for (flag = 0; flag < MAX_FLAGS; flag = flag + 1)
                            if (toggle_flag[flag])
                                phase_q[flag] <= ~phase_q[flag];
                    end
                end
                default: state_q <= IDLE;
            endcase
        end
    end

`ifndef SYNTHESIS
    initial begin
        if ((LANES & (LANES-1)) != 0 || SIZE % LANES != 0 ||
            (ITEMS_PER_LANE & (ITEMS_PER_LANE-1)) != 0 ||
            ITEMS_PER_LANE < 2)
            $error("sparse Gray search requires power-of-two lanes and blocks");
    end
`endif
endmodule

`default_nettype wire
