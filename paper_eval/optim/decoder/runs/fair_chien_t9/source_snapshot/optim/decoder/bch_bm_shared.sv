`default_nettype none

// Inversionless Berlekamp-Massey.  One iteration is split into discrepancy and
// update cycles, keeping the recurrence visible and the timing predictable.
module bch_bm_shared #(
    parameter integer M = 13,
    parameter integer T = 8,
    parameter [M:0] PRIMITIVE_POLYNOMIAL = 14'h201b,
    parameter integer DEG_W = $clog2(T + 1),
    parameter integer ITER_W = $clog2(2*T),
    parameter integer DELTA_W = $clog2(4*T + 2)
) (
    input  wire                   clk,
    input  wire                   reset_n,
    input  wire                   start_i,
    input  wire [(2*T*M)-1:0]     syndromes_i,
    output reg  [((T+1)*M)-1:0]   locator_o,
    output reg  [DEG_W-1:0]       degree_o,
    output reg                    done_o,
    output wire                   busy_o
);
    `include "rtl/common/gf.svh"

    reg [M-1:0] lambda_q [0:T];
    reg [M-1:0] aux_q [0:T];
    reg [M-1:0] history_q [0:T];
    reg [M-1:0] future_q [0:2*T-2];
    reg [M-1:0] gamma_q;
    reg [M-1:0] discrepancy_q;
    reg signed [DELTA_W-1:0] delta_q;
    reg [DEG_W-1:0] degree_q;
    reg [ITER_W-1:0] iteration_q;
    reg [1:0] phase_q;
    reg [M-1:0] scaled_q [0:T];
    reg [M-1:0] mul_a [0:T];
    reg [M-1:0] mul_b [0:T];
    wire [M-1:0] product [0:T];
    integer op;
    reg busy_q;
    reg [M-1:0] discrepancy_work;
    reg [M-1:0] lambda_old [0:T];
    reg [M-1:0] lambda_next [0:T];
    reg [DEG_W-1:0] degree_next;
    integer j;

    assign busy_o = busy_q;

    genvar g;
    generate
        for(g=0;g<=T;g=g+1) begin : multipliers
            assign product[g]=gf_mul(mul_a[g],mul_b[g]);
        end
    endgenerate
    always @* begin
        for(op=0;op<=T;op=op+1) begin
            if(phase_q==0) begin
                mul_a[op]=lambda_q[op]; mul_b[op]=history_q[op];
            end else if(phase_q==1) begin
                mul_a[op]=lambda_q[op]; mul_b[op]=gamma_q;
            end else begin
                mul_a[op]=(op==0) ? {M{1'b0}} : aux_q[op-1];
                mul_b[op]=discrepancy_q;
            end
        end
    end

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            locator_o <= '0;
            degree_o <= '0;
            done_o <= 1'b0;
            busy_q <= 1'b0;
            phase_q <= 2'd0;
            gamma_q <= '0;
            discrepancy_q <= '0;
            delta_q <= '0;
            degree_q <= '0;
            iteration_q <= '0;
            for (j = 0; j <= T; j = j + 1) begin
                lambda_q[j] <= '0;
                scaled_q[j] <= '0;
                aux_q[j] <= '0;
                history_q[j] <= '0;
            end
            for (j = 0; j < 2*T-1; j = j + 1)
                future_q[j] <= '0;
        end else begin
            done_o <= 1'b0;
            if (start_i && !busy_q) begin
                busy_q <= 1'b1;
                phase_q <= 2'd0;
                gamma_q <= {{(M-1){1'b0}}, 1'b1};
                delta_q <= '0;
                degree_q <= '0;
                iteration_q <= '0;
                history_q[0] <= syndromes_i[0 +: M];
                for (j = 1; j <= T; j = j + 1)
                    history_q[j] <= '0;
                for (j = 0; j < 2*T-1; j = j + 1)
                    future_q[j] <= syndromes_i[(j+1)*M +: M];
                for (j = 0; j <= T; j = j + 1) begin
                    lambda_q[j] <= (j == 0) ? {{(M-1){1'b0}},1'b1} : '0;
                    aux_q[j] <= (j == 0) ? {{(M-1){1'b0}},1'b1} : '0;
                end
            end else if (busy_q && phase_q == 0) begin
                discrepancy_work = '0;
                for (j = 0; j <= T; j = j + 1)
                    discrepancy_work = discrepancy_work ^ product[j];
                discrepancy_q <= discrepancy_work;
                phase_q <= 2'd1;
            end else if (busy_q && phase_q == 1) begin
                for (j = 0; j <= T; j = j + 1)
                    scaled_q[j] <= product[j];
                phase_q <= 2'd2;
            end else if (busy_q) begin
                for (j = 0; j <= T; j = j + 1) begin
                    lambda_old[j] = lambda_q[j];
                    lambda_next[j] = scaled_q[j];
                    if (j > 0)
                        lambda_next[j] = lambda_next[j] ^ product[j];
                    lambda_q[j] <= lambda_next[j];
                end

                degree_next = degree_q;
                if ((discrepancy_q == 0) || (delta_q < 0)) begin
                    aux_q[0] <= '0;
                    for (j = 1; j <= T; j = j + 1)
                        aux_q[j] <= aux_q[j-1];
                    delta_q <= delta_q + 1;
                end else begin
                    for (j = 0; j <= T; j = j + 1)
                        aux_q[j] <= lambda_old[j];
                    delta_q <= -1 - delta_q;
                    gamma_q <= discrepancy_q;
                    degree_next = iteration_q + 1 - degree_q;
                    degree_q <= degree_next;
                end

                for (j = T; j > 0; j = j - 1)
                    history_q[j] <= history_q[j-1];
                history_q[0] <= future_q[0];
                for (j = 0; j < 2*T-2; j = j + 1)
                    future_q[j] <= future_q[j+1];
                future_q[2*T-2] <= '0;

                if (iteration_q == 2*T-1) begin
                    for (j = 0; j <= T; j = j + 1)
                        locator_o[j*M +: M] <= lambda_next[j];
                    degree_o <= degree_next;
                    busy_q <= 1'b0;
                    phase_q <= 2'd0;
                    done_o <= 1'b1;
                end else begin
                    iteration_q <= iteration_q + 1'b1;
                    phase_q <= 2'd0;
                end
            end
        end
    end
endmodule

`default_nettype wire
