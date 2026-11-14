#!/usr/bin/env python3
"""Factor exact full-beat BCH remainder linear maps with shared XOR pairs."""
from collections import Counter, defaultdict
from itertools import combinations
from pathlib import Path
import argparse
import json
import sys
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT))
from model.ecc import STUDY_PROFILES  # noqa: E402


def remainder_rows(codec, width=512):
    r = codec.r
    state = [1 << index for index in range(r)]
    taps = [index for index in range(r) if codec.generator >> index & 1]
    for lane in range(width):
        feedback = state[-1] ^ (1 << (r + width - 1 - lane))
        state = [0] + state[:-1]
        for index in taps:
            state[index] ^= feedback
    return state


def factor(rows, inputs):
    terms = [set(index for index in range(inputs) if row >> index & 1)
             for row in rows]
    counts = Counter()
    for term in terms:
        counts.update(combinations(sorted(term), 2))
    buckets = defaultdict(set)
    for pair, count in counts.items():
        buckets[count].add(pair)
    users = [set(index for index, term in enumerate(terms) if bit in term)
             for bit in range(inputs)]
    depth = [0] * inputs
    maximum = max(buckets)
    pairs = []

    def adjust(left, right, delta):
        nonlocal maximum
        pair = (left, right) if left < right else (right, left)
        old = counts.get(pair, 0)
        if old:
            buckets[old].remove(pair)
        new = old + delta
        if new:
            counts[pair] = new
            buckets[new].add(pair)
            maximum = max(maximum, new)
        else:
            del counts[pair]

    while True:
        while maximum > 1 and not buckets[maximum]:
            maximum -= 1
        if maximum <= 1:
            break
        left, right = min(buckets[maximum],
                          key=lambda pair: (max(depth[pair[0]], depth[pair[1]]), pair))
        affected = users[left] & users[right]
        assert len(affected) == maximum
        new_index = inputs + len(pairs)
        for index in affected:
            term = terms[index]
            term.remove(left)
            term.remove(right)
            adjust(left, right, -1)
            for other in term:
                adjust(left, other, -1)
                adjust(right, other, -1)
                adjust(new_index, other, 1)
            term.add(new_index)
        users[left].difference_update(affected)
        users[right].difference_update(affected)
        users.append(affected)
        depth.append(1 + max(depth[left], depth[right]))
        pairs.append((left, right))

    # Symbolic proof: each factored output has the identical GF(2) row.
    symbols = [1 << bit for bit in range(inputs)]
    for left, right in pairs:
        symbols.append(symbols[left] ^ symbols[right])
    for expected, term in zip(rows, terms):
        actual = 0
        for node in term:
            actual ^= symbols[node]
        assert actual == expected
    return pairs, [sorted(term) for term in terms], depth


def generate(profile):
    codec = STUDY_PROFILES[profile]
    t, r, width = codec.t, codec.r, 512
    started = time.time()
    rows = remainder_rows(codec, width)
    pairs, outputs, depth = factor(rows, r + width)
    def node(index):
        if index < r:
            return "state_i[%d]" % index
        if index < r + width:
            return "data_i[%d]" % (index - r)
        return "x%d" % (index - r - width)
    lines = ["`default_nettype none",
             "// Exact generated GF(2) factorization; original polynomial and bit order.",
             "module bch_remainder_cse_t%d (" % t,
             "  input wire [%d:0] state_i," % (r - 1),
             "  input wire [511:0] data_i,",
             "  output wire [%d:0] next_o" % (r - 1), ");"]
    for index, (left, right) in enumerate(pairs):
        lines.append("  wire x%d = %s ^ %s;" % (index, node(left), node(right)))
    for bit, output in enumerate(outputs):
        expression = " ^ ".join(node(index) for index in output) or "1'b0"
        lines.append("  assign next_o[%d] = %s;" % (bit, expression))
    lines += ["endmodule", "`default_nettype wire", ""]
    (HERE / ("bch_remainder_cse_t%d.sv" % t)).write_text("\n".join(lines))

    source = (ROOT / "rtl/bch/bch_enc.sv").read_text()
    source = source.replace("module bch_enc #(", "module bch_encoder_cse_t%d #(" % t)
    source = source.replace("parameter integer R = 104", "parameter integer R = %d" % r)
    source = source.replace("parameter integer W = 64", "parameter integer W = 512")
    source = source.replace("reg [R-1:0] remainder_full;", "wire [R-1:0] remainder_full;")
    source = source.replace("reg [R-1:0] remainder_special;", "wire [R-1:0] remainder_special;")
    begin = source.index("    always @* begin\n        remainder_full")
    end = source.index("    always @* begin\n        out_bits_o", begin)
    source = source[:begin] + (
        "    // Study encoders accept full 512-bit payload beats only.\n"
        "    bch_remainder_cse_t%d map_u(.state_i(remainder_q),\n"
        "        .data_i(in_bits_i),.next_o(remainder_full));\n"
        "    assign remainder_special = remainder_q;\n\n" % t) + source[end:]
    (HERE / ("bch_encoder_cse_t%d.sv" % t)).write_text(source)

    xor_count = len(pairs) + sum(max(0, len(row) - 1) for row in outputs)
    meta = dict(profile=profile, t=t, r=r, width=width,
                input_count=r + width, naive_xor_count=sum(bin(x).count("1") - 1 for x in rows),
                factored_xor_count=xor_count, shared_nodes=len(pairs),
                shared_max_depth=max(depth), max_output_terms=max(map(len, outputs)),
                symbolic_equivalence=True, generation_seconds=time.time() - started)
    (HERE / ("cse_t%d.json" % t)).write_text(json.dumps(meta, indent=2) + "\n")

    bench = """`timescale 1ns/1ps
module bch_remainder_cse_t%(t)d_tb;
  reg [%(rm1)d:0] state;
  reg [511:0] data;
  wire [%(rm1)d:0] actual;
  reg [%(rm1)d:0] golden;
  localparam [%(r)d:0] POLY=%(poly)s;
  integer basis, lane;
  bch_remainder_cse_t%(t)d dut(state,data,actual);
  always @* begin
    golden=state;
    for(lane=0;lane<512;lane=lane+1) begin
      if(data[511-lane]^golden[%(rm1)d])
        golden={golden[%(rm2)d:0],1'b0}^POLY[%(rm1)d:0];
      else golden={golden[%(rm2)d:0],1'b0};
    end
  end
  initial begin
    state=0;data=0;#1;
    if(actual!==golden) $fatal(1,"zero mismatch");
    for(basis=0;basis<%(inputs)d;basis=basis+1) begin
      state=0;data=0;
      if(basis<%(r)d)state[basis]=1'b1;
      else data[basis-%(r)d]=1'b1;
      #1;
      if(actual!==golden)$fatal(1,"basis mismatch %%0d",basis);
    end
    $display("PASS BCH t=%(t)d all %(inputs)d state/data basis vectors");
    $finish;
  end
endmodule
""" % dict(t=t, r=r, rm1=r - 1, rm2=r - 2, inputs=r + width,
           poly="%d'h%x" % (r + 1, codec.generator))
    (HERE / ("bch_remainder_cse_t%d_tb.sv" % t)).write_text(bench)
    print(json.dumps(meta, indent=2), flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("profiles", nargs="*", default=["bch_base", "bch_equal_r", "bch_paper"])
    for chosen in parser.parse_args().profiles:
        generate(chosen)
