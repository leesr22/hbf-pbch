`default_nettype none
// Exact sparse-input blocked FWHT. Blocks enumerate selectors in numerical
// order, permitting a proof-safe stop at the first score == flag_count.
// Histogram construction shares CHUNK flag lanes across up to MAX_FLAGS flags.
module selector_search_fwht_compact #(
    parameter integer L=13, N=4213, MAX_FLAGS=32,
    parameter integer HIGH_L=5, LOW_L=L-HIGH_L,
    parameter integer PIPE_GROUP=HIGH_L,
    parameter integer CHUNK=8, EARLY_EXIT=1, FUSE_INPUT=0, MODULAR6=0,
    parameter integer HIST_STYLE=0,
    parameter integer BLOCK=1<<HIGH_L, OUTER=1<<LOW_L,
    parameter integer PIPE_COUNT=(HIGH_L+PIPE_GROUP-1)/PIPE_GROUP,
    parameter integer FLAG_COUNT_W=$clog2(MAX_FLAGS+1),
    parameter integer SCORE_W=$clog2(N+1)+1,
    parameter integer ACC_W=$clog2(MAX_FLAGS+1)+1
) (
    input wire clk, reset_n, start_i,
    output wire start_ready_o,
    input wire [L-1:0] label_i,
    input wire base_is_zero_i, add_valid_i,
    output wire add_ready_o,
    input wire finish_i,
    output reg [L-1:0] selector_o,
    output reg signed [SCORE_W-1:0] best_score_o,
    output reg overflow_o, done_o,
    output wire busy_o
);
    localparam [1:0] IDLE=0, LOAD=1, SEARCH=2;
    localparam integer CHUNKS=(MAX_FLAGS+CHUNK-1)/CHUNK;
    localparam integer CHUNK_W=(CHUNKS>1)?$clog2(CHUNKS):1;
    localparam integer INTERNAL_W=ACC_W-((MODULAR6!=0)?1:0);
    localparam signed [ACC_W-1:0] MIN_SCORE={1'b1,{(ACC_W-1){1'b0}}};
    reg [1:0] state_q;
    reg [FLAG_COUNT_W-1:0] count_q;
    reg [L-1:0] labels_q[0:MAX_FLAGS-1];
    reg positive_q[0:MAX_FLAGS-1];
    reg [FLAG_COUNT_W-1:0] bucket_count_q[0:BLOCK-1];
    reg [CHUNK_W-1:0] chunk_q;
    reg [LOW_L:0] feed_q;
    reg signed [INTERNAL_W-1:0] accumulated_q[0:BLOCK-1];
    reg signed [INTERNAL_W-1:0] value_q[0:PIPE_COUNT][0:BLOCK-1];
    reg [PIPE_COUNT:0] valid_q;
    reg [LOW_L-1:0] outer_q[0:PIPE_COUNT];
    reg signed [ACC_W-1:0] best_q;
    reg [L-1:0] best_index_q;
    wire last_chunk=(CHUNKS==1) ? 1'b1 : ((chunk_q+1)*CHUNK>=count_q);
    wire [L-1:0] chunk_labels[0:CHUNK-1];
    wire [CHUNK-1:0] chunk_active, chunk_positive;
    wire signed [INTERNAL_W-1:0] partial_h[0:BLOCK-1];
    wire signed [INTERNAL_W-1:0] group_value[0:PIPE_COUNT-1][0:PIPE_GROUP][0:BLOCK-1];
    genvar f,b,g,s,i;
    generate
        for(f=0;f<CHUNK;f=f+1) begin: flags
            wire [FLAG_COUNT_W-1:0] position=chunk_q*CHUNK+f;
            assign chunk_labels[f]=labels_q[position];
            assign chunk_active[f]=position<count_q;
            assign chunk_positive[f]=positive_q[position] ^
                ^(feed_q[LOW_L-1:0] & chunk_labels[f][L-1:HIGH_L]);
        end
        for(b=0;b<BLOCK;b=b+1) begin: histogram
            wire [CHUNK-1:0] active;
            for(f=0;f<CHUNK;f=f+1) begin: contribution
                assign active[f]=chunk_active[f] &&
                    (chunk_labels[f][HIGH_L-1:0]==b[HIGH_L-1:0]);
            end
            if(HIST_STYLE==0) begin: signed_tree
                wire signed [$clog2(CHUNK+1):0] chunk_sum;
                sparse_signed_sum_tree #(.COUNT(CHUNK)) sum_u(
                    .valid_i(active),.positive_i(chunk_positive),.sum_o(chunk_sum));
                assign partial_h[b]=chunk_sum;
            end else if(HIST_STYLE==3) begin: biased_tree
                // c in {-1,0,+1} is encoded as unsigned c+2 in {1,2,3}.
                // Sum without sign extension, then subtract the fixed bias.
                wire [$clog2(3*CHUNK+1)-1:0] biased_sum;
                fwht_biased_sum_tree #(.COUNT(CHUNK)) sum_u(
                    .valid_i(active),.positive_i(chunk_positive),.sum_o(biased_sum));
                assign partial_h[b]=biased_sum-2*CHUNK;
            end else begin: unsigned_tree
                wire [$clog2(CHUNK+1)-1:0] positives;
                fwht_popcount #(.COUNT(CHUNK)) positive_u(
                    .bits_i(active & chunk_positive),.sum_o(positives));
                if(HIST_STYLE==1) begin: count_both
                    wire [$clog2(CHUNK+1)-1:0] total;
                    fwht_popcount #(.COUNT(CHUNK)) total_u(.bits_i(active),.sum_o(total));
                    assign partial_h[b]=(positives<<1)-total;
                end else begin: cached_total
                    assign partial_h[b]=(positives<<1)-bucket_count_q[b];
                end
            end
        end
        for(g=0;g<PIPE_COUNT;g=g+1) begin: groups
            for(i=0;i<BLOCK;i=i+1) begin: inputs
                if(g==0 && FUSE_INPUT!=0) begin: fused
                    assign group_value[g][0][i]=partial_h[i]+((chunk_q==0)?0:accumulated_q[i]);
                end else begin: registered
                    assign group_value[g][0][i]=value_q[g][i];
                end
            end
            for(s=0;s<PIPE_GROUP;s=s+1) begin: stages
                localparam integer STAGE=g*PIPE_GROUP+s;
                for(i=0;i<BLOCK;i=i+1) begin: butterflies
                    if(STAGE<HIGH_L) begin: active
                        localparam integer PARTNER=i^(1<<STAGE);
                        if((i&(1<<STAGE))==0) begin: plus
                            assign group_value[g][s+1][i]=group_value[g][s][i]+group_value[g][s][PARTNER];
                        end else begin: minus
                            assign group_value[g][s+1][i]=group_value[g][s][PARTNER]-group_value[g][s][i];
                        end
                    end else begin: bypass
                        assign group_value[g][s+1][i]=group_value[g][s][i];
                    end
                end
            end
        end
    endgenerate
    wire signed [ACC_W-1:0] block_max;
    wire [HIGH_L-1:0] block_index;
    wire [HIGH_L-1:0] indices[0:BLOCK-1];
    wire signed [ACC_W-1:0] max_values[0:BLOCK-1];
    wire first_outer_positive=positive_q[0] ^
        ^(outer_q[PIPE_COUNT] & labels_q[0][L-1:HIGH_L]);
    generate for(i=0;i<BLOCK;i=i+1) begin: index_init
        assign indices[i]=i[HIGH_L-1:0];
        if(MODULAR6!=0) begin: recover
            // All stages are linear over Z/64Z. True outputs lie in[-32,32].
            // The sole residue ambiguity is +32 versus -32. At either extreme
            // all32 signed contributions agree, so one term determines sign.
            wire positive32=(value_q[PIPE_COUNT][i]==6'b100000) &&
                (first_outer_positive ^ ^(labels_q[0][HIGH_L-1:0]&i[HIGH_L-1:0]));
            assign max_values[i]={value_q[PIPE_COUNT][i][5] && !positive32,
                                  value_q[PIPE_COUNT][i]};
        end else begin: normal
            assign max_values[i]=value_q[PIPE_COUNT][i];
        end
    end endgenerate
    fht_max_tree #(.COUNT(BLOCK),.SCORE_W(ACC_W),.INDEX_W(HIGH_L)) max_u(
        .value_i(max_values),.index_i(indices),
        .value_o(block_max),.index_o(block_index));
    wire [L-1:0] candidate={outer_q[PIPE_COUNT],block_index};
    // Blocks are disjoint increasing selector ranges, so equal scores retain
    // the already selected earlier block; the tree retains the smallest lane.
    wire better=$signed(block_max)>$signed(best_q);
    wire perfect=(EARLY_EXIT!=0) && ($signed(block_max)==$signed({1'b0,count_q}));
    assign start_ready_o=state_q==IDLE;
    assign add_ready_o=state_q==LOAD;
    assign busy_o=state_q!=IDLE;
    integer p,j;
    always @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            state_q<=IDLE; count_q<=0; chunk_q<=0; feed_q<=0;
            valid_q<=0; best_q<=MIN_SCORE; best_index_q<=0;
            selector_o<=0; best_score_o<=0; overflow_o<=0; done_o<=0;
        end else begin
            done_o<=0;
            case(state_q)
                IDLE: if(start_i) begin
                    count_q<=0; valid_q<=0; overflow_o<=0; state_q<=LOAD;
                    if(HIST_STYLE==2)
                        for(j=0;j<BLOCK;j=j+1) bucket_count_q[j]<=0;
                end
                LOAD: begin
                    if(add_valid_i) begin
                        if(count_q<MAX_FLAGS) begin
                            labels_q[count_q]<=label_i;
                            positive_q[count_q]<=base_is_zero_i;
                            count_q<=count_q+1'b1;
                            if(HIST_STYLE==2)
                                for(j=0;j<BLOCK;j=j+1)
                                    if(label_i[HIGH_L-1:0]==j[HIGH_L-1:0])
                                        bucket_count_q[j]<=bucket_count_q[j]+1'b1;
                        end else overflow_o<=1;
                    end
                    if(finish_i) begin
                        chunk_q<=0; feed_q<=0; valid_q<=0;
                        best_q<=MIN_SCORE; best_index_q<=0; state_q<=SEARCH;
                    end
                end
                SEARCH: begin
                    valid_q[0]<=0;
                    if(feed_q<OUTER) begin
                        if(last_chunk) begin
                            for(j=0;j<BLOCK;j=j+1)
                                value_q[0][j]<=partial_h[j]+((chunk_q==0)?0:accumulated_q[j]);
                            outer_q[0]<=feed_q[LOW_L-1:0];
                            valid_q[0]<=1; feed_q<=feed_q+1'b1; chunk_q<=0;
                        end else begin
                            for(j=0;j<BLOCK;j=j+1)
                                accumulated_q[j]<=partial_h[j]+((chunk_q==0)?0:accumulated_q[j]);
                            chunk_q<=chunk_q+1'b1;
                        end
                    end
                    for(p=0;p<PIPE_COUNT;p=p+1) begin
                        if(p==0 && FUSE_INPUT!=0) begin
                            valid_q[p+1]<=(feed_q<OUTER) && last_chunk;
                            outer_q[p+1]<=feed_q[LOW_L-1:0];
                        end else begin
                            valid_q[p+1]<=valid_q[p];
                            outer_q[p+1]<=outer_q[p];
                        end
                        for(j=0;j<BLOCK;j=j+1)
                            value_q[p+1][j]<=group_value[p][PIPE_GROUP][j];
                    end
                    if(valid_q[PIPE_COUNT]) begin
                        if(better) begin best_q<=block_max; best_index_q<=candidate; end
                        if(perfect || outer_q[PIPE_COUNT]==OUTER-1) begin
                            selector_o<=better?candidate:best_index_q;
                            best_score_o<=better?block_max:best_q;
                            done_o<=1; valid_q<=0; state_q<=IDLE;
                        end
                    end
                end
                default: state_q<=IDLE;
            endcase
        end
    end
`ifndef SYNTHESIS
    initial begin
        if(MODULAR6!=0 && (MAX_FLAGS!=32 || ACC_W!=7))
            $fatal(1,"MODULAR6 proof requires MAX_FLAGS32 ACC_W7");
        if(HIST_STYLE==2 && CHUNK!=MAX_FLAGS)
            $fatal(1,"Cached total histogram currently requires CHUNK=MAX_FLAGS");
    end
