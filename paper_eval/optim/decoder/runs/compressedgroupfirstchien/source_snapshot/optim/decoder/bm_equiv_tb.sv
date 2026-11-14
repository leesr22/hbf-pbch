`timescale 1ns/1ps
`default_nettype none
module bm_equiv_tb;
    localparam integer M=13,T=`T_BITS,D=$clog2(T+1),LOC=(T+1)*M;
    reg clk=0,reset_n=0,start=0;
    always #1 clk=~clk;
    reg [2*T*M-1:0] syndromes=0;
    reg [2*T*M-1:0] memory[0:999];
    wire [LOC-1:0] original_locator,shared_locator,binary_locator,compact_locator;
    wire [D-1:0] original_degree,shared_degree,binary_degree,compact_degree;
    wire compact_done,compact_busy;
    wire original_done,shared_done,binary_done,original_busy,shared_busy,binary_busy;
    reg seen_original=0,seen_shared=0,seen_binary=0,seen_compact=0;
    reg [LOC-1:0] saved_original,saved_shared,saved_binary,saved_compact;
    reg [D-1:0] degree_original,degree_shared,degree_binary,degree_compact;
    integer trial;
    string vectors;
    bch_bm #(.T(T)) original_u(.clk(clk),.reset_n(reset_n),.start_i(start),.syndromes_i(syndromes),.locator_o(original_locator),.degree_o(original_degree),.done_o(original_done),.busy_o(original_busy));
    bch_bm_shared #(.T(T)) shared_u(.clk(clk),.reset_n(reset_n),.start_i(start),.syndromes_i(syndromes),.locator_o(shared_locator),.degree_o(shared_degree),.done_o(shared_done),.busy_o(shared_busy));
    bch_bm_binary #(.T(T)) binary_u(.clk(clk),.reset_n(reset_n),.start_i(start),.syndromes_i(syndromes),.locator_o(binary_locator),.degree_o(binary_degree),.done_o(binary_done),.busy_o(binary_busy));
    bch_bm_compact #(.T(T)) compact_u(.clk(clk),.reset_n(reset_n),.start_i(start),.syndromes_i(syndromes),.locator_o(compact_locator),.degree_o(compact_degree),.done_o(compact_done),.busy_o(compact_busy));
    always @(posedge clk) begin
        if(original_done) begin seen_original=1;saved_original=original_locator;degree_original=original_degree;end
        if(shared_done) begin seen_shared=1;saved_shared=shared_locator;degree_shared=shared_degree;end
        if(binary_done) begin seen_binary=1;saved_binary=binary_locator;degree_binary=binary_degree;end
        if(compact_done) begin seen_compact=1;saved_compact=compact_locator;degree_compact=compact_degree;end
    end
    initial begin
        if(!$value$plusargs("VEC_FILE=%s",vectors)) $fatal(1,"VEC_FILE");
        $readmemh(vectors,memory);
        repeat(4) @(negedge clk);reset_n=1;
        for(trial=0;trial<1000;trial=trial+1) begin
            @(negedge clk);
            seen_original=0;seen_shared=0;seen_binary=0;seen_compact=0;
            syndromes=memory[trial];start=1;
            @(negedge clk);start=0;
            wait(seen_original && seen_shared && seen_binary && seen_compact);
            if(saved_original!==saved_shared || saved_original!==saved_binary || saved_original!==saved_compact || degree_original!==degree_shared || degree_original!==degree_binary || degree_original!==degree_compact)
                $fatal(1,"BM inequivalence T=%0d trial=%0d degrees=%0d/%0d/%0d",T,trial,degree_original,degree_shared,degree_binary);
        end
        $display("PASS BM exact locator+degree T=%0d 1000 sets: actualerrors0..2T+5 +random Frobenius syndromes",T);
        $finish;
    end
    initial begin #1000000;$fatal(1,"timeout");end
endmodule
`default_nettype wire
