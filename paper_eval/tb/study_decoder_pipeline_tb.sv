`timescale 1ns/1ps
`default_nettype none

// Long streaming check for both replay and decoder-local-buffer variants.
// Five distinct error patterns are repeated to expose periodic pipeline stalls.
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

module study_decoder_pipeline_tb;
    localparam integer K=`K_BITS, R=`R_BITS, T=`T_BITS, L=`L_BITS, W=`W_BITS;
    localparam integer VECTOR_FRAMES=5, FRAMES=25, COUNT_W=$clog2(W+1);
    localparam integer INFO_BEATS=(K+W-1)/W;
    localparam integer CW_BEATS=(L==0?0:1)+INFO_BEATS+(R+W-1)/W;

    reg clk=0, reset_n=0, start=0;
    always #2 clk=~clk;
    wire start_ready;
    reg [W-1:0] code_bits=0, replay_bits=0;
    reg [COUNT_W-1:0] code_count=0, replay_count=0;
    reg code_valid=0, replay_valid=0;
    wire code_ready, replay_req, replay_ready;
    wire [W-1:0] info_bits;
    wire [COUNT_W-1:0] info_count;
    wire info_valid, done, success, busy;
    wire [$clog2(T+1)-1:0] error_count;
`ifdef PBCH_MODE
    wire [L-1:0] selector;
