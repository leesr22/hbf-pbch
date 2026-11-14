#!/usr/bin/env python3
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
OUT=Path(__file__).resolve().parent
src=(ROOT/'tb/study_decoder_pipeline_tb.sv').read_text()
src=src.replace('module study_decoder_pipeline_tb;', 'module decoder_pipeline_metrics_tb;')
src=src.replace('    integer start_cycle[0:FRAMES-1];', '    integer start_cycle[0:FRAMES-1];\n    time accepted_time[0:FRAMES-1];\n    integer accepted_frames=0;')
src=src.replace('    always @(posedge clk) begin\n        if(info_valid)', '    always @(posedge clk) begin\n        if(start && start_ready) begin\n            accepted_time[accepted_frames]=$time;\n            start_cycle[accepted_frames]=$time/4;\n            accepted_frames=accepted_frames+1;\n        end\n        if(info_valid)')
src=src.replace('''                    wait(start_ready); @(negedge clk); start=1;
                    start_cycle[input_frame]=cycle;''','''                    @(negedge clk); start=1;
                    @(posedge clk);
                    while(!start_ready) @(posedge clk);''')
src=src.replace('            outputs=outputs+1;', '            outputs=outputs+1;\n            if(outputs%INFO_BEATS==0) $display("METRIC E2E_frame_%0d=%0d",outputs/INFO_BEATS-1,($time-accepted_time[outputs/INFO_BEATS-1])/4);')
src=src.replace('module decoder_pipeline_metrics_tb;', '`ifndef PIPELINE_FRAMES\n`define PIPELINE_FRAMES 25\n`endif\n\nmodule decoder_pipeline_metrics_tb;')
src=src.replace('VECTOR_FRAMES=5, FRAMES=25', 'VECTOR_FRAMES=5, FRAMES=`PIPELINE_FRAMES')
src=src.replace('    reg code_valid=0, replay_valid=0;', '    reg code_valid=0, replay_valid=0;\n    reg info_ready=1;')
src=src.replace(".info_ready_i(1'b1)", '.info_ready_i(info_ready)')
src=src.replace('if(info_valid) begin', 'if(info_valid && info_ready) begin')
src=src.replace('        integer source_frame;', '        integer source_frame;\n        bit pending;')
src=src.replace('            beat=0;', '            beat=0;\n            pending=0;')
src=src.replace('replay_valid=1; if(replay_ready) beat=beat+1;', 'replay_valid=1;')
src=src.replace('code_valid=1; if(code_ready) beat=beat+1;', 'code_valid=1;')
src=src.replace('''                @(negedge clk);
                if(replay_phase) begin''','''                @(negedge clk);
`ifdef STRESS_PIPELINE
                if(!pending && (cycle+frame_index)%13==0) begin
                    if(replay_phase) replay_valid=0;else code_valid=0;
                end else begin
`endif
                pending=1;
                if(replay_phase) begin''')
src=src.replace('''            end
            @(negedge clk);
            if(replay_phase) replay_valid=0;''','''`ifdef STRESS_PIPELINE
                end
`endif
                // Count only transfers sampled by the circuit, after all
                // combinational ready paths have settled.
                @(posedge clk);
                if((replay_phase && replay_valid && replay_ready) ||
                   (!replay_phase && code_valid && code_ready)) begin
                    beat=beat+1;
                    pending=0;
                end
            end
            @(negedge clk);
            if(replay_phase) replay_valid=0;''')
src=src.replace('    integer frame;', '''`ifdef STRESS_PIPELINE
    // Readiness changes after sampling and is stable before the next negedge.
    always @(posedge clk) begin
        #0.1;
        info_ready=((cycle%97)<61) && (cycle%7!=0);
    end
`endif

    integer frame;''')
src=src.replace('        bit pending;', '        bit pending;\n        bit first_attempt;')
src=src.replace('            pending=0;\n            while', '            pending=0;\n            first_attempt=1;\n            while')
src=src.replace('''                @(negedge clk);
`ifdef STRESS_PIPELINE''','''`ifdef ZERO_START_BUBBLE
                // The input task starts on the START-deassert negedge. Present
                // beat zero immediately, so its transfer is on the next edge.
                if(replay_phase || !first_attempt) @(negedge clk);
`else
                @(negedge clk);
`endif
                first_attempt=0;
`ifdef STRESS_PIPELINE''')
src=src.replace('''                    beat=beat+1;
                    pending=0;''','''`ifdef TRACE_TIMELINE
                    if(frame_index<4 && (beat==0 || beat==CW_BEATS-1))
                        $display("TIMELINE frame=%0d event=%s_%s cycle=%0d",frame_index,
                            replay_phase?"replay":"input",beat==0?"first":"last",$time/4);
`endif
                    beat=beat+1;
                    pending=0;''')
src=src.replace('''            accepted_time[accepted_frames]=$time;''','''`ifdef TRACE_TIMELINE
            if(accepted_frames<4) $display("TIMELINE frame=%0d event=START cycle=%0d",accepted_frames,$time/4);
`endif
            accepted_time[accepted_frames]=$time;''')
src=src.replace('''            outputs=outputs+1;''','''`ifdef TRACE_TIMELINE
            if(outputs/INFO_BEATS<4 && (outputs%INFO_BEATS==0 || outputs%INFO_BEATS==INFO_BEATS-1))
                $display("TIMELINE frame=%0d event=output_%s cycle=%0d",outputs/INFO_BEATS,
                         outputs%INFO_BEATS==0?"first":"last",$time/4);
`endif
            outputs=outputs+1;''')
(OUT/'decoder_pipeline_metrics_tb.sv').write_text(src)
