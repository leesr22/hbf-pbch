`timescale 1ns/1ps
`default_nettype none

`ifndef ENC_TOP
`define ENC_TOP bch_base_enc_w64
`endif
`ifndef K_BITS
`define K_BITS 4096
`endif
`ifndef R_BITS
`define R_BITS 104
`endif
`ifndef W_BITS
`define W_BITS 64
`endif

module study_bch_encoder_tb;
    localparam integer K=`K_BITS, R=`R_BITS, N=K+R, W=`W_BITS;
    localparam integer COUNT_W=$clog2(W+1);
    localparam integer INFO_BEATS=(K+W-1)/W;
    localparam integer CODE_BEATS=INFO_BEATS+(R+W-1)/W;

    reg clk=0, reset_n=0, start=0;
    always #2 clk=~clk;
    wire start_ready;
    reg [W-1:0] in_bits=0;
    reg [COUNT_W-1:0] in_count=0;
    reg in_valid=0;
    wire in_ready;
    wire [W-1:0] out_bits;
    wire [COUNT_W-1:0] out_count;
    wire out_valid, out_last, done, busy;
    reg out_ready=1;
    reg [W-1:0] message_mem[0:INFO_BEATS-1];
    reg [W-1:0] codeword_mem[0:CODE_BEATS-1];
    string vector_dir;
    integer input_beat=0, output_beat=0, failures=0;

    `ENC_TOP dut(
        .clk(clk),.reset_n(reset_n),.start_i(start),.start_ready_o(start_ready),
        .in_bits_i(in_bits),.in_count_i(in_count),.in_valid_i(in_valid),
        .in_ready_o(in_ready),.out_bits_o(out_bits),.out_count_o(out_count),
        .out_valid_o(out_valid),.out_ready_i(out_ready),.out_last_o(out_last),
        .done_o(done),.busy_o(busy));

    function automatic integer expected_count(input integer beat);
        integer parity_beat;
        begin
            if(beat<INFO_BEATS)
                expected_count=(beat==INFO_BEATS-1)?K-W*(INFO_BEATS-1):W;
            else begin
                parity_beat=beat-INFO_BEATS;
                expected_count=(parity_beat==(R+W-1)/W-1)?
                               R-W*parity_beat:W;
            end
        end
    endfunction

    always @(posedge clk) begin
        if(reset_n && out_valid && out_ready) begin
            if(out_bits!==codeword_mem[output_beat] ||
               out_count!==expected_count(output_beat)) begin
                $display("ERROR beat=%0d expected=%h/%0d got=%h/%0d",
                         output_beat,codeword_mem[output_beat],
                         expected_count(output_beat),out_bits,out_count);
                failures=failures+1;
            end
            output_beat=output_beat+1;
        end
    end

    initial begin
        if(!$value$plusargs("VEC_DIR=%s",vector_dir)) $fatal(1,"missing VEC_DIR");
        $readmemh({vector_dir,"/message.mem"},message_mem);
        $readmemh({vector_dir,"/codeword.mem"},codeword_mem);
        repeat(4) @(posedge clk); reset_n=1;
        wait(start_ready); @(negedge clk); start=1;
        @(negedge clk); start=0;
        while(input_beat<INFO_BEATS) begin
            in_bits=message_mem[input_beat];
            in_count=expected_count(input_beat);
            in_valid=1;
            @(posedge clk);
            if(in_ready) input_beat=input_beat+1;
            @(negedge clk);
        end
        in_valid=0;
        wait(done);
        if(output_beat!=CODE_BEATS) failures=failures+1;
        if(failures) $fatal(1,"encoder failures=%0d",failures);
        $display("PASS BCH encoder K=%0d R=%0d W=%0d beats=%0d",
                 K,R,W,CODE_BEATS);
        $finish;
    end

    initial begin #1000000; $fatal(1,"encoder timeout"); end
endmodule

`default_nettype wire
