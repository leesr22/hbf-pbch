`timescale 1ns/1ps
module bch_remainder_cse_t8_tb;
  reg [103:0] state;
  reg [511:0] data;
  wire [103:0] actual;
  reg [103:0] golden;
  localparam [104:0] POLY=105'h115f914e07b0c138741c5c4fb23;
  integer basis, lane;
  bch_remainder_cse_t8 dut(state,data,actual);
  always @* begin
    golden=state;
    for(lane=0;lane<512;lane=lane+1) begin
      if(data[511-lane]^golden[103])
        golden={golden[102:0],1'b0}^POLY[103:0];
      else golden={golden[102:0],1'b0};
    end
  end
  initial begin
    state=0;data=0;#1;
    if(actual!==golden) $fatal(1,"zero mismatch");
    for(basis=0;basis<616;basis=basis+1) begin
      state=0;data=0;
      if(basis<104)state[basis]=1'b1;
      else data[basis-104]=1'b1;
      #1;
      if(actual!==golden)$fatal(1,"basis mismatch %0d",basis);
    end
    $display("PASS BCH t=8 all 616 state/data basis vectors");
    $finish;
  end
endmodule
