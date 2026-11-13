`timescale 1ns/1ps
`default_nettype none

`ifndef DEC_TOP
`define DEC_TOP bch_base_dec_replay_w64
`endif
`ifndef K_BITS
`define K_BITS 4096
`endif
`ifndef R_BITS
`define R_BITS 104
`endif
`ifndef T_BITS
`define T_BITS 8
`endif
`ifndef L_BITS
`define L_BITS 0
`endif
`ifndef W_BITS
`define W_BITS 64
`endif

module study_decoder_tb;
    localparam integer K = `K_BITS;
    localparam integer R = `R_BITS;
    localparam integer T = `T_BITS;
    localparam integer L = `L_BITS;
    localparam integer N = K + L + R;
    localparam integer W = `W_BITS;
    localparam integer COUNT_W = $clog2(W + 1);
    localparam integer INFO_BEATS = (K + W - 1) / W;
    localparam integer CW_BEATS = (L == 0 ? 0 : 1) + INFO_BEATS + (R + W - 1) / W;

    reg clk = 1'b0;
    reg reset_n = 1'b0;
    reg start = 1'b0;
    wire start_ready;
    reg [W-1:0] code_bits = '0;
    reg [COUNT_W-1:0] code_count = '0;
    reg code_valid = 1'b0;
    wire code_ready;
    wire replay_req;
    reg [W-1:0] replay_bits = '0;
    reg [COUNT_W-1:0] replay_count = '0;
    reg replay_valid = 1'b0;
    wire replay_ready;
    wire [W-1:0] info_bits;
    wire [COUNT_W-1:0] info_count;
    wire info_valid;
    reg info_ready = 1'b1;
    wire done;
    wire success;
    wire [$clog2(T+1)-1:0] error_count;
    wire busy;
`ifdef PBCH_MODE
    wire [L-1:0] selector;
