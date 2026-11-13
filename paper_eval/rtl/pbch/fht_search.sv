`default_nettype none

// Exact PBCH2 selector search with a fixed 64-bank Walsh-Hadamard schedule.
//
// H[label] receives +1 when selector d should produce zero at a flagged cell,
// and -1 otherwise.  A 13-stage FHT converts H into all 8192 exact selector
// scores.  The maximum score therefore gives the exhaustive-search result.
//
// The low six index bits select an explicit bank:
//   stages 0..5  : 32 fixed inter-bank butterflies per cycle
//   stages 6..12 : 64 fixed intra-bank butterflies per cycle
// Only the 128-entry row address is dynamic.  This avoids the enormous
// runtime-selected multiport muxes produced by the original description.
module fht_search #(
    parameter integer L = 13,
    parameter integer N = 4278,
    // Source compatibility with old wrappers; the fixed schedule supersedes P.
    parameter integer PARALLEL = 8,
    parameter integer SIZE = (1 << L),
    parameter integer BANKS = 64,
    parameter integer BANK_W = 6,
    parameter integer DEPTH = SIZE / BANKS,
    parameter integer ROW_W = $clog2(DEPTH),
    parameter integer SCORE_W = $clog2(N + 1) + 1,
    parameter integer STAGE_W = $clog2(L + 1)
) (
    input  wire                       clk,
    input  wire                       reset_n,
    input  wire                       start_i,
    output wire                       start_ready_o,
    input  wire [L-1:0]               label_i,
    input  wire                       base_is_zero_i,
    input  wire                       add_valid_i,
    output wire                       add_ready_o,
    input  wire                       finish_i,
    output reg  [L-1:0]               selector_o,
    output reg  signed [SCORE_W-1:0]  best_score_o,
    output reg                        done_o,
    output wire                       busy_o
);
    localparam [2:0] IDLE = 3'd0, CLEAR = 3'd1, LOAD = 3'd2,
                     FHT = 3'd3, FIND_MAX = 3'd4;
    localparam signed [SCORE_W-1:0] MIN_SCORE =
        {1'b1,{(SCORE_W-1){1'b0}}};

    reg [2:0] state_q;
    reg [ROW_W-1:0] row_q;
    reg [STAGE_W-1:0] stage_q;
    reg signed [SCORE_W-1:0] best_q;
    reg [L-1:0] best_index_q;

    reg [ROW_W-1:0] read_a [0:BANKS-1];
    reg [ROW_W-1:0] read_b [0:BANKS-1];
    reg write_a [0:BANKS-1];
    reg write_b [0:BANKS-1];
    reg signed [SCORE_W-1:0] write_data_a [0:BANKS-1];
    reg signed [SCORE_W-1:0] write_data_b [0:BANKS-1];
    wire signed [SCORE_W-1:0] bank_data_a [0:BANKS-1];
    wire signed [SCORE_W-1:0] bank_data_b [0:BANKS-1];
    wire signed [SCORE_W-1:0] low_stage_data [0:BANKS-1];

    wire [ROW_W-1:0] label_row = label_i[L-1:BANK_W];
    wire [BANK_W-1:0] label_bank = label_i[BANK_W-1:0];
    wire signed [SCORE_W-1:0] load_delta =
        base_is_zero_i ? {{(SCORE_W-1){1'b0}},1'b1} : {SCORE_W{1'b1}};

    integer bank;
    integer row_stage;
    integer span;
    integer group_number;
    integer offset;
    integer left_row;
    integer right_row;

    assign start_ready_o = state_q == IDLE;
    assign add_ready_o = state_q == LOAD;
    assign busy_o = state_q != IDLE;

    // Each output bank has only six fixed partners across stages 0..5.
    genvar low_bank;
    generate
        for (low_bank = 0; low_bank < BANKS; low_bank = low_bank + 1) begin : low_stage
            reg signed [SCORE_W-1:0] result;
            always @* begin
                result = '0;
                case (stage_q)
                    0: result = (low_bank & 1) ?
                        bank_data_a[low_bank ^ 1] - bank_data_a[low_bank] :
                        bank_data_a[low_bank] + bank_data_a[low_bank ^ 1];
                    1: result = (low_bank & 2) ?
                        bank_data_a[low_bank ^ 2] - bank_data_a[low_bank] :
                        bank_data_a[low_bank] + bank_data_a[low_bank ^ 2];
                    2: result = (low_bank & 4) ?
                        bank_data_a[low_bank ^ 4] - bank_data_a[low_bank] :
                        bank_data_a[low_bank] + bank_data_a[low_bank ^ 4];
                    3: result = (low_bank & 8) ?
                        bank_data_a[low_bank ^ 8] - bank_data_a[low_bank] :
                        bank_data_a[low_bank] + bank_data_a[low_bank ^ 8];
                    4: result = (low_bank & 16) ?
                        bank_data_a[low_bank ^ 16] - bank_data_a[low_bank] :
                        bank_data_a[low_bank] + bank_data_a[low_bank ^ 16];
                    5: result = (low_bank & 32) ?
                        bank_data_a[low_bank ^ 32] - bank_data_a[low_bank] :
                        bank_data_a[low_bank] + bank_data_a[low_bank ^ 32];
                    default: result = '0;
                endcase
            end
            assign low_stage_data[low_bank] = result;
        end
    endgenerate

    // Address and write schedule shared by the 64 explicit banks.
    always @* begin
        for (bank = 0; bank < BANKS; bank = bank + 1) begin
            read_a[bank] = '0;
            read_b[bank] = '0;
            write_a[bank] = 1'b0;
            write_b[bank] = 1'b0;
            write_data_a[bank] = '0;
            write_data_b[bank] = '0;
        end

        case (state_q)
            CLEAR: begin
                for (bank = 0; bank < BANKS; bank = bank + 1) begin
                    read_a[bank] = row_q;
                    write_a[bank] = 1'b1;
                end
            end

            LOAD: begin
                for (bank = 0; bank < BANKS; bank = bank + 1) begin
                    read_a[bank] = label_row;
                    if (add_valid_i && label_bank == bank[BANK_W-1:0]) begin
                        write_a[bank] = 1'b1;
                        write_data_a[bank] = bank_data_a[bank] + load_delta;
                    end
                end
            end

            FHT: begin
                if (stage_q < BANK_W) begin
                    for (bank = 0; bank < BANKS; bank = bank + 1) begin
                        read_a[bank] = row_q;
                        write_a[bank] = 1'b1;
                        write_data_a[bank] = low_stage_data[bank];
                    end
                end else begin
                    row_stage = stage_q - BANK_W;
                    span = 1 << row_stage;
                    group_number = row_q >> row_stage;
                    offset = row_q & (span - 1);
                    left_row = (group_number << (row_stage + 1)) | offset;
                    right_row = left_row | span;
                    for (bank = 0; bank < BANKS; bank = bank + 1) begin
                        read_a[bank] = left_row[ROW_W-1:0];
                        read_b[bank] = right_row[ROW_W-1:0];
                        write_a[bank] = 1'b1;
                        write_b[bank] = 1'b1;
                        write_data_a[bank] = bank_data_a[bank] + bank_data_b[bank];
                        write_data_b[bank] = bank_data_a[bank] - bank_data_b[bank];
                    end
                end
            end

            FIND_MAX: begin
                for (bank = 0; bank < BANKS; bank = bank + 1)
                    read_a[bank] = row_q;
            end
            default: begin end
        endcase
    end

    genvar bank_number;
    generate
        for (bank_number = 0; bank_number < BANKS;
             bank_number = bank_number + 1) begin : score_bank
            fht_score_bank #(
                .DEPTH(DEPTH), .SCORE_W(SCORE_W), .ADDR_W(ROW_W)
            ) bank_u (
                .clk(clk), .read_a_i(read_a[bank_number]),
                .read_b_i(read_b[bank_number]),
                .data_a_o(bank_data_a[bank_number]),
                .data_b_o(bank_data_b[bank_number]),
                .write_a_i(write_a[bank_number]),
                .write_b_i(write_b[bank_number]),
                .write_data_a_i(write_data_a[bank_number]),
                .write_data_b_i(write_data_b[bank_number])
            );
        end
    endgenerate

    wire [L-1:0] max_input_index [0:BANKS-1];
    wire signed [SCORE_W-1:0] row_max_value;
    wire [L-1:0] row_max_index;
    genvar max_bank;
    generate
        for (max_bank = 0; max_bank < BANKS; max_bank = max_bank + 1)
            assign max_input_index[max_bank] = {row_q,max_bank[BANK_W-1:0]};
    endgenerate
    fht_max_tree #(
        .COUNT(BANKS), .SCORE_W(SCORE_W), .INDEX_W(L)
    ) max_u (
        .value_i(bank_data_a), .index_i(max_input_index),
        .value_o(row_max_value), .index_o(row_max_index)
    );

    wire row_max_is_better =
        ($signed(row_max_value) > $signed(best_q)) ||
        (($signed(row_max_value) == $signed(best_q)) &&
         (row_max_index < best_index_q));

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state_q <= IDLE;
            row_q <= '0;
            stage_q <= '0;
            best_q <= MIN_SCORE;
            best_index_q <= '0;
            selector_o <= '0;
            best_score_o <= '0;
            done_o <= 1'b0;
        end else begin
            done_o <= 1'b0;
            case (state_q)
                IDLE: if (start_i) begin
                    row_q <= '0;
                    state_q <= CLEAR;
                end

                CLEAR: begin
                    if (row_q == DEPTH-1) begin
                        row_q <= '0;
                        state_q <= LOAD;
                    end else row_q <= row_q + 1'b1;
                end

                LOAD: if (finish_i) begin
                    row_q <= '0;
                    stage_q <= '0;
                    state_q <= FHT;
                end

                FHT: begin
                    if ((stage_q < BANK_W && row_q == DEPTH-1) ||
                        (stage_q >= BANK_W && row_q == DEPTH/2-1)) begin
                        row_q <= '0;
                        if (stage_q == L-1) begin
                            best_q <= MIN_SCORE;
                            best_index_q <= '0;
                            state_q <= FIND_MAX;
                        end else stage_q <= stage_q + 1'b1;
                    end else row_q <= row_q + 1'b1;
                end

                FIND_MAX: begin
                    if (row_max_is_better) begin
                        best_q <= row_max_value;
                        best_index_q <= row_max_index;
                    end
                    if (row_q == DEPTH-1) begin
                        selector_o <= row_max_is_better ?
                                      row_max_index : best_index_q;
                        best_score_o <= row_max_is_better ?
                                        row_max_value : best_q;
                        done_o <= 1'b1;
                        state_q <= IDLE;
                    end else row_q <= row_q + 1'b1;
                end
                default: state_q <= IDLE;
            endcase
        end
    end

`ifndef SYNTHESIS
    initial begin
        if (L < BANK_W || SIZE % BANKS != 0 ||
            (DEPTH & (DEPTH-1)) != 0)
            $error("fixed-bank FHT requires L>=6 and power-of-two DEPTH");
    end
`endif
endmodule

`default_nettype wire
