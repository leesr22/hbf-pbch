#!/usr/bin/env python3
"""Generate isolated encoder optimization points; preserve published RTL."""
from pathlib import Path
import argparse
import importlib.util
import json
import re
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT))
from model.ecc import STUDY_PROFILES

spec = importlib.util.spec_from_file_location('recurrence_helpers', ROOT/'optim/decoder/gen_variants.py')
helpers = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helpers)


def stream_mask(mode):
    codec = STUDY_PROFILES['pbch_paper']
    masks = codec.mask_columns()
    length, poly = helpers.binary_bm([v & 1 for v in masks[:128]])
    assert length == 32
    for n in range(32, len(masks)):
        v = 0
        for j in range(1,33):
            if poly >> j & 1:
                v ^= masks[n-j]
        assert v == masks[n], (n, v, masks[n])
    linear = [1 << i for i in range(32)]
    for n in range(32, 544):
        v = 0
        for j in range(1,33):
            if poly >> j & 1:
                v ^= linear[n-j]
        linear.append(v)
    initial = helpers.cse_assignments(masks[:32], [f'selector_i[{i}]' for i in range(13)], 'init_x', 'initial_state')
    if mode == 'cse':
        transform = helpers.cse_assignments(linear, [f'state_q[{i}]' for i in range(32)], 'step_x', 'extended')
    else:
        transform = '\n'.join(f'    assign extended[{i}] = {helpers.xor_expr(v,"state_q",32)};' for i,v in enumerate(linear))
    parity_cols = codec.influence_columns()[codec.l+codec.k:]
    parity = helpers.cse_assignments(parity_cols, [f'selector_i[{i}]' for i in range(13)], 'parity_x', 'parity_mask')
    out_assign = '\n'.join(f'    assign payload_mask_o[{511-i}] = extended[{i}];' for i in range(512))
    parity_assign = '\n'.join(f'    assign parity_mask_o[{511-i}] = parity_mask[{i}];' for i in range(codec.parent.r))
    return f'''`default_nettype none
// Exact frozen mask matrix, represented as a 32-bit binary recurrence.
module pbch_mask_stream_{mode} (
    input wire clk, load_i, advance_i,
    input wire [12:0] selector_i,
    output wire [511:0] payload_mask_o,
    output wire [511:0] parity_mask_o
);
    reg [31:0] state_q;
    wire [31:0] initial_state;
    wire [543:0] extended;
    wire [103:0] parity_mask;
{initial}
{transform}
{parity}
{out_assign}
{parity_assign}
    assign parity_mask_o[407:0] = 408'b0;
    always @(posedge clk) begin
        if (load_i) state_q <= initial_state;
        else if (advance_i) state_q <= extended[543:512];
    end
endmodule
`default_nettype wire
'''


