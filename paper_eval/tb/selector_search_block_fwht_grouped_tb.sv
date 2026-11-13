`timescale 1ns/1ps
`default_nettype none

`ifndef FWHT_HIGH_L
`define FWHT_HIGH_L 7
`endif
`ifndef FWHT_PIPE_GROUP
`define FWHT_PIPE_GROUP 2
`endif

module selector_search_block_fwht_grouped_tb;
    localparam integer CASES = 96;
    localparam integer MAX_FLAGS = 32;
    localparam integer SCORE_W = $clog2(4278 + 1) + 1;

    reg clk = 1'b0;
    reg reset_n = 1'b0;
    reg start = 1'b0;
    reg [12:0] label = '0;
    reg base_is_zero = 1'b0;
    reg add_valid = 1'b0;
    reg finish = 1'b0;
    wire start_ready;
    wire add_ready;
    wire [12:0] selector;
    wire signed [SCORE_W-1:0] best_score;
    wire overflow;
    wire done;
    wire busy;

    reg [5:0] count_mem [0:CASES-1];
    reg [12:0] selector_mem [0:CASES-1];
    reg signed [6:0] score_mem [0:CASES-1];
    reg [13*MAX_FLAGS-1:0] labels_mem [0:CASES-1];
    reg [MAX_FLAGS-1:0] base_mem [0:CASES-1];
    reg [1023:0] vector_dir;
    integer case_index;
    integer flag_index;

    always #2 clk = ~clk;

    selector_search_block_fwht_grouped #(
        .L(13), .N(4278), .MAX_FLAGS(MAX_FLAGS),
        .HIGH_L(`FWHT_HIGH_L), .PIPE_GROUP(`FWHT_PIPE_GROUP)
    ) dut (
        .clk(clk), .reset_n(reset_n), .start_i(start),
        .start_ready_o(start_ready), .label_i(label),
        .base_is_zero_i(base_is_zero), .add_valid_i(add_valid),
        .add_ready_o(add_ready), .finish_i(finish),
        .selector_o(selector), .best_score_o(best_score),
        .overflow_o(overflow), .done_o(done), .busy_o(busy)
    );

    task load_files;
        begin
            if (!$value$plusargs("VEC_DIR=%s", vector_dir))
                $fatal(1, "VEC_DIR is required");
            $readmemh({vector_dir,"/counts.hex"}, count_mem);
            $readmemh({vector_dir,"/selectors.hex"}, selector_mem);
            $readmemh({vector_dir,"/scores.hex"}, score_mem);
            $readmemh({vector_dir,"/labels.hex"}, labels_mem);
            $readmemh({vector_dir,"/base_zero.hex"}, base_mem);
        end
    endtask

    initial begin
        load_files();
        repeat (4) @(posedge clk);
        reset_n <= 1'b1;

        for (case_index = 0; case_index < CASES;
             case_index = case_index + 1) begin
            wait (start_ready);
            @(posedge clk); start <= 1'b1;
            @(posedge clk); start <= 1'b0;
            wait (add_ready);

            for (flag_index = 0; flag_index < count_mem[case_index];
                 flag_index = flag_index + 1) begin
                @(posedge clk);
                label <= labels_mem[case_index][13*flag_index +: 13];
                base_is_zero <= base_mem[case_index][flag_index];
                add_valid <= 1'b1;
            end
            @(posedge clk); add_valid <= 1'b0; finish <= 1'b1;
            @(posedge clk); finish <= 1'b0;
            wait (done);

            if (overflow !== 1'b0 ||
                selector !== selector_mem[case_index] ||
                $signed(best_score) !== $signed(score_mem[case_index])) begin
                $fatal(1,
                    "case=%0d count=%0d got selector=%0h score=%0d overflow=%0b expected selector=%0h score=%0d",
                    case_index, count_mem[case_index], selector,
                    $signed(best_score), overflow, selector_mem[case_index],
                    $signed(score_mem[case_index]));
            end
        end

        $display("PASS grouped exact FWHT regression cases=%0d high_l=%0d group=%0d",
                 CASES, `FWHT_HIGH_L, `FWHT_PIPE_GROUP);
        $finish;
    end
endmodule

`default_nettype wire
