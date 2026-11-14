`default_nettype none
// Two coefficient groups time-share ceil((T+1)/2) GF multipliers.
// Binary BCH odd discrepancies are zero; exact inversionless scaling is kept.
module bch_bm_grouped #(
    parameter integer M=13,T=8,
    parameter [M:0] PRIMITIVE_POLYNOMIAL=14'h201b,
    parameter integer DEG_W=$clog2(T+1),ITER_W=$clog2(2*T),
    parameter integer DELTA_W=$clog2(4*T+2)
)(
    input wire clk,reset_n,start_i,
    input wire [2*T*M-1:0] syndromes_i,
    output wire [(T+1)*M-1:0] locator_o,
    output wire [DEG_W-1:0] degree_o,
    output reg done_o,
    output wire busy_o
);
    `include "rtl/common/gf.svh"
    localparam integer P=(T+2)/2;
    reg [M-1:0] lambda_q[0:T],aux_q[0:T],scaled_q[0:T];
    reg [M-1:0] synd_ring[0:2*T-1];
    reg [M-1:0] gamma_q,discrepancy_q,acc_q;
    reg signed [DELTA_W-1:0] delta_q;
    reg [DEG_W-1:0] degree_q;
    reg [ITER_W-1:0] iteration_q;
    reg [1:0] phase_q;
    reg group_q,busy_q;
    wire [M-1:0] product[0:P-1];
    reg [M-1:0] part;
    integer j;
    assign busy_o=busy_q;
    assign degree_o=degree_q;
    genvar g;
    generate for(g=0;g<=T;g=g+1) begin: outputs
        assign locator_o[g*M +: M]=lambda_q[g];
    end
    for(g=0;g<P;g=g+1) begin: multipliers
        wire [M-1:0] l0=lambda_q[g],s0=synd_ring[g];
        wire [M-1:0] a0;
        if(g==0) assign a0='0;
        else assign a0=aux_q[g-1];
        wire [M-1:0] l1,s1,a1;
        if(g+P<=T) begin: upper
            assign l1=lambda_q[g+P];
            assign s1=synd_ring[g+P];
            assign a1=aux_q[g+P-1];
        end else begin: absent
            assign l1='0;assign s1='0;assign a1='0;
        end
        wire [M-1:0] l=group_q?l1:l0;
        wire [M-1:0] s=group_q?s1:s0;
        wire [M-1:0] a=group_q?a1:a0;
        assign product[g]=gf_mul(phase_q==2?a:l,
            phase_q==0?s:(phase_q==1?gamma_q:discrepancy_q));
    end endgenerate
    always @* begin
        part='0;
        for(integer p=0;p<P;p=p+1) part=part^product[p];
    end
    always @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            busy_q<=0;done_o<=0;phase_q<=0;group_q<=0;
            gamma_q<=0;discrepancy_q<=0;acc_q<=0;
            delta_q<=0;degree_q<=0;iteration_q<=0;
            for(j=0;j<=T;j=j+1) begin
                lambda_q[j]<=0;aux_q[j]<=0;scaled_q[j]<=0;
            end
            for(j=0;j<2*T;j=j+1) synd_ring[j]<=0;
        end else begin
            done_o<=0;
            if(start_i && !busy_q) begin
                busy_q<=1;phase_q<=0;group_q<=0;
                gamma_q<=1;delta_q<=0;degree_q<=0;iteration_q<=0;
                synd_ring[0]<=syndromes_i[0 +: M];
                for(j=1;j<2*T;j=j+1) synd_ring[j]<=syndromes_i[(2*T-j)*M +: M];
                for(j=0;j<=T;j=j+1) begin
                    lambda_q[j]<=(j==0);aux_q[j]<=(j==0);
                end
            end else if(busy_q) begin
                group_q<=!group_q;
                if(phase_q==0) begin
                    if(!group_q) acc_q<=part;
                    else begin discrepancy_q<=acc_q^part;phase_q<=1;end
                end else if(phase_q==1) begin
                    for(j=0;j<=T;j=j+1) begin
                        if((j/P)==group_q) begin
                            if(iteration_q[0]) lambda_q[j]<=product[j%P];
                            else scaled_q[j]<=product[j%P];
                        end
                    end
                    if(group_q) begin
                        if(!iteration_q[0]) phase_q<=2;
                        else begin
                            aux_q[0]<=0;
                            for(j=1;j<=T;j=j+1) aux_q[j]<=aux_q[j-1];
                            delta_q<=delta_q+1;
                            for(j=2*T-1;j>0;j=j-1) synd_ring[j]<=synd_ring[j-1];
                            synd_ring[0]<=synd_ring[2*T-1];
                            phase_q<=0;
                            if(iteration_q==2*T-1) begin busy_q<=0;done_o<=1;end
                            else iteration_q<=iteration_q+1'b1;
                        end
                    end
                end else begin
                    if(!group_q) begin
                        for(j=0;j<P;j=j+1) scaled_q[j]<=scaled_q[j]^product[j];
                    end else begin
                        for(j=0;j<=T;j=j+1) begin
                            if(j<P) lambda_q[j]<=scaled_q[j];
                            else lambda_q[j]<=scaled_q[j]^product[j-P];
                        end
                        if(discrepancy_q==0 || delta_q<0) begin
                            aux_q[0]<=0;
                            for(j=1;j<=T;j=j+1) aux_q[j]<=aux_q[j-1];
                            delta_q<=delta_q+1;
                        end else begin
                            for(j=0;j<=T;j=j+1) aux_q[j]<=lambda_q[j];
                            delta_q<=-1-delta_q;gamma_q<=discrepancy_q;
                            degree_q<=iteration_q+1-degree_q;
                        end
                        for(j=2*T-1;j>0;j=j-1) synd_ring[j]<=synd_ring[j-1];
                        synd_ring[0]<=synd_ring[2*T-1];
                        iteration_q<=iteration_q+1'b1;phase_q<=1;
                    end
                end
            end
        end
    end
endmodule
`default_nettype wire