def generate(name, mode, safe, search_file=None, search_module=None, high=7, group=7, scan_file=None, scan_module=None, credit='slot', chunk=8, early=1, fuse=0, modular=0, direct_load=False, scan_pipe=False, crc_width=512, hist_style=0, direct_stages=0):
    core = (ROOT/'rtl/pbch/pbch_sparse_pipeline_enc.sv').read_text()
    core_name = f'pbch_encoder_core_{name}'
    top_name = f'pbch_encoder_{name}'
    core = core.replace('module pbch_sparse_pipeline_enc #(', f'module {core_name} #(')
    if safe:
        core = core.replace('    wire search_done;\n', '')
        core = core.replace('    wire search_start_ready;', '    wire search_done;\n    wire search_start_ready;')
        core = core.replace('search_start_ready;\n    wire [FLAG_COUNT_W:0] load_count',
            'search_start_ready && !search_done && !result_valid_q &&\n                        !output_active_q;\n    wire [FLAG_COUNT_W:0] load_count')
        # Result wins over a scan that has not started. Otherwise a short
        # search can deadlock output and FRONT_WAIT_SCAN waiting on each other.
        core = core.replace('front_state_q != FRONT_SCAN &&\n                front_state_q != FRONT_WAIT_SCAN', 'front_state_q != FRONT_SCAN')
        if credit == 'skid':
            core = core.replace('search_start_ready && !search_done && !result_valid_q &&\n                        !output_active_q;', 'search_start_ready && !search_done && !search_result_pending_q;')
            core = core.replace('    wire search_done;', '    reg search_result_pending_q;\n    wire search_done;')
            pos = core.index('    // One completed result context')
            core = core[:pos] + '''    // Reuse the search core's stable output registers as one completion slot.
    // Metadata cannot change until this slot is transferred to output.
    wire capture_result = (search_done || search_result_pending_q) &&
        (!result_valid_q || (output_active_q && out_ready_i && emit_beat_q == EMIT_BEATS-1));
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) search_result_pending_q <= 1'b0;
        else if (capture_result) search_result_pending_q <= 1'b0;
        else if (search_done) search_result_pending_q <= 1'b1;
    end

''' + core[pos:]
            core = core.replace('            if (search_done) begin\n                result_valid_q', '            if (capture_result) begin\n                result_valid_q')
            core = core.replace('                    if (!search_done)\n                        result_valid_q', '                    if (!capture_result)\n                        result_valid_q')
            core = core.replace('if (reset_n && search_done && result_valid_q && !output_active_q)', 'if (reset_n && search_done && search_result_pending_q)')
    if mode != 'baseline':
        code = f'''    wire [W-1:0] payload_mask, parity_mask;
    pbch_mask_stream_{mode} mask_stream_u (
        .clk(clk), .load_i(output_active_q && out_ready_i && emit_beat_q == 0),
        .advance_i(output_active_q && out_ready_i && emit_beat_q > 0 && emit_beat_q <= DATA_BEATS),
        .selector_i(result_selector_q), .payload_mask_o(payload_mask),
        .parity_mask_o(parity_mask)
    );
    // Selector, payload and parity retain exactly the original bit order.
    always @* begin
        out_bits_o = '0;
        out_count_o = '0;
        out_last_o = 1'b0;
        if (output_active_q) begin
            out_last_o = emit_beat_q == EMIT_BEATS-1;
            if (emit_beat_q == 0) begin
                out_bits_o[W-1 -: L] = result_selector_q;
                out_count_o = L;
            end else if (emit_beat_q <= DATA_BEATS) begin
                out_bits_o = external_message_bits_i ^ payload_mask;
                out_count_o = W;
            end else begin
                out_bits_o[W-1 -: R] = result_remainder_q;
                out_bits_o = out_bits_o ^ parity_mask;
                out_count_o = R;
            end
        end
    end

'''
        start = core.index('    // Final selected codeword.')
        end = core.index('    generate', start)
        core = core[:start] + code + core[end:]
        (HERE/f'pbch_mask_stream_{mode}.sv').write_text(stream_mask(mode))
    if search_module:
        core = core.replace('selector_search_block_fwht_grouped #(', f'{search_module} #(')
        core = core.replace('.HIGH_L(FWHT_HIGH_L), .PIPE_GROUP(FWHT_PIPE_GROUP)',f'.HIGH_L(FWHT_HIGH_L), .PIPE_GROUP(FWHT_PIPE_GROUP), .CHUNK({chunk}), .EARLY_EXIT({early}), .FUSE_INPUT({fuse}), .MODULAR6({modular}), .HIST_STYLE({hist_style}), .DIRECT_STAGES({direct_stages})')
    if scan_module:
        core = core.replace('wire [L-1:0] scan_column = G0_COLUMNS[scan_position*L +: L];',
            f'wire [L-1:0] scan_column;\n    {scan_module} label_u (.position_i(scan_position), .label_o(scan_column));')
    if direct_load:
        assert safe and credit == 'skid'
        # Probe scanner and search use the same flag bank. The search LOAD
        # phase accepts every scanner flag directly, eliminating a duplicated
        # pending flag RAM and the subsequent serialized reload.
        core = core.replace('    reg search_result_pending_q;\n    wire search_done;\n    wire search_start_ready;\n', '')
        core = core.replace('    wire scan_start =', '    reg search_result_pending_q;\n    wire search_done, search_start_ready;\n    wire scan_start =')
        core = core.replace('!result_valid_q && !output_active_q;', '!result_valid_q && !output_active_q && search_start_ready &&\n                      !search_done && !search_result_pending_q;', 1)
        begin=core.index('    wire search_start =')
        end=core.index('    wire search_busy;',begin)
        core=core[:begin]+'''    wire search_start = scan_start;
    wire search_add_valid = scan_flag_valid;
    wire [L-1:0] search_add_label = scan_column;
    wire search_add_base_zero = !scan_base_bit;
    wire search_finish = scan_finish;
'''+core[end:]
    if scan_pipe:
        assert scan_module
        core=core.replace(f'{scan_module} label_u (.position_i(scan_position)', f'{scan_module} label_u (.position_i(label_position_q)')
        core=core.replace('    wire [L-1:0] scan_column;', '''    reg [CODE_W-1:0] label_position_q;
    reg label_valid_q, label_base_q, label_finish_q;
    wire [L-1:0] scan_column;''')
        if direct_load:
            core=core.replace('wire search_add_valid = scan_flag_valid;', 'wire search_add_valid = label_valid_q;')
            core=core.replace('wire search_add_base_zero = !scan_base_bit;', 'wire search_add_base_zero = !label_base_q;')
            core=core.replace('wire search_finish = scan_finish;', 'wire search_finish = label_finish_q;')
        else:
            # Align the pending flag bank to the delayed column lookup. Keep
            # the front-end context until its delayed final flag is consumed.
            core=core.replace('if (scan_flag_valid) begin', 'if (label_valid_q) begin')
            core=core.replace('pending_base_zero_q[pending_count_q] <= !scan_base_bit;', 'pending_base_zero_q[pending_count_q] <= !label_base_q;')
            core=core.replace('if (scan_finish) begin', 'if (label_finish_q) begin')
            core=core.replace('if (scan_finish && front_state_q == FRONT_SCAN)', 'if (label_finish_q && front_state_q == FRONT_SCAN)')
        pos=core.index('    // Front end and pending')
        core=core[:pos]+'''    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            label_position_q <= '0;
            label_valid_q <= 1'b0;
            label_base_q <= 1'b0;
            label_finish_q <= 1'b0;
        end else begin
            label_valid_q <= scan_flag_valid;
            label_finish_q <= scan_finish;
            if (scan_flag_valid) begin
                label_position_q <= scan_position;
                label_base_q <= scan_base_bit;
            end
        end
    end

'''+core[pos:]
    if crc_width != 512:
        assert crc_width in (64,128,256)
        phases=512//crc_width
        core=core.replace('    reg [1:0] front_state_q;',f'    reg [{(phases-1).bit_length()-1}:0] crc_phase_q;\n    reg [1:0] front_state_q;')
        core=core.replace('assign data_ready_o = front_state_q == FRONT_CAPTURE;',f'assign data_ready_o = front_state_q == FRONT_CAPTURE && crc_phase_q == {phases-1};')
        core=core.replace('for (lane = 0; lane < W; lane = lane + 1) begin\n            feedback = data_bits_i[W-1-lane]',f'for (lane = 0; lane < {crc_width}; lane = lane + 1) begin\n            feedback = data_bits_i[W-1-crc_phase_q*{crc_width}-lane]')
        old='''                FRONT_CAPTURE: if (data_valid_i && data_ready_o) begin
                    front_remainder_q <= remainder_next;
                    data_seen_q <= data_seen_q + data_count_i;
                    if (data_seen_q + data_count_i == K)
                        front_state_q <= FRONT_WAIT_SCAN;
                end'''
        new=f'''                // The source holds a valid 512-bit beat until ready. Each
                // phase folds one slice into the exact BCH remainder.
                FRONT_CAPTURE: if (data_valid_i) begin
                    front_remainder_q <= remainder_next;
                    if (crc_phase_q == {phases-1}) begin
                        data_seen_q <= data_seen_q + data_count_i;
                        if (data_seen_q + data_count_i == K)
                            front_state_q <= FRONT_WAIT_SCAN;
                    end
                end'''
        assert old in core
        core=core.replace(old,new)
        pos=core.index('    // Front end and pending')
        core=core[:pos]+f'''    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) crc_phase_q <= '0;
        else if (start_i && start_ready_o) crc_phase_q <= '0;
        else if (front_state_q == FRONT_CAPTURE && data_valid_i)
            crc_phase_q <= crc_phase_q + 1'b1;
    end

'''+core[pos:]
    if direct_load:
        core=core.replace('(front_state_q == FRONT_IDLE) && !pending_valid_q;', '(front_state_q == FRONT_IDLE);')
        core=core.replace('assign busy_o = (front_state_q != FRONT_IDLE) || pending_valid_q ||\n                    (load_state_q != LOAD_IDLE) || search_busy ||\n                    result_valid_q || output_active_q;', 'assign busy_o = (front_state_q != FRONT_IDLE) || search_busy || search_done ||\n                    search_result_pending_q || result_valid_q || output_active_q;')
        begin=core.index('    // Pending-valid ownership')
        end=core.index('    // Reuse the search core',begin)
        core=core[:begin]+'''    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            search_remainder_q <= '0;
            search_context_q <= '0;
            search_total_q <= '0;
        end else begin
            if (search_start) begin
                search_remainder_q <= front_remainder_q;
                search_context_q <= front_context_q;
            end
            if (scan_finish) search_total_q <= scan_total;
        end
    end

'''+core[end:]
    if safe and credit == 'skid' and not direct_load:
        core=core.replace('(load_state_q != LOAD_IDLE) || search_busy ||\n                    result_valid_q || output_active_q;', '(load_state_q != LOAD_IDLE) || search_busy || search_done ||\n                    search_result_pending_q || result_valid_q || output_active_q;')
    if mode != 'baseline':
        begin=core.index('// Exact PBCH2 encoder')
        end=core.index('module ',begin)
        core=core[:begin]+'''// Exact frozen PBCH(t=8,l=13) encoder with codeword-stage overlap.
// The unchanged seed62 mask matrix is represented by an exact recurrence.
// Blocked FWHT preserves every candidate score and the smallest-selector tie
// break. EARLY_EXIT, when enabled, stops only at the proven maximum score;
// otherwise the complete 8192-selector space is traversed.
// The upstream multi-context buffer supplies one shared message-read port.
// This generated core is intended only for its fixed-profile wrapper.
'''+core[end:]
        core=core.replace('// One completed result context is enough for the synthesized study points:\n    // their exact-search interval is longer than the 18-beat W=256 emission.\n    // Emission waits for an active probe scan to end.', '// A result slot and the search completion slot absorb output stalls.\n    // W=512 emits ten beats; an active probe scan owns the message port first.')
        if direct_load:
            core=core.replace('    reg load_state_q;\n','')
            core=re.sub(r'^    reg .*?\b(?:pending_\w+|load_index_q)\b[^;]*;\n','',core,flags=re.M)
            core=re.sub(r'^            pending_\w+ <= .*?;\n','',core,flags=re.M)
            core=re.sub(r'^                    pending_\w+ <= .*?;\n','',core,flags=re.M)
            begin=core.index('                    if (scan_flag_valid) begin',core.index('// Front end and pending'))
            end=core.index('                    if (scan_finish) begin',begin)
            core=core[:begin]+core[end:]
            core=re.sub(r'^                        pending_\w+ <= .*?;\n','',core,flags=re.M)
            core=core.replace('// Front end and pending exact-search context.', '// Front end: capture the parent-BCH remainder, then scan flags directly into FWHT.')
        pos=core.index('    localparam')
        core=core[:pos]+'''    // synthesis translate_off
    initial begin
        if (K != 4096 || L != 13 || R != 104 || N != 4213 || W != 512 || MAX_FLAGS != 32)
            $fatal(1, "This generated encoder supports only k4096/t8/l13/W512/max32");
    end
    // synthesis translate_on
'''+core[pos:]
    (HERE/f'{core_name}.sv').write_text(core)
    wrapper = (ROOT/'rtl/generated/study_wrappers/pbch_paper_blockg7_fwht_h7_m32_p128_w512.sv').read_text()
    wrapper = wrapper.replace('pbch_paper_blockg7_fwht_h7_m32_p128_w512',top_name)
    wrapper = wrapper.replace('pbch_sparse_pipeline_enc #(',f'{core_name} #(')
    wrapper = wrapper.replace('.FWHT_HIGH_L(7)', f'.FWHT_HIGH_L({high})').replace('.FWHT_PIPE_GROUP(7)', f'.FWHT_PIPE_GROUP({group})')
    (HERE/f'{top_name}.sv').write_text(wrapper)
    sources = [ROOT/'rtl/pbch'/f for f in ('fht_max_tree.sv','sparse_delta_tree.sv','sparse_signed_sum_tree.sv','selector_search_sparse_gray.sv','selector_search_block_fwht.sv','selector_search_block_fwht_grouped.sv','probe_scan.sv')]
    if mode != 'baseline': sources.append(HERE/f'pbch_mask_stream_{mode}.sv')
    if search_file: sources.append(Path(search_file).resolve())
    if scan_file: sources.append(Path(scan_file).resolve())
    sources += [HERE/f'{core_name}.sv', HERE/f'{top_name}.sv']
    config = dict(name=name, top=top_name, mode=mode, safe=safe, high=high, group=group, credit=credit, chunk=chunk, early=early, fuse=fuse, modular=modular, direct_load=direct_load, scan_pipe=scan_pipe, crc_width=crc_width, hist_style=hist_style, direct_stages=direct_stages, sources=[str(s) for s in sources])
    (HERE/f'{name}.json').write_text(json.dumps(config,indent=2)+'\n')
    (HERE/f'{name}.files.tcl').write_text('set sources [list '+ ' '.join('{'+str(s)+'}' for s in sources)+']\n')
    return config