`endif
    reg [W-1:0] message_mem[0:VECTOR_FRAMES*INFO_BEATS-1];
    reg [W-1:0] received_mem[0:VECTOR_FRAMES*CW_BEATS-1];
    reg [$clog2(T+1)-1:0] expected_errors[0:VECTOR_FRAMES-1];
    string vector_dir;
    integer cycle=0, outputs=0, completions=0, failures=0;
    integer start_cycle[0:FRAMES-1];

    always @(posedge clk) cycle=cycle+1;

`ifdef BUFFERED_MODE
  `ifdef PBCH_MODE
    `DEC_TOP dut(.*,.start_i(start),.start_ready_o(start_ready),
        .code_bits_i(code_bits),.code_count_i(code_count),.code_valid_i(code_valid),
        .code_ready_o(code_ready),.info_bits_o(info_bits),.info_count_o(info_count),
        .info_valid_o(info_valid),.info_ready_i(1'b1),.selector_o(selector),
        .done_o(done),.success_o(success),.error_count_o(error_count),.busy_o(busy));
  `else
    `DEC_TOP dut(.*,.start_i(start),.start_ready_o(start_ready),
        .code_bits_i(code_bits),.code_count_i(code_count),.code_valid_i(code_valid),
        .code_ready_o(code_ready),.info_bits_o(info_bits),.info_count_o(info_count),
        .info_valid_o(info_valid),.info_ready_i(1'b1),
        .done_o(done),.success_o(success),.error_count_o(error_count),.busy_o(busy));
  `endif
`else
  `ifdef PBCH_MODE
    `DEC_TOP dut(.*,.start_i(start),.start_ready_o(start_ready),
        .code_bits_i(code_bits),.code_count_i(code_count),.code_valid_i(code_valid),
        .code_ready_o(code_ready),.replay_req_o(replay_req),
        .replay_bits_i(replay_bits),.replay_count_i(replay_count),
        .replay_valid_i(replay_valid),.replay_ready_o(replay_ready),
        .info_bits_o(info_bits),.info_count_o(info_count),.info_valid_o(info_valid),
        .info_ready_i(1'b1),.selector_o(selector),.done_o(done),
        .success_o(success),.error_count_o(error_count),.busy_o(busy));
  `else
    `DEC_TOP dut(.*,.start_i(start),.start_ready_o(start_ready),
        .code_bits_i(code_bits),.code_count_i(code_count),.code_valid_i(code_valid),
        .code_ready_o(code_ready),.replay_req_o(replay_req),
        .replay_bits_i(replay_bits),.replay_count_i(replay_count),
        .replay_valid_i(replay_valid),.replay_ready_o(replay_ready),
        .info_bits_o(info_bits),.info_count_o(info_count),.info_valid_o(info_valid),
        .info_ready_i(1'b1),.done_o(done),.success_o(success),
        .error_count_o(error_count),.busy_o(busy));
  `endif
`endif

    function automatic integer count_at(input integer beat);
        integer b,p;
        begin
            if(L!=0 && beat==0) count_at=L;
            else begin
                b=beat-(L==0?0:1);
                if(b<INFO_BEATS) count_at=(b==INFO_BEATS-1)?K-W*(INFO_BEATS-1):W;
                else begin p=b-INFO_BEATS;
                    count_at=(p==(R+W-1)/W-1)?R-W*p:W;
                end
            end
        end
    endfunction

    task automatic drive_code(input bit replay_phase, input integer frame_index);
        integer beat;
        integer source_frame;
        begin
            source_frame=frame_index%VECTOR_FRAMES;
            beat=0;
            while(beat<CW_BEATS) begin
                @(negedge clk);
                if(replay_phase) begin
                    replay_bits=received_mem[source_frame*CW_BEATS+beat];
                    replay_count=count_at(beat);
                    replay_valid=1; if(replay_ready) beat=beat+1;
                end else begin
                    code_bits=received_mem[source_frame*CW_BEATS+beat];
                    code_count=count_at(beat);
                    code_valid=1; if(code_ready) beat=beat+1;
                end
            end
            @(negedge clk);
            if(replay_phase) replay_valid=0; else code_valid=0;
        end
    endtask

    always @(posedge clk) begin
        if(info_valid) begin
            if(info_bits!==message_mem[
                    ((outputs/INFO_BEATS)%VECTOR_FRAMES)*INFO_BEATS+
                    (outputs%INFO_BEATS)]) begin
                $display("ERROR output=%0d expected=%h got=%h",
                         outputs,message_mem[
                         ((outputs/INFO_BEATS)%VECTOR_FRAMES)*INFO_BEATS+
                         (outputs%INFO_BEATS)],info_bits);
                failures=failures+1;
            end
            outputs=outputs+1;
        end
        if(done) begin
            if(!success || error_count!=
                    expected_errors[completions%VECTOR_FRAMES]) begin
                $display("ERROR completion=%0d success=%0b errors=%0d expected=%0d",
                         completions,success,error_count,
                         expected_errors[completions%VECTOR_FRAMES]);
                failures=failures+1;
            end
            completions=completions+1;
        end
    end

    integer frame;
    integer input_frame;
    integer replay_frame;
    initial begin
        if(!$value$plusargs("VEC_DIR=%s",vector_dir)) $fatal(1,"missing VEC_DIR");
        $readmemh({vector_dir,"/pipeline_message.mem"},message_mem);
        $readmemh({vector_dir,"/pipeline_received.mem"},received_mem);
        $readmemh({vector_dir,"/pipeline_error_count.mem"},expected_errors);
        repeat(4) @(posedge clk); reset_n=1;
        fork
            begin
                for(input_frame=0;input_frame<FRAMES;input_frame=input_frame+1) begin
                    wait(start_ready); @(negedge clk); start=1;
                    start_cycle[input_frame]=cycle;
                    @(negedge clk); start=0; drive_code(0,input_frame);
                end
            end
`ifndef BUFFERED_MODE
            begin
                for(replay_frame=0;replay_frame<FRAMES;replay_frame=replay_frame+1) begin
                    wait(replay_req); drive_code(1,replay_frame);
                end
            end
`endif
        join
        wait(completions==FRAMES);
        if(outputs!=FRAMES*INFO_BEATS) failures=failures+1;
        for(frame=1;frame<FRAMES;frame=frame+1)
            $display("METRIC start_gap_%0d=%0d",frame,start_cycle[frame]-start_cycle[frame-1]);
        if(failures) $fatal(1,"pipeline failures=%0d",failures);
        $display("PASS pipeline frames=%0d outputs=%0d",FRAMES,outputs);
        $finish;
    end
    initial begin #10000000; $fatal(1,"pipeline timeout"); end
endmodule

`default_nettype wire
