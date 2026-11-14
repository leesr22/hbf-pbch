#!/usr/bin/env python3
"""Generate exact PBCH decoder variants; original matrix and RTL stay intact."""
from pathlib import Path
import collections
import json
import sys

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
from model.ecc import STUDY_PROFILES


def xorshift(x):
    x ^= (x << 13) & 0xffffffff
    x ^= x >> 17
    x ^= (x << 5) & 0xffffffff
    return x


def binary_bm(seq):
    c, b, length, shift = 1, 1, 0, 1
    for n, bit in enumerate(seq):
        d = bit
        for j in range(1, length+1):
            d ^= ((c >> j) & 1) & seq[n-j]
        if d:
            old = c
            c ^= b << shift
            if 2*length <= n:
                length, b, shift = n+1-length, old, 1
            else:
                shift += 1
        else:
            shift += 1
    return length, c


def xor_expr(mask, base, size):
    return ' ^ '.join(f'{base}[{i}]' for i in range(size) if mask >> i & 1) or "1'b0"


def cse_assignments(masks, inputs, prefix, output):
    """Greedy exact GF(2) common-pair extraction, then balanced XOR synthesis."""
    terms = [set(i for i in range(len(inputs)) if m >> i & 1) for m in masks]
    names = list(inputs)
    code = []
    while True:
        pairs = collections.Counter()
        for term in terms:
            ts = sorted(term)
            pairs.update((a,b) for j,a in enumerate(ts) for b in ts[j+1:])
        if not pairs:
            break
        (a,b), count = pairs.most_common(1)[0]
        if count <= 1:
            break
        idx = len(names)
        name = f'{prefix}{idx-len(inputs)}'
        code.append(f'    wire {name} = {names[a]} ^ {names[b]};')
        names.append(name)
        for term in terms:
            if a in term and b in term:
                term.difference_update((a,b))
                term.add(idx)
    for j, term in enumerate(terms):
        expr = ' ^ '.join(names[i] for i in sorted(term)) or "1'b0"
        code.append(f'    assign {output}[{j}] = {expr};')
    return '\n'.join(code)


def main():
    codec = STUDY_PROFILES['pbch_paper']
    state, raw = codec.mask_seed, []
    for _ in range(codec.k):
        state = xorshift(state)
        raw.append(state & ((1<<codec.l)-1))
    length, poly = binary_bm([x&1 for x in raw[:128]])
    assert length == 32
    for n in range(length, len(raw)):
        predicted = 0
        for j in range(1,length+1):
            if poly >> j & 1:
                predicted ^= raw[n-j]
        assert predicted == raw[n]
    masks = codec.mask_columns()
    exceptions = [(i, a^b) for i,(a,b) in enumerate(zip(raw,masks)) if a != b]
    # State contains the next 32 output bits in stream order. Extend to 96.
    linear = [1<<i for i in range(32)]
    for n in range(32,96):
        v = 0
        for j in range(1,33):
            if poly >> j & 1:
                v ^= linear[n-j]
        linear.append(v)
    metadata = {'degree':length, 'recurrence':hex(poly), 'zero_column_exceptions':exceptions}
    (OUT/'recurrence.json').write_text(json.dumps(metadata, indent=2)+'\n')
    for mode in ['direct','cse']:
        module = f'pbch_unmask_rec_{mode}'
        init = '\n'.join(f'    assign initial_state[{i}] = {xor_expr(masks[i], "selector_i",13)};' for i in range(32))
        if mode == 'cse':
            transform = cse_assignments(linear, [f'state_now[{i}]' for i in range(32)], 'x', 'extended')
        else:
            transform = '\n'.join(f'    assign extended[{i}] = {xor_expr(m,"state_now",32)};' for i,m in enumerate(linear))
        correction = []
        for lane in range(64):
            extra = [(i//64,col) for i,col in exceptions if i%64==lane]
            expr = f'extended[{lane}]'
            for beat,col in extra:
                expr += f' ^ ((beat_q == 6\'d{beat}) & ({xor_expr(col,"selector_i",13)}))'
            correction.append(f'    assign out_bits_o[{63-lane}] = in_bits_i[{63-lane}] ^ ((in_count_i > {lane}) & ({expr}));')
        source = f'''`default_nettype none
// Bit-exact implementation of the frozen xorshift-derived mask matrix.
// This changes only its hardware representation, not the selected code.
module {module} (
    input wire clk, reset_n, start_i,
    input wire [12:0] selector_i,
    input wire [63:0] in_bits_i,
    input wire [6:0] in_count_i,
    input wire in_valid_i,
    output wire in_ready_o,
    output wire [63:0] out_bits_o,
    output wire [6:0] out_count_o,
    output wire out_valid_o,
    input wire out_ready_i
);
    reg first_q;
    reg [5:0] beat_q;
    reg [31:0] state_q;
    wire [31:0] initial_state;
    wire [31:0] state_now = first_q ? initial_state : state_q;
    wire [95:0] extended;
    assign in_ready_o = out_ready_i;
    assign out_valid_o = in_valid_i;
    assign out_count_o = in_count_i;
{init}
{transform}
{chr(10).join(correction)}
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            first_q <= 1'b1;
            beat_q <= 0;
            state_q <= 0;
        end else if (start_i) begin
            first_q <= 1'b1;
            beat_q <= 0;
        end else if (in_valid_i && in_ready_o) begin
            first_q <= 1'b0;
            beat_q <= beat_q + 1'b1;
            state_q <= extended[95:64];
        end
    end
endmodule
`default_nettype wire
'''
        (OUT/f'{module}.sv').write_text(source)
        parent = (ROOT/'rtl/pbch/pbch_dec_replay.sv').read_text()
        parent = parent.replace('module pbch_dec_replay #(', f'module pbch_dec_rec_{mode} #(')
        parent = parent.replace('pbch_unmask #(\n        .K(K), .L(L), .W(W), .MASK_COLUMNS(MASK_COLUMNS)\n    ) unmask_u', f'{module} unmask_u')
        (OUT/f'pbch_dec_rec_{mode}.sv').write_text(parent)
        wrapper = (ROOT/'rtl/generated/study_wrappers/pbch_paper_dec_replay_w64.sv').read_text()
        wrapper = wrapper.replace('module pbch_paper_dec_replay_w64', f'module pbch_dec_{mode}')
        wrapper = wrapper.replace('pbch_dec_replay #(', f'pbch_dec_rec_{mode} #(')
        (OUT/f'pbch_dec_{mode}.sv').write_text(wrapper)
    print(metadata)


if __name__ == '__main__':
    main()
