`timescale 1ns/1ps
module fwht_compact_tb;
localparam CASES=1000;
reg clk=0,reset_n=0,start_i=0,base_is_zero_i=0,add_valid_i=0,finish_i=0;
reg [12:0] label_i=0;
wire start_ready_o,add_ready_o,overflow_o,done_o,busy_o;
wire [12:0] selector_o;
wire signed [13:0] best_score_o;
fwht_h7_c16_e0_f1_m6_hs1 dut(.*);
always #1.666667 clk=~clk;
reg [5:0] counts[0:CASES-1];
reg [428:0] labels[0:CASES-1];
reg [32:0] positive[0:CASES-1];
reg [12:0] selectors[0:CASES-1];
reg signed [6:0] scores[0:CASES-1];
reg [1023:0] vec_dir;
integer c,f,cycles,fd;
initial begin
if(!$value$plusargs("VEC_DIR=%s",vec_dir)) $fatal(1,"VEC_DIR missing");
$readmemh({vec_dir,"/counts.hex"},counts);
$readmemh({vec_dir,"/labels.hex"},labels);
$readmemh({vec_dir,"/positive.hex"},positive);
$readmemh({vec_dir,"/selectors.hex"},selectors);
$readmemh({vec_dir,"/scores.hex"},scores);
repeat(3) @(negedge clk);reset_n=1;
for(c=0;c<CASES;c=c+1) begin
wait(start_ready_o);@(negedge clk);start_i=1;
@(negedge clk);start_i=0;
for(f=0;f<counts[c];f=f+1) begin
label_i=labels[c][13*f+:13];base_is_zero_i=positive[c][f];add_valid_i=1;
@(negedge clk);
end
add_valid_i=0;finish_i=1;
@(negedge clk);finish_i=0;cycles=0;
while(!done_o && cycles<40000) begin @(negedge clk);cycles=cycles+1;end
if(!done_o || selector_o!==selectors[c] || $signed(best_score_o)!==$signed(scores[c]) || overflow_o!==(counts[c]>32))
$fatal(1,"case %0d flags%0d selector%0d/%0d score%0d/%0d overflow%0b cycles%0d",c,counts[c],selector_o,selectors[c],best_score_o,scores[c],overflow_o,cycles);
$display("RESULT case=%0d flags=%0d search_cycles=%0d selector=%0d score=%0d",c,counts[c],cycles,selector_o,best_score_o);
end
$display("PASS compact FWHT fwht_h7_c16_e0_f1_m6_hs1 cases=%0d",CASES);$finish;
end
endmodule
