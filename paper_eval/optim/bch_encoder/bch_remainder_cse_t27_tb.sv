`timescale 1ns/1ps
module bch_remainder_cse_t27_tb;
  reg [350:0] state;
  reg [511:0] data;
  wire [350:0] actual;
  reg [350:0] golden;
  localparam [351:0] POLY=352'hb4e157247094cbaae72500117981ca4f6d8438e62186330511cb8e8cf32f8eedc89a5cbf72c7002ba84111f7;
  integer basis, lane;
  bch_remainder_cse_t27 dut(state,data,actual);
  always @* begin
    golden=state;
    for(lane=0;lane<512;lane=lane+1) begin
      if(data[511-lane]^golden[350])
        golden={golden[349:0],1'b0}^POLY[350:0];
      else golden={golden[349:0],1'b0};
    end
  end
  initial begin
    state=0;data=0;#1;
    if(actual!==golden) $fatal(1,"zero mismatch");
    for(basis=0;basis<863;basis=basis+1) begin
      state=0;data=0;
      if(basis<351)state[basis]=1'b1;
      else data[basis-351]=1'b1;
      #1;
      if(actual!==golden)$fatal(1,"basis mismatch %0d",basis);
    end
    $display("PASS BCH t=27 all 863 state/data basis vectors");
    $finish;
  end
endmodule
