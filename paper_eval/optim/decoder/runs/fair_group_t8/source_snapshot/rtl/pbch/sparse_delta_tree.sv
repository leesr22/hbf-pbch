`default_nettype none

// Balanced signed reduction for one Gray-search lane.  A toggled flag changes
// its contribution by +2 when it was mismatched and -2 when it was matched.
module sparse_delta_tree #(
    parameter integer COUNT = 32,
    parameter integer SCORE_W = 14,
    parameter integer PADDED = (1 << $clog2(COUNT)),
    parameter integer LEVELS = $clog2(PADDED)
) (
    input  wire toggle_i [0:COUNT-1],
    input  wire match_i  [0:COUNT-1],
    output wire signed [SCORE_W-1:0] delta_o
);
    // Keep the inter-level container at the final width, but perform each
    // addition at only the precision that level can actually need.  A leaf
    // is in {-2,0,+2} (3 signed bits); each reduction level grows the worst
    // case magnitude by one bit.  Explicit slicing below prevents synthesis
    // from building SCORE_W-bit adders at every level.
    wire signed [SCORE_W-1:0] value [0:LEVELS][0:PADDED-1];

    genvar item;
    generate
        for (item = 0; item < PADDED; item = item + 1) begin : leaves
            if (item < COUNT) begin : real_item
                assign value[0][item] = toggle_i[item] ?
                    (match_i[item] ? -2 : 2) : 0;
            end else begin : padding
                assign value[0][item] = '0;
            end
        end
    endgenerate

    genvar level;
    genvar pair;
    generate
        for (level = 0; level < LEVELS; level = level + 1) begin : levels
            for (pair = 0; pair < (PADDED >> (level+1));
                 pair = pair + 1) begin : pairs
                localparam integer IN_W = ((level + 3) < SCORE_W) ?
                                            (level + 3) : SCORE_W;
                localparam integer OUT_W = ((level + 4) < SCORE_W) ?
                                             (level + 4) : SCORE_W;
                wire signed [IN_W-1:0] left =
                    value[level][2*pair][IN_W-1:0];
                wire signed [IN_W-1:0] right =
                    value[level][2*pair+1][IN_W-1:0];
                wire signed [OUT_W-1:0] sum =
                    {{(OUT_W-IN_W){left[IN_W-1]}},left} +
                    {{(OUT_W-IN_W){right[IN_W-1]}},right};
                assign value[level+1][pair] =
                    {{(SCORE_W-OUT_W){sum[OUT_W-1]}},sum};
            end
        end
    endgenerate

    assign delta_o = value[LEVELS][0];
endmodule

`default_nettype wire
