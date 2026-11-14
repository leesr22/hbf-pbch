`default_nettype none

// Turns a valid/ready pre-read stream into flagged codeword positions.
//
// The scanner accepts one W-bit beat, emits all its set bits, then requests the
// next beat.  Only one beat and one priority encoder are stored.  Every set bit
// is emitted, so there is no capacity limit or overflow case.
module probe_scan #(
    parameter integer N = 4278,
    parameter integer W = 64,
    parameter integer COUNT_W = $clog2(W + 1),
    parameter integer POS_W = $clog2(N + 1),
    parameter integer LANE_W = (W <= 1) ? 1 : $clog2(W),
    parameter integer GROUP_SIZE = 16,
    parameter integer GROUPS = (W + GROUP_SIZE - 1) / GROUP_SIZE,
    parameter integer GROUP_W = (GROUPS <= 1) ? 1 : $clog2(GROUPS),
    parameter integer GROUP_LANE_W = $clog2(GROUP_SIZE)
) (
    input  wire                 clk,
    input  wire                 reset_n,
    input  wire                 start_i,
    input  wire [W-1:0]         bits_i,
    input  wire [COUNT_W-1:0]   count_i,
    input  wire                 valid_i,
    output wire                 ready_o,
    output wire [POS_W-1:0]     position_o,
    output wire                 flag_valid_o,
    output reg                  finish_o,
    output reg  [POS_W-1:0]     total_o,
    output wire                 busy_o
);
    reg active_q;
    reg [W-1:0] pending_q;
    reg [POS_W-1:0] seen_q;
    reg [POS_W-1:0] base_q;
    reg [W-1:0] masked_beat;
    reg [W-1:0] selected_bit;
    reg [LANE_W-1:0] selected_lane;
    reg [GROUPS-1:0] group_has;
    reg [GROUP_W-1:0] selected_group;
    reg [GROUP_LANE_W-1:0] selected_group_lane;
    reg found_group;
    reg found_lane;
    integer group;
    integer lane;
    integer group_lane;
    integer flat_lane;

    assign ready_o = active_q && !(|pending_q) && (seen_q < N);
    assign position_o = base_q + selected_lane;
    assign flag_valid_o = active_q && (|pending_q);
    assign busy_o = active_q;

    // Stream bit 0 is carried in bits_i[W-1].  A two-level priority encoder
    // avoids the W-deep priority chain produced by one flat loop.  This is
    // especially important for W=256, but does not change which bit wins.
    always @* begin
        masked_beat = '0;
        selected_bit = '0;
        selected_lane = '0;
        group_has = '0;
        selected_group = '0;
        selected_group_lane = '0;
        found_group = 1'b0;
        found_lane = 1'b0;
        flat_lane = 0;
        for (lane = 0; lane < W; lane = lane + 1)
            if (lane < count_i)
                masked_beat[W-1-lane] = bits_i[W-1-lane];

        for (group = 0; group < GROUPS; group = group + 1)
            for (group_lane = 0; group_lane < GROUP_SIZE;
                 group_lane = group_lane + 1) begin
                flat_lane = group*GROUP_SIZE + group_lane;
                if (flat_lane < W && pending_q[W-1-flat_lane])
                    group_has[group] = 1'b1;
            end

        for (group = 0; group < GROUPS; group = group + 1)
            if (!found_group && group_has[group]) begin
                selected_group = group[GROUP_W-1:0];
                found_group = 1'b1;
            end

        for (group_lane = 0; group_lane < GROUP_SIZE;
             group_lane = group_lane + 1) begin
            flat_lane = selected_group*GROUP_SIZE + group_lane;
            if (!found_lane && flat_lane < W &&
                pending_q[W-1-flat_lane]) begin
                selected_group_lane = group_lane[GROUP_LANE_W-1:0];
                found_lane = 1'b1;
            end
        end

        selected_lane = selected_group*GROUP_SIZE + selected_group_lane;
        if (found_group && found_lane)
            selected_bit[W-1-selected_lane] = 1'b1;
    end

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            active_q <= 1'b0;
            pending_q <= '0;
            seen_q <= '0;
            base_q <= '0;
            total_o <= '0;
            finish_o <= 1'b0;
        end else begin
            finish_o <= 1'b0;
            if (start_i) begin
                active_q <= 1'b1;
                pending_q <= '0;
                seen_q <= '0;
                base_q <= '0;
                total_o <= '0;
            end else if (valid_i && ready_o) begin
                pending_q <= masked_beat;
                base_q <= seen_q;
                seen_q <= seen_q + count_i;
            end else if (flag_valid_o) begin
                pending_q <= pending_q & ~selected_bit;
                total_o <= total_o + 1'b1;
            end else if (active_q && seen_q == N) begin
                active_q <= 1'b0;
                finish_o <= 1'b1;
            end
        end
    end
endmodule

`default_nettype wire
