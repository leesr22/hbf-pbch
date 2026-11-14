`timescale 1ns/1ps
module bch_remainder_cse_t9_tb;
  reg [116:0] state;
  reg [511:0] data;
  wire [116:0] actual;
  reg [116:0] golden;
  localparam [117:0] POLY=118'h2d8aa10efe51eb9ccab1b3e6b626e1;
  integer basis, lane;
  bch_remainder_cse_t9 dut(state,data,actual);
  always @* begin
    golden=state;
    for(lane=0;lane<512;lane=lane+1) begin
      if(data[511-lane]^golden[116])
        golden={golden[115:0],1'b0}^POLY[116:0];
      else golden={golden[115:0],1'b0};
    end
  end
  initial begin
    state=0;data=0;#1;
    if(actual!==golden) $fatal(1,"zero mismatch");
    for(basis=0;basis<629;basis=basis+1) begin
      state=0;data=0;
      if(basis<117)state[basis]=1'b1;
      else data[basis-117]=1'b1;
      #1;
      if(actual!==golden)$fatal(1,"basis mismatch %0d",basis);
    end
    $display("PASS BCH t=9 all 629 state/data basis vectors");
    $finish;
  end
endmodule
