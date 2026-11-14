`default_nettype none

// Balanced signed maximum tree.  Equal scores select the lower index.
module fht_max_tree #(
    parameter integer COUNT = 64,
    parameter integer SCORE_W = 14,
    parameter integer INDEX_W = 13,
    parameter integer LEVELS = $clog2(COUNT)
) (
    input  wire signed [SCORE_W-1:0] value_i [0:COUNT-1],
    input  wire        [INDEX_W-1:0] index_i [0:COUNT-1],
    output wire signed [SCORE_W-1:0] value_o,
    output wire        [INDEX_W-1:0] index_o
);
    wire signed [SCORE_W-1:0] value_level [0:LEVELS][0:COUNT-1];
    wire        [INDEX_W-1:0] index_level [0:LEVELS][0:COUNT-1];

    genvar item;
    generate
        for (item = 0; item < COUNT; item = item + 1) begin : input_level
            assign value_level[0][item] = value_i[item];
            assign index_level[0][item] = index_i[item];
        end
    endgenerate

    genvar level;
    genvar pair;
    generate
        for (level = 0; level < LEVELS; level = level + 1) begin : tree_level
            for (pair = 0; pair < (COUNT >> (level+1)); pair = pair + 1) begin : tree_pair
                wire choose_left;
                assign choose_left =
                    ($signed(value_level[level][2*pair]) >
                     $signed(value_level[level][2*pair+1])) ||
                    (($signed(value_level[level][2*pair]) ==
                      $signed(value_level[level][2*pair+1])) &&
                     (index_level[level][2*pair] <
                      index_level[level][2*pair+1]));
                assign value_level[level+1][pair] = choose_left ?
                    value_level[level][2*pair] : value_level[level][2*pair+1];
                assign index_level[level+1][pair] = choose_left ?
                    index_level[level][2*pair] : index_level[level][2*pair+1];
            end
        end
    endgenerate

    assign value_o = value_level[LEVELS][0];
    assign index_o = index_level[LEVELS][0];
endmodule

`default_nettype wire
