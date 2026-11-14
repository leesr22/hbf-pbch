`timescale 1ns/1ps
`default_nettype none
module unmask_tb;
    reg clk=0,reset_n=0,start=0,load=0;
    always #1 clk=~clk;
    reg [12:0] selector=0;
    reg [63:0] in_bits=0;
    reg [6:0] count=64;
    reg valid=0,ready=1;
    wire [63:0] direct_bits,cse_bits,load_bits;
    wire direct_ready,cse_ready,direct_valid,cse_valid,load_ready,load_valid;
    wire [6:0] direct_count,cse_count,load_count;
    reg [12:0] columns[0:4095];
    integer s,b,l,checks=0;
    reg [63:0] expected;
    string vectors;
    pbch_unmask_rec_direct direct_u(.clk(clk),.reset_n(reset_n),.start_i(start),.selector_i(selector),.in_bits_i(in_bits),.in_count_i(count),.in_valid_i(valid),.in_ready_o(direct_ready),.out_bits_o(direct_bits),.out_count_o(direct_count),.out_valid_o(direct_valid),.out_ready_i(ready));
    pbch_unmask_rec_cse cse_u(.clk(clk),.reset_n(reset_n),.start_i(start),.selector_i(selector),.in_bits_i(in_bits),.in_count_i(count),.in_valid_i(valid),.in_ready_o(cse_ready),.out_bits_o(cse_bits),.out_count_o(cse_count),.out_valid_o(cse_valid),.out_ready_i(ready));
    pbch_unmask_rec_cseload load_u(.clk(clk),.reset_n(reset_n),.start_i(start),.load_i(load),.selector_i(selector),.in_bits_i(in_bits),.in_count_i(count),.in_valid_i(valid),.in_ready_o(load_ready),.out_bits_o(load_bits),.out_count_o(load_count),.out_valid_o(load_valid),.out_ready_i(ready));
    initial begin
        if(!$value$plusargs("VEC_DIR=%s",vectors)) $fatal(1,"VEC_DIR");
        $readmemh({vectors,"/columns.mem"},columns);
        repeat(3) @(negedge clk);
        reset_n=1;
        for(s=0;s<8192;s=s+1) begin
            @(negedge clk); start=1;selector=s;valid=0;
            @(negedge clk); start=0;load=1;
            @(negedge clk); load=0;
            for(b=0;b<64;b=b+1) begin
                in_bits={$random,$random}; valid=1;
                for(l=0;l<64;l=l+1) expected[63-l]=in_bits[63-l] ^ (^(selector & columns[b*64+l]));
                #0.1;
                if(direct_bits !== expected || cse_bits !== expected || load_bits !== expected) $fatal(1,"mask mismatch selector=%0d beat=%0d",s,b);
                checks=checks+64;
                if(b%9==0) begin
                    ready=0;
                    @(negedge clk);
                    #0.1;
                    if(direct_bits !== expected || cse_bits !== expected || load_bits !== expected) $fatal(1,"stall mismatch");
                    ready=1;
                end
                @(negedge clk);
            end
            valid=0;
        end
        $display("PASS direct/cse/cseload unmask all8192 selectors all4096 positions bits=%0d with backpressure",checks);
        $finish;
    end
endmodule
`default_nettype wire
