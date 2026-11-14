#!/usr/bin/env python3
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
OUT=Path(__file__).resolve().parent
src=(ROOT/'tb/study_decoder_pipeline_tb.sv').read_text()
src=src.replace('module study_decoder_pipeline_tb;', 'module decoder_pipeline_metrics_tb;')
src=src.replace('    integer start_cycle[0:FRAMES-1];', '    integer start_cycle[0:FRAMES-1];\n    time accepted_time[0:FRAMES-1];\n    integer accepted_frames=0;')
src=src.replace('    always @(posedge clk) begin\n        if(info_valid)', '    always @(posedge clk) begin\n        if(start && start_ready) begin\n            accepted_time[accepted_frames]=$time;accepted_frames=accepted_frames+1;\n        end\n        if(info_valid)')
src=src.replace('            outputs=outputs+1;', '            outputs=outputs+1;\n            if(outputs%INFO_BEATS==0) $display("METRIC E2E_frame_%0d=%0d",outputs/INFO_BEATS-1,($time-accepted_time[outputs/INFO_BEATS-1])/4);')
src=src.replace('module decoder_pipeline_metrics_tb;', '`ifndef PIPELINE_FRAMES\n`define PIPELINE_FRAMES 25\n`endif\n\nmodule decoder_pipeline_metrics_tb;')
src=src.replace('VECTOR_FRAMES=5, FRAMES=25', 'VECTOR_FRAMES=5, FRAMES=`PIPELINE_FRAMES')
src=src.replace('    reg code_valid=0, replay_valid=0;', '    reg code_valid=0, replay_valid=0;\n    reg info_ready=1;')
src=src.replace(".info_ready_i(1'b1)", '.info_ready_i(info_ready)')
src=src.replace('if(info_valid) begin', 'if(info_valid && info_ready) begin')
src=src.replace('''                @(negedge clk);
                if(replay_phase) begin''','''                @(negedge clk);
`ifdef STRESS_PIPELINE
                if((cycle+frame_index)%13==0) begin
                    if(replay_phase) replay_valid=0;else code_valid=0;
                end else begin
`endif
                if(replay_phase) begin''')
src=src.replace('''            end
            @(negedge clk);
            if(replay_phase) replay_valid=0;''','''`ifdef STRESS_PIPELINE
                end
`endif
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
(OUT/'decoder_pipeline_metrics_tb.sv').write_text(src)