`endif

    reg [W-1:0] message_mem [0:INFO_BEATS-1];
    reg [W-1:0] received_mem [0:CW_BEATS-1];
    string vector_dir;
    integer failures = 0;
    integer output_beat = 0;
    integer cycles = 0;
    integer start_cycle;

    always #2 clk = ~clk;
    always @(posedge clk) cycles = cycles + 1;

`ifdef BUFFERED_MODE
  `ifdef PBCH_MODE
    `DEC_TOP dut (
        .clk(clk),.reset_n(reset_n),.start_i(start),.start_ready_o(start_ready),
        .code_bits_i(code_bits),.code_count_i(code_count),
        .code_valid_i(code_valid),.code_ready_o(code_ready),
        .info_bits_o(info_bits),.info_count_o(info_count),
        .info_valid_o(info_valid),.info_ready_i(info_ready),.selector_o(selector),
        .done_o(done),.success_o(success),.error_count_o(error_count),.busy_o(busy));
  `else
    `DEC_TOP dut (
        .clk(clk),.reset_n(reset_n),.start_i(start),.start_ready_o(start_ready),
        .code_bits_i(code_bits),.code_count_i(code_count),
        .code_valid_i(code_valid),.code_ready_o(code_ready),
        .info_bits_o(info_bits),.info_count_o(info_count),
        .info_valid_o(info_valid),.info_ready_i(info_ready),
        .done_o(done),.success_o(success),.error_count_o(error_count),.busy_o(busy));
  `endif
`else
  `ifdef PBCH_MODE
    `DEC_TOP dut (
        .clk(clk),.reset_n(reset_n),.start_i(start),.start_ready_o(start_ready),
        .code_bits_i(code_bits),.code_count_i(code_count),
        .code_valid_i(code_valid),.code_ready_o(code_ready),
        .replay_req_o(replay_req),.replay_bits_i(replay_bits),
        .replay_count_i(replay_count),.replay_valid_i(replay_valid),
        .replay_ready_o(replay_ready),.info_bits_o(info_bits),
        .info_count_o(info_count),.info_valid_o(info_valid),
        .info_ready_i(info_ready),.selector_o(selector),.done_o(done),
        .success_o(success),.error_count_o(error_count),.busy_o(busy));
  `else
    `DEC_TOP dut (
        .clk(clk),.reset_n(reset_n),.start_i(start),.start_ready_o(start_ready),
        .code_bits_i(code_bits),.code_count_i(code_count),
        .code_valid_i(code_valid),.code_ready_o(code_ready),
        .replay_req_o(replay_req),.replay_bits_i(replay_bits),
        .replay_count_i(replay_count),.replay_valid_i(replay_valid),
        .replay_ready_o(replay_ready),.info_bits_o(info_bits),
        .info_count_o(info_count),.info_valid_o(info_valid),
        .info_ready_i(info_ready),.done_o(done),.success_o(success),
        .error_count_o(error_count),.busy_o(busy));
  `endif
`endif

    function automatic integer count_at(input integer beat);
        integer adjusted;
        integer parity_beat;
        begin
            if (L != 0 && beat == 0) begin
                count_at = L;
            end else begin
                adjusted = beat - (L == 0 ? 0 : 1);
                if (adjusted < INFO_BEATS)
                    count_at = (adjusted == INFO_BEATS-1) ?
                               K-W*(INFO_BEATS-1) : W;
                else begin
                    parity_beat = adjusted - INFO_BEATS;
                    count_at = (parity_beat == (R+W-1)/W-1) ?
                               R-W*parity_beat : W;
                end
            end
        end
    endfunction

    task drive_word(input bit is_replay);
        integer beat;
        begin
            beat = 0;
            while (beat < CW_BEATS) begin
                @(negedge clk);
                if (!is_replay) begin
                    code_bits = received_mem[beat];
                    code_count = count_at(beat);
                    code_valid = 1'b1;
                    if (code_ready) beat = beat + 1;
                end else begin
                    replay_bits = received_mem[beat];
                    replay_count = count_at(beat);
                    replay_valid = 1'b1;
                    if (replay_ready) beat = beat + 1;
                end
            end
            @(negedge clk);
            if (is_replay) replay_valid = 1'b0;
            else code_valid = 1'b0;
        end
    endtask

    always @(posedge clk) begin
        if (reset_n && info_valid && info_ready) begin
            if (output_beat >= INFO_BEATS || info_bits !== message_mem[output_beat]) begin
                $display("ERROR info beat=%0d expected=%h got=%h",
                         output_beat, message_mem[output_beat], info_bits);
                failures = failures + 1;
            end
            output_beat = output_beat + 1;
        end
    end

    initial begin
        if (!$value$plusargs("VEC_DIR=%s", vector_dir))
            $fatal(1, "missing +VEC_DIR");
        $readmemh({vector_dir,"/message.mem"}, message_mem);
        $readmemh({vector_dir,"/received.mem"}, received_mem);
        repeat (4) @(posedge clk);
        reset_n = 1'b1;
        wait (start_ready);
        @(negedge clk); start = 1'b1;
        @(negedge clk); start = 1'b0;
        start_cycle = cycles;
        drive_word(1'b0);
`ifndef BUFFERED_MODE
        wait (replay_req);
        drive_word(1'b1);
`endif
        wait (done);
        if (!success || error_count != T) begin
            $display("ERROR status success=%0b errors=%0d expected=%0d",
                     success, error_count, T);
            failures = failures + 1;
        end
        if (output_beat != INFO_BEATS) begin
            $display("ERROR output beats=%0d expected=%0d", output_beat, INFO_BEATS);
            failures = failures + 1;
        end
        if (failures)
            $fatal(1, "decoder failures=%0d", failures);
        $display("PASS decoder K=%0d L=%0d T=%0d W=%0d cycles=%0d",
                 K,L,T,W,cycles-start_cycle);
        $finish;
    end

    initial begin
        #4000000;
        $fatal(1, "decoder timeout");
    end
endmodule

`default_nettype wire
