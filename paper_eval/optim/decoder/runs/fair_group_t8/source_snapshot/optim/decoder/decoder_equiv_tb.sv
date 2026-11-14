`timescale 1ns/1ps
`default_nettype none
module decoder_equiv_tb;
    localparam integer FRAMES=144,CW_BEATS=67;
    reg clk=0,reset_n=0,start=0;
    always #1.666667 clk=~clk;
    wire start_ready;
    reg [63:0] code_bits=0,replay_bits=0;
    reg [6:0] code_count=0,replay_count=0;
    reg code_valid=0,replay_valid=0,info_ready=1;
    wire code_ready,replay_req,replay_ready,info_valid,done,success,busy;
    wire [63:0] info_bits;
    wire [6:0] info_count;
    wire [12:0] selector;
    wire [3:0] error_count;
    reg [63:0] message_mem[0:FRAMES*64-1];
    reg [63:0] received_mem[0:FRAMES*CW_BEATS-1];
    reg [12:0] selector_mem[0:FRAMES-1];
    reg [3:0] errors_mem[0:FRAMES-1];
    integer cycle=0,frame=0,outputs=0,start_cycle=0,last_cycle=0;
    string vectors;
    reg stalled=0;
    reg [63:0] held;
    `DEC_TOP dut(.clk(clk),.reset_n(reset_n),.start_i(start),.start_ready_o(start_ready),
       .code_bits_i(code_bits),.code_count_i(code_count),.code_valid_i(code_valid),.code_ready_o(code_ready),
       .replay_req_o(replay_req),.replay_bits_i(replay_bits),.replay_count_i(replay_count),.replay_valid_i(replay_valid),.replay_ready_o(replay_ready),
       .info_bits_o(info_bits),.info_count_o(info_count),.info_valid_o(info_valid),.info_ready_i(info_ready),.selector_o(selector),
       .done_o(done),.success_o(success),.error_count_o(error_count),.busy_o(busy));
    wire reference_start_ready,reference_code_ready,reference_replay_req,reference_replay_ready;
    wire [63:0] reference_info_bits;
    wire [6:0] reference_info_count;
    wire reference_info_valid,reference_done,reference_success,reference_busy;
    wire [12:0] reference_selector;
    wire [3:0] reference_error_count;
    pbch_paper_dec_replay_w64 reference_u(.clk(clk),.reset_n(reset_n),.start_i(start),.start_ready_o(reference_start_ready),
       .code_bits_i(code_bits),.code_count_i(code_count),.code_valid_i(code_valid),.code_ready_o(reference_code_ready),
       .replay_req_o(reference_replay_req),.replay_bits_i(replay_bits),.replay_count_i(replay_count),.replay_valid_i(replay_valid),.replay_ready_o(reference_replay_ready),
       .info_bits_o(reference_info_bits),.info_count_o(reference_info_count),.info_valid_o(reference_info_valid),.info_ready_i(info_ready),.selector_o(reference_selector),
       .done_o(reference_done),.success_o(reference_success),.error_count_o(reference_error_count),.busy_o(reference_busy));
    always @(posedge clk) begin
        if(reset_n) begin
            if({start_ready,code_ready,replay_req,replay_ready,info_valid,done,success,busy} !==
               {reference_start_ready,reference_code_ready,reference_replay_req,reference_replay_ready,reference_info_valid,reference_done,reference_success,reference_busy})
                $fatal(1,"control/status inequivalence frame=%0d cycle=%0d",frame,cycle);
            if(info_valid && ({info_bits,info_count,selector} !== {reference_info_bits,reference_info_count,reference_selector}))
                $fatal(1,"payload/selector inequivalence frame=%0d cycle=%0d",frame,cycle);
            if(done && error_count!==reference_error_count) $fatal(1,"error count inequivalence");
        end
    end
    always @(posedge clk) begin
        cycle=cycle+1;
        if(start && start_ready) start_cycle=cycle;
        if(reset_n && info_valid && info_ready) begin
            outputs=outputs+1;
            if(outputs==64) last_cycle=cycle;
        end
    end
    always @(negedge clk) begin
        if(frame<9) info_ready=1;
        else info_ready=(cycle%11 != 1 && cycle%11 != 2 && cycle%7 != 0);
    end
    function automatic integer count_at(input integer b);
        if(b==0) count_at=13;
        else if(b==66) count_at=40;
        else count_at=64;
    endfunction
    task automatic drive(input bit replay_phase);
        integer b;
        begin
            for(b=0;b<CW_BEATS;b=b+1) begin
                @(negedge clk);
                if(frame>=9 && b%13==0) begin
                    if(replay_phase) replay_valid=0; else code_valid=0;
                    @(negedge clk);
                end
                if(replay_phase) begin
                    replay_bits=received_mem[frame*CW_BEATS+b]; replay_count=count_at(b); replay_valid=1;
                    @(posedge clk);
                    while(!replay_ready) @(posedge clk);
                end else begin
                    code_bits=received_mem[frame*CW_BEATS+b]; code_count=count_at(b); code_valid=1;
                    @(posedge clk);
                    while(!code_ready) @(posedge clk);
                end
            end
            @(negedge clk);
            if(replay_phase) replay_valid=0; else code_valid=0;
        end
    endtask
    initial begin
        if(!$value$plusargs("VEC_DIR=%s",vectors)) $fatal(1,"VEC_DIR");
        $readmemh({vectors,"/message.mem"},message_mem);
        $readmemh({vectors,"/received_invalid.mem"},received_mem);
        $readmemh({vectors,"/selector.mem"},selector_mem);
        $readmemh({vectors,"/errors.mem"},errors_mem);
        repeat(4) @(negedge clk);reset_n=1;
        for(frame=0;frame<FRAMES;frame=frame+1) begin
            outputs=0;
            wait(start_ready);
            @(negedge clk);start=1;
            @(negedge clk);start=0;
            drive(0);
            wait(replay_req);
            drive(1);
            wait(done);#0.01;
            if(frame<9) $display("METRIC errors=%0d e2e_cycles=%0d",errors_mem[frame],last_cycle-start_cycle);
            @(negedge clk);
        end
        $display("PASS cycle-equivalence frames=%0d errors0..64 andrandominvalidwords, payload/status/control/backpressure",FRAMES);
        $finish;
    end
    initial begin #2000000;$fatal(1,"timeout");end
endmodule
`default_nettype wire
