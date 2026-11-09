`default_nettype none

// Balanced signed reduction for sparse +1/-1/0 contributions.
// Each recursive level grows only to the number of bits required by the
// number of leaves below it; this avoids a serial chain of full-width adders.
module signed_sum_tree #(
    parameter integer COUNT = 32,
    parameter integer SUM_W = $clog2(COUNT + 1) + 1
) (
    input  wire [COUNT-1:0] valid_i,
    input  wire [COUNT-1:0] positive_i,
    output wire signed [SUM_W-1:0] sum_o
);
    generate
        if (COUNT == 1) begin : leaf
            assign sum_o = !valid_i[0] ? {SUM_W{1'b0}} :
                           positive_i[0] ?
                           {{(SUM_W-1){1'b0}},1'b1} : {SUM_W{1'b1}};
        end else begin : branch
            localparam integer LEFT_COUNT = COUNT / 2;
            localparam integer RIGHT_COUNT = COUNT - LEFT_COUNT;
            localparam integer LEFT_W = $clog2(LEFT_COUNT + 1) + 1;
            localparam integer RIGHT_W = $clog2(RIGHT_COUNT + 1) + 1;
            wire signed [LEFT_W-1:0] left_sum;
            wire signed [RIGHT_W-1:0] right_sum;
            wire signed [SUM_W-1:0] left_extended =
                {{(SUM_W-LEFT_W){left_sum[LEFT_W-1]}},left_sum};
            wire signed [SUM_W-1:0] right_extended =
                {{(SUM_W-RIGHT_W){right_sum[RIGHT_W-1]}},right_sum};

            signed_sum_tree #(.COUNT(LEFT_COUNT)) left_u (
                .valid_i(valid_i[LEFT_COUNT-1:0]),
                .positive_i(positive_i[LEFT_COUNT-1:0]),
                .sum_o(left_sum)
            );
            signed_sum_tree #(.COUNT(RIGHT_COUNT)) right_u (
                .valid_i(valid_i[COUNT-1:LEFT_COUNT]),
                .positive_i(positive_i[COUNT-1:LEFT_COUNT]),
                .sum_o(right_sum)
            );
            assign sum_o = left_extended + right_extended;
        end
    endgenerate
endmodule

`default_nettype wire
