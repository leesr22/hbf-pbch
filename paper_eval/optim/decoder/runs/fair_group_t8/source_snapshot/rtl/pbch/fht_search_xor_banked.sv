`default_nettype none

// Exact FWHT selector search with conflict-free XOR banking.
//
// Logical index x={row,low} is stored in
//   bank = low XOR fold(row)
// where every row bit is XORed into one bank bit.  Toggling any logical
// index bit therefore toggles a physical bank bit.  The two operands of every
// radix-2 butterfly always reside in different banks, including stages whose
// butterfly bit belongs to the row.  This removes the second asynchronous
// read port required by the original fixed-bank implementation.
//
// With B butterflies there are 2B banks and SIZE/(2B) cycles per stage.
// The numerical operation is still the paper's exact in-place FWHT.
module fht_search_xor_banked #(
    parameter integer L = 13,
    parameter integer N = 4278,
    parameter integer BUTTERFLIES = 64,
    parameter integer SIZE = (1 << L),
    parameter integer BANKS = 2 * BUTTERFLIES,
    parameter integer BANK_W = $clog2(BANKS),
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

    reg [ROW_W-1:0] bank_addr [0:BANKS-1];
    reg bank_write [0:BANKS-1];
    reg signed [SCORE_W-1:0] bank_write_data [0:BANKS-1];
    wire signed [SCORE_W-1:0] bank_data [0:BANKS-1];
    reg signed [SCORE_W-1:0] fht_data [0:BANKS-1];

    function automatic [BANK_W-1:0] fold_row;
        input [ROW_W-1:0] row;
        integer bit_number;
        begin
            fold_row = '0;
            for (bit_number = 0; bit_number < ROW_W;
                 bit_number = bit_number + 1)
                fold_row[bit_number % BANK_W] =
                    fold_row[bit_number % BANK_W] ^ row[bit_number];
        end
    endfunction

    wire [ROW_W-1:0] label_row = label_i[L-1:BANK_W];
    wire [BANK_W-1:0] label_bank =
        label_i[BANK_W-1:0] ^ fold_row(label_row);
    wire signed [SCORE_W-1:0] load_delta =
        base_is_zero_i ? {{(SCORE_W-1){1'b0}},1'b1} : {SCORE_W{1'b1}};

    integer bank;
    integer partner_bank;
    integer row_stage;
    integer bank_stage;
    integer pair_number;
    integer lower_row;
    integer upper_row;
    integer phase;
    reg [BANK_W-1:0] row_fold;
    reg logical_right;

    assign start_ready_o = state_q == IDLE;
    assign add_ready_o = state_q == LOAD;
    assign busy_o = state_q != IDLE;

    // One conflict-free address and one optional write per bank.
    always @* begin
        for (bank = 0; bank < BANKS; bank = bank + 1) begin
            bank_addr[bank] = '0;
            bank_write[bank] = 1'b0;
            bank_write_data[bank] = '0;
            fht_data[bank] = '0;
        end

        case (state_q)
            CLEAR: begin
                for (bank = 0; bank < BANKS; bank = bank + 1) begin
                    bank_addr[bank] = row_q;
                    bank_write[bank] = 1'b1;
                end
            end

            LOAD: begin
                for (bank = 0; bank < BANKS; bank = bank + 1) begin
                    bank_addr[bank] = label_row;
                    if (add_valid_i && label_bank == bank[BANK_W-1:0]) begin
                        bank_write[bank] = 1'b1;
                        bank_write_data[bank] = bank_data[bank] + load_delta;
                    end
                end
            end

            FHT: begin
                if (stage_q < BANK_W) begin
                    // The butterfly bit is in the logical low part.  All
                    // banks access one row; fold(row) tells whether the value
                    // stored in this bank is the left or right operand.
                    row_fold = fold_row(row_q);
                    for (bank = 0; bank < BANKS; bank = bank + 1)
                        bank_addr[bank] = row_q;
                    for (bank = 0; bank < BANKS; bank = bank + 1) begin
                        partner_bank = bank ^ (1 << stage_q);
                        logical_right = bank[stage_q] ^ row_fold[stage_q];
                        fht_data[bank] = logical_right ?
                            bank_data[partner_bank] - bank_data[bank] :
                            bank_data[bank] + bank_data[partner_bank];
                    end
                end else begin
                    // A row-bit butterfly connects two rows and two banks.
                    // Two phases cover every logical low value once while
                    // reading each physical bank exactly once per cycle.
                    row_stage = stage_q - BANK_W;
                    // row_stage is at most six for L=13.  Avoid a generic
                    // synthesized divider for the rare wrap at B=32.
                    bank_stage = (row_stage >= BANK_W) ?
                                 (row_stage - BANK_W) : row_stage;
                    phase = row_q[0];
                    pair_number = row_q >> 1;
                    lower_row = ((pair_number >> row_stage) << (row_stage+1)) |
                                (pair_number & ((1 << row_stage) - 1));
                    upper_row = lower_row | (1 << row_stage);
                    for (bank = 0; bank < BANKS; bank = bank + 1) begin
                        bank_addr[bank] = (bank[bank_stage] == phase) ?
                                          lower_row[ROW_W-1:0] :
                                          upper_row[ROW_W-1:0];
                    end
                    for (bank = 0; bank < BANKS; bank = bank + 1) begin
                        partner_bank = bank ^ (1 << bank_stage);
                        fht_data[bank] = (bank[bank_stage] == phase) ?
                            bank_data[bank] + bank_data[partner_bank] :
                            bank_data[partner_bank] - bank_data[bank];
                    end
                end
                for (bank = 0; bank < BANKS; bank = bank + 1) begin
                    bank_write[bank] = 1'b1;
                    bank_write_data[bank] = fht_data[bank];
                end
            end

            FIND_MAX: begin
                for (bank = 0; bank < BANKS; bank = bank + 1)
                    bank_addr[bank] = row_q;
            end
            default: begin end
        endcase
    end

    genvar bank_number;
    generate
        for (bank_number = 0; bank_number < BANKS;
             bank_number = bank_number + 1) begin : score_bank
            fht_score_bank_1rw #(
                .DEPTH(DEPTH), .SCORE_W(SCORE_W), .ADDR_W(ROW_W)
            ) bank_u (
                .clk(clk), .addr_i(bank_addr[bank_number]),
                .data_o(bank_data[bank_number]),
                .write_i(bank_write[bank_number]),
                .write_data_i(bank_write_data[bank_number])
            );
        end
    endgenerate

    wire signed [SCORE_W-1:0] max_value_input [0:BANKS-1];
    wire [L-1:0] max_index_input [0:BANKS-1];
    wire signed [SCORE_W-1:0] row_max_value;
    wire [L-1:0] row_max_index;
    genvar max_bank;
    generate
        for (max_bank = 0; max_bank < BANKS; max_bank = max_bank + 1) begin
            assign max_value_input[max_bank] = bank_data[max_bank];
            assign max_index_input[max_bank] =
                {row_q, max_bank[BANK_W-1:0] ^ fold_row(row_q)};
        end
    endgenerate
    fht_max_tree #(
        .COUNT(BANKS), .SCORE_W(SCORE_W), .INDEX_W(L)
    ) max_u (
        .value_i(max_value_input), .index_i(max_index_input),
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
                    if (row_q == DEPTH-1) begin
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
        if (BANKS > SIZE || (BANKS & (BANKS-1)) != 0 ||
            (DEPTH & (DEPTH-1)) != 0 || BANK_W > L)
            $error("XOR-banked FWHT requires power-of-two banks/depth");
    end
`endif
endmodule

`default_nettype wire