if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('name')
    p.add_argument('--mode', choices=['baseline','direct','cse'], default='cse')
    p.add_argument('--unsafe-baseline', action='store_true')
    p.add_argument('--search-file')
    p.add_argument('--search-module')
    p.add_argument('--scan-file')
    p.add_argument('--scan-module')
    p.add_argument('--high',type=int,default=7)
    p.add_argument('--group',type=int,default=7)
    p.add_argument('--credit',choices=['slot','skid'],default='skid')
    p.add_argument('--chunk',type=int,default=8)
    p.add_argument('--early',type=int,default=1)
    p.add_argument('--fuse',type=int,default=0)
    p.add_argument('--modular',type=int,default=0)
    p.add_argument('--direct-load',action='store_true')
    p.add_argument('--scan-pipe',action='store_true')
    p.add_argument('--crc-width',type=int,default=512)
    p.add_argument('--hist-style',type=int,choices=(0,1,2,3),default=0)
    p.add_argument('--direct-stages',type=int,default=0)
    a = p.parse_args()
    print(json.dumps(generate(a.name,a.mode,not a.unsafe_baseline,a.search_file,a.search_module,a.high,a.group,a.scan_file,a.scan_module,a.credit,a.chunk,a.early,a.fuse,a.modular,a.direct_load,a.scan_pipe,a.crc_width,a.hist_style,a.direct_stages),indent=2))
