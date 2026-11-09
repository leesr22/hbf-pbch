`timescale 1ns/1ps
`default_nettype none

module pbch_encoder_tb;
`ifndef PBCH_TOP
`define PBCH_TOP pbch_fwht_encoder_w128
`endif
`ifndef PBCH_W
`define PBCH_W 128
`endif
    localparam integer K = 4096;
    localparam integer N = 4278;
    localparam integer W = `PBCH_W;
    localparam integer VECTORS = 8;
    localparam integer COUNT_W = $clog2(W + 1);

    reg clk = 1'b0;
    reg reset_n = 1'b0;
    reg start = 1'b0;
    reg [2:0] context_id = '0;
    wire start_ready;
    reg [W-1:0] data_bits = '0;
    reg [COUNT_W-1:0] data_count = '0;
    reg data_valid = 1'b0;
    wire data_ready;
    reg [W-1:0] probe_bits = '0;
    reg [COUNT_W-1:0] probe_count = '0;
    reg probe_valid = 1'b0;
    wire probe_ready;
    wire [2:0] message_context;
    wire [$clog2(K/W+1)-1:0] message_addr;
    reg [W-1:0] external_message_bits;
    wire [W-1:0] out_bits;
    wire [COUNT_W-1:0] out_count;
    wire out_valid;
    reg out_ready = 1'b1;
    wire out_last;
    wire [2:0] result_context;
    wire [12:0] selector;
    wire [$clog2(N+1)-1:0] failures;
    wire flags_truncated;
    wire done;
    wire busy;

    reg [K-1:0] messages [0:VECTORS-1];
    reg [N-1:0] probes [0:VECTORS-1];
    reg [N-1:0] expected_words [0:VECTORS-1];
    reg [15:0] expected_selectors [0:VECTORS-1];
    reg [15:0] expected_failures [0:VECTORS-1];
    reg expected_truncated [0:VECTORS-1];
    reg [15:0] flag_counts [0:VECTORS-1];
    reg [15:0] actual_failures [0:VECTORS-1];
    reg [N-1:0] observed [0:VECTORS-1];
    integer observed_bits [0:VECTORS-1];
    reg observed_done [0:VECTORS-1];
    integer cycle_count;
    integer start_cycle [0:VECTORS-1];
    integer results_seen;
    integer lane;
    integer result_index;
    string vector_dir;
    reg random_backpressure;
    reg [15:0] ready_lfsr = 16'h1ace;

    always #2 clk = ~clk;
    always @(posedge clk) cycle_count <= cycle_count + 1;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            ready_lfsr <= 16'h1ace;
            out_ready <= 1'b1;
        end else begin
            ready_lfsr <= {ready_lfsr[14:0],
                           ready_lfsr[15] ^ ready_lfsr[13] ^
                           ready_lfsr[12] ^ ready_lfsr[10]};
            out_ready <= !random_backpressure ||
                         (ready_lfsr[1:0] != 2'b00);
        end
    end

    always @* begin
        external_message_bits = '0;
        if (message_context < VECTORS) begin
            for (lane = 0; lane < W; lane = lane + 1)
                if (message_addr*W + lane < K)
                    external_message_bits[W-1-lane] =
                        messages[message_context][K-1-message_addr*W-lane];
        end
    end

    `PBCH_TOP dut (
        .clk(clk),.reset_n(reset_n),.start_i(start),.context_i(context_id),
        .start_ready_o(start_ready),
        .data_bits_i(data_bits),.data_count_i(data_count),
        .data_valid_i(data_valid),.data_ready_o(data_ready),
        .probe_bits_i(probe_bits),.probe_count_i(probe_count),
        .probe_valid_i(probe_valid),.probe_ready_o(probe_ready),
        .message_context_o(message_context),.message_addr_o(message_addr),
        .external_message_bits_i(external_message_bits),
        .out_bits_o(out_bits),.out_count_o(out_count),.out_valid_o(out_valid),
        .out_ready_i(out_ready),.out_last_o(out_last),
        .result_context_o(result_context),.selector_o(selector),
        .selected_failures_o(failures),.flags_truncated_o(flags_truncated),
        .done_o(done),.busy_o(busy)
    );

    task send_data(input integer index);
        integer seen;
        integer local_lane;
        begin
            seen = 0;
            while (seen < K) begin
                data_bits = '0;
                data_count = W;
                for (local_lane = 0; local_lane < W; local_lane = local_lane + 1)
                    data_bits[W-1-local_lane] =
                        messages[index][K-1-seen-local_lane];
                data_valid = 1'b1;
                do @(posedge clk); while (!data_ready);
                seen = seen + W;
                @(negedge clk);
            end
            data_valid = 1'b0;
        end
    endtask

    task send_probe(input integer index);
        integer seen;
        integer local_lane;
        integer count_now;
        begin
            seen = 0;
            while (seen < N) begin
                probe_bits = '0;
                count_now = ((N-seen) > W) ? W : (N-seen);
                probe_count = count_now;
                for (local_lane = 0; local_lane < W; local_lane = local_lane + 1)
                    if (local_lane < count_now)
                        probe_bits[W-1-local_lane] =
                            probes[index][N-1-seen-local_lane];
                probe_valid = 1'b1;
                do @(posedge clk); while (!probe_ready);
                seen = seen + count_now;
                @(negedge clk);
            end
            probe_valid = 1'b0;
        end
    endtask

    task launch(input integer index);
        begin
            wait (start_ready);
            @(negedge clk);
            context_id = index[2:0];
            start = 1'b1;
            start_cycle[index] = cycle_count;
            @(negedge clk);
            start = 1'b0;
            $display("START vector=%0d cycle=%0d", index, start_cycle[index]);
            fork
                send_data(index);
                send_probe(index);
            join
        end
    endtask

    always @(posedge clk) begin
        if (reset_n && out_valid && out_ready) begin
            result_index = result_context;
            if (result_index >= VECTORS)
                $fatal(1,"invalid result context=%0d",result_index);
            for (lane = 0; lane < W; lane = lane + 1)
                if (lane < out_count)
                    observed[result_index][N-1-observed_bits[result_index]-lane] =
                        out_bits[W-1-lane];
            observed_bits[result_index] = observed_bits[result_index] + out_count;
            if (out_last) begin
                if (observed_done[result_index])
                    $fatal(1,"duplicate result context=%0d",result_index);
                observed_done[result_index] = 1'b1;
                results_seen = results_seen + 1;
                if (observed[result_index] !== expected_words[result_index])
                    $fatal(1,"codeword mismatch context=%0d",result_index);
                if (selector !== expected_selectors[result_index][12:0])
                    $fatal(1,"selector mismatch context=%0d got=%0h expected=%0h",
                           result_index,selector,expected_selectors[result_index]);
                if (failures !== expected_failures[result_index])
                    $fatal(1,"failure mismatch context=%0d got=%0d expected=%0d",
                           result_index,failures,expected_failures[result_index]);
                if (flags_truncated !== expected_truncated[result_index])
                    $fatal(1,"truncation mismatch context=%0d got=%0b expected=%0b",
                           result_index,flags_truncated,
                           expected_truncated[result_index]);
                $display("PASS result=%0d flags=%0d selector=%0h selected_failures=%0d actual_failures=%0d truncated=%0b cycle=%0d",
                         result_index,flag_counts[result_index],selector,failures,
                         actual_failures[result_index],flags_truncated,cycle_count);
            end
        end
    end

    integer index;
    initial begin
        if (!$value$plusargs("VEC_DIR=%s", vector_dir))
            vector_dir = "vectors/encoder_max32";
        random_backpressure = $test$plusargs("RANDOM_BP");
        $readmemh({vector_dir,"/message.hex"}, messages);
        $readmemh({vector_dir,"/probe.hex"}, probes);
        $readmemh({vector_dir,"/codeword.hex"}, expected_words);
        $readmemh({vector_dir,"/selector.hex"}, expected_selectors);
        $readmemh({vector_dir,"/selected_failures.hex"}, expected_failures);
        $readmemh({vector_dir,"/actual_failures.hex"}, actual_failures);
        $readmemh({vector_dir,"/truncated.hex"}, expected_truncated);
        $readmemh({vector_dir,"/flag_count.hex"}, flag_counts);
        cycle_count = 0;
        results_seen = 0;
        for (index = 0; index < VECTORS; index = index + 1) begin
            observed[index] = '0;
            observed_bits[index] = 0;
            observed_done[index] = 1'b0;
            start_cycle[index] = 0;
        end

        repeat (4) @(posedge clk);
        reset_n <= 1'b1;
        for (index = 0; index < VECTORS; index = index + 1)
            launch(index);
        wait (results_seen == VECTORS);
        for (index = 1; index < VECTORS; index = index + 1)
            $display("START_GAP %0d->%0d cycles=%0d",index-1,index,
                     start_cycle[index]-start_cycle[index-1]);
        $display("PASS pbch_fwht_encoder MAX_FLAGS=32 vectors=%0d",VECTORS);
        $finish;
    end

    initial begin
        #2000000;
        $fatal(1,"timeout results=%0d busy=%0b",results_seen,busy);
    end
endmodule

`default_nettype wire
