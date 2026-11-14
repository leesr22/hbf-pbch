`timescale 1ns/1ps
`default_nettype none
module encoder_pipeline_tb;
    localparam integer R=`R_BITS, FRAMES=128;
    reg clk=0, reset_n=0, start=0, in_valid=0, out_ready=1;
    always #1.666667 clk=~clk;
    reg [511:0] in_bits=0;
    reg [9:0] in_count=512;
    wire start_ready,in_ready,out_valid,out_last,done,busy;
    wire [511:0] out_bits;
    wire [9:0] out_count;
    `ENC_TOP dut(.clk(clk),.reset_n(reset_n),.start_i(start),
        .start_ready_o(start_ready),.in_bits_i(in_bits),.in_count_i(in_count),
        .in_valid_i(in_valid),.in_ready_o(in_ready),.out_bits_o(out_bits),
        .out_count_o(out_count),.out_valid_o(out_valid),.out_ready_i(out_ready),
        .out_last_o(out_last),.done_o(done),.busy_o(busy));
    reg [511:0] messages[0:FRAMES*8-1], expected[0:FRAMES*9-1];
    integer start_cycle[0:FRAMES-1];
    integer cycle=0,started=0,completed=0,input_frame=-1,input_beat=8,output_beat=0;
    integer stall_mode=0,latency,last_start=-1;
    reg [31:0] random_state=32'h1e6d9a3f;
    reg sampled_start=0,sampled_input=0,sampled_output=0,sampled_last=0;
    reg [511:0] sampled_bits;
    reg [9:0] sampled_count;
    string vector_dir;
    // Drive and pre-sample away from the active edge: library zero-delay
    // sequential models need not share behavioral NBA scheduling semantics.
    always @(negedge clk) begin
        if(reset_n) begin
            random_state=random_state^(random_state<<13);
            random_state=random_state^(random_state>>17);
            random_state=random_state^(random_state<<5);
            out_ready=!stall_mode || ((random_state & 7)!=0);
            #0.05;
            start=started<FRAMES && start_ready;
            in_valid=input_frame>=0 && input_beat<8;
            if(in_valid) in_bits=messages[input_frame*8+input_beat];
            #0.05;
            sampled_start=start&&start_ready;
            sampled_input=in_valid&&in_ready;
            sampled_output=out_valid&&out_ready;
            sampled_bits=out_bits;
            sampled_count=out_count;
            sampled_last=out_last;
        end else begin
            start=0;in_valid=0;sampled_start=0;sampled_input=0;sampled_output=0;
        end
    end
    always @(posedge clk) if(reset_n) begin
        cycle=cycle+1;
        if(sampled_start) begin
            if(!stall_mode && last_start>=0 && cycle-last_start!=9)
                $fatal(1,"II mismatch frame=%0d gap=%0d",started,cycle-last_start);
            start_cycle[started]=cycle;
            last_start=cycle;
            input_frame=started;input_beat=0;started=started+1;
        end
        if(sampled_input) input_beat=input_beat+1;
        if(sampled_output) begin
            if(sampled_bits!==expected[completed*9+output_beat] ||
               sampled_count!==((output_beat<8)?512:R) ||
               sampled_last!==(output_beat==8))
                $fatal(1,"Golden mismatch frame=%0d beat=%0d",completed,output_beat);
            if(sampled_last) begin
                latency=cycle-start_cycle[completed];
                if(!stall_mode && latency!=9)
                    $fatal(1,"E2E mismatch frame=%0d cycles=%0d",completed,latency);
                completed=completed+1;output_beat=0;
            end else output_beat=output_beat+1;
            if(completed==FRAMES) begin
                if(stall_mode) $display("PASS mapped/golden BCH R=%0d frames=%0d beats=%0d random output stalls",R,FRAMES,FRAMES*9);
                else $display("PASS mapped/golden BCH R=%0d frames=%0d beats=%0d E2E=9 II=9",R,FRAMES,FRAMES*9);
                $finish;
            end
        end
    end
    initial begin
        if(!$value$plusargs("VEC_DIR=%s",vector_dir)) $fatal(1,"missing VEC_DIR");
        if($value$plusargs("STALL=%d",stall_mode)) begin end
        $readmemh({vector_dir,"/messages.mem"},messages);
        $readmemh({vector_dir,"/codewords.mem"},expected);
        repeat(4) @(negedge clk);
        #0.2; reset_n=1;
    end
    initial begin #100000; $fatal(1,"pipeline timeout"); end
endmodule
`default_nettype wire
