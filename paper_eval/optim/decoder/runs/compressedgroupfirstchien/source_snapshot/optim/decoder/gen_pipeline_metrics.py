#!/usr/bin/env python3
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
OUT=Path(__file__).resolve().parent
src=(ROOT/'tb/study_decoder_pipeline_tb.sv').read_text()
src=src.replace('module study_decoder_pipeline_tb;', 'module decoder_pipeline_metrics_tb;')
src=src.replace('    integer start_cycle[0:FRAMES-1];', '    integer start_cycle[0:FRAMES-1];\n    time accepted_time[0:FRAMES-1];\n    integer accepted_frames=0;')
src=src.replace('    always @(posedge clk) begin\n        if(info_valid)', '    always @(posedge clk) begin\n        if(start && start_ready) begin\n            accepted_time[accepted_frames]=$time;accepted_frames=accepted_frames+1;\n        end\n        if(info_valid)')
src=src.replace('            outputs=outputs+1;', '            outputs=outputs+1;\n            if(outputs%INFO_BEATS==0) $display("METRIC E2E_frame_%0d=%0d",outputs/INFO_BEATS-1,($time-accepted_time[outputs/INFO_BEATS-1])/4);')
(OUT/'decoder_pipeline_metrics_tb.sv').write_text(src)