`endif
endmodule

module fwht_popcount #(
    parameter integer COUNT=32, OUT_W=$clog2(COUNT+1)
)(input wire [COUNT-1:0] bits_i, output wire [OUT_W-1:0] sum_o);
    generate if(COUNT==1) begin: leaf
        assign sum_o=bits_i[0];
    end else begin: branch
        localparam integer LEFT=COUNT/2, RIGHT=COUNT-LEFT;
        wire [$clog2(LEFT+1)-1:0] left_sum;
        wire [$clog2(RIGHT+1)-1:0] right_sum;
        fwht_popcount #(.COUNT(LEFT)) left_u(.bits_i(bits_i[LEFT-1:0]),.sum_o(left_sum));
        fwht_popcount #(.COUNT(RIGHT)) right_u(.bits_i(bits_i[COUNT-1:LEFT]),.sum_o(right_sum));
        assign sum_o=left_sum+right_sum;
    end endgenerate
endmodule

module fwht_biased_sum_tree #(
    parameter integer COUNT=32, OUT_W=$clog2(3*COUNT+1)
)(input wire [COUNT-1:0] valid_i, positive_i,
  output wire [OUT_W-1:0] sum_o);
    generate if(COUNT==1) begin: leaf
        assign sum_o={~(valid_i[0] & !positive_i[0]),valid_i[0]};
    end else begin: branch
        localparam integer LEFT=COUNT/2, RIGHT=COUNT-LEFT;
        wire [$clog2(3*LEFT+1)-1:0] left_sum;
        wire [$clog2(3*RIGHT+1)-1:0] right_sum;
        fwht_biased_sum_tree #(.COUNT(LEFT)) left_u(
            .valid_i(valid_i[LEFT-1:0]),.positive_i(positive_i[LEFT-1:0]),.sum_o(left_sum));
        fwht_biased_sum_tree #(.COUNT(RIGHT)) right_u(
            .valid_i(valid_i[COUNT-1:LEFT]),.positive_i(positive_i[COUNT-1:LEFT]),.sum_o(right_sum));
        assign sum_o=left_sum+right_sum;
    end endgenerate
endmodule
`default_nettype wire
