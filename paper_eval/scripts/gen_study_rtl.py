#!/usr/bin/env python3
"""Generate fixed Fig. 8 wrappers and compile-time BCH/PBCH constants."""

from pathlib import Path
import hashlib
import json
import random
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from model.ecc import M, PRIMITIVE_POLY, PBCH, STUDY_PROFILES, gf_pow  # noqa: E402


WIDTHS = (32, 64, 128, 256, 512)
FHT_PARALLEL = (1, 2, 4, 8, 16, 32)
XOR_BANK_BUTTERFLIES = (32, 64, 128, 256)
SPARSE_GRAY_CONFIGS = ((32, 8), (32, 16), (32, 32), (32, 64),
                       (48, 16), (48, 32), (48, 64),
                       (80, 16), (80, 32))
SPARSE_EXTERNAL_CONFIGS = ((32, 32), (32, 64), (32, 128), (32, 256),
                           (48, 16), (48, 32), (48, 64), (48, 128))
SPARSE_EXTERNAL_WIDTH_SWEEP = ((32, 64), (32, 128),
                               (48, 64), (48, 128))
SPARSE_PIPELINE_CONFIGS = ((128, 32, 64), (128, 32, 128),
                           (256, 32, 128))


def literal(width, value):
    digits = (width + 3) // 4
    return "%d'h%0*x" % (width, digits, value)


def pack(values, width):
    result = 0
    for index, value in enumerate(values):
        result |= value << (index * width)
    return result


def syndrome_factors(t, width, count):
    state = [gf_pow(2, (2 * odd + 1) * count) for odd in range(t)]
    inputs = []
    for odd in range(t):
        exponent = 2 * odd + 1
        for lane in range(width):
            inputs.append(gf_pow(2, exponent * (count - 1 - lane))
                          if lane < count else 0)
    return state, inputs


def chien_factors(t, width, count):
    return [gf_pow(2, coefficient * count) for coefficient in range(t + 1)]


def decoder_constants(k, n, t, width, partial_a, partial_b):
    full_state, full_input = syndrome_factors(t, width, width)
    a_state, a_input = syndrome_factors(t, width, partial_a)
    b_state, b_input = syndrome_factors(t, width, partial_b)
    init = [gf_pow(2, (-(n - 1) * j) % ((1 << M) - 1))
            for j in range(t + 1)]
    lane = [gf_pow(2, coefficient * lane_index)
            for lane_index in range(width) for coefficient in range(t + 1)]
    return {
        "SYN_FULL_STATE": literal(t * M, pack(full_state, M)),
        "SYN_FULL_INPUT": literal(t * width * M, pack(full_input, M)),
        "SYN_PARTIAL_A_STATE": literal(t * M, pack(a_state, M)),
        "SYN_PARTIAL_A_INPUT": literal(t * width * M, pack(a_input, M)),
        "SYN_PARTIAL_B_STATE": literal(t * M, pack(b_state, M)),
        "SYN_PARTIAL_B_INPUT": literal(t * width * M, pack(b_input, M)),
        "CHIEN_INIT": literal((t + 1) * M, pack(init, M)),
        "CHIEN_LANE": literal((t + 1) * width * M, pack(lane, M)),
        "CHIEN_ADVANCE_FULL": literal(
            (t + 1) * M, pack(chien_factors(t, width, width), M)),
        "CHIEN_ADVANCE_PARTIAL_A": literal(
            (t + 1) * M, pack(chien_factors(t, width, partial_a), M)),
        "CHIEN_ADVANCE_PARTIAL_B": literal(
            (t + 1) * M, pack(chien_factors(t, width, partial_b), M)),
    }


def parameter_text(constants):
    return ",\n        ".join(".%s(%s)" % item for item in constants.items())


def bch_encoder_wrapper(name, codec, width):
    return f"""
module {name}_enc_w{width} (
    input wire clk,input wire reset_n,input wire start_i,output wire start_ready_o,
    input wire [{width-1}:0] in_bits_i,input wire [$clog2({width}+1)-1:0] in_count_i,
    input wire in_valid_i,output wire in_ready_o,
    output wire [{width-1}:0] out_bits_o,output wire [$clog2({width}+1)-1:0] out_count_o,
    output wire out_valid_o,input wire out_ready_i,output wire out_last_o,
    output wire done_o,output wire busy_o
);
    bch_enc #(.K({codec.k}),.R({codec.r}),.W({width}),
        .GENERATOR({literal(codec.r+1,codec.generator)})) core (.*);
endmodule
"""


def bch_decoder_wrapper(name, codec, width, buffered, lanes_override=None):
    suffix = "buffered" if buffered else "replay"
    top = f"{name}_dec_{suffix}_w{width}"
    module = "bch_dec_buffered" if buffered else "bch_dec"
    lanes = (2 if codec.t >= 28 else 1) if lanes_override is None \
        else lanes_override
    partial_b = codec.r % width
    c = decoder_constants(codec.k, codec.n, codec.t, width, 0, partial_b)
    replay_ports = "" if buffered else f"""
    output wire replay_req_o,input wire [{width-1}:0] replay_bits_i,
    input wire [$clog2({width}+1)-1:0] replay_count_i,input wire replay_valid_i,
    output wire replay_ready_o,"""
    replay_connect = "" if buffered else """
        .replay_req_o(replay_req_o),.replay_bits_i(replay_bits_i),
        .replay_count_i(replay_count_i),.replay_valid_i(replay_valid_i),
        .replay_ready_o(replay_ready_o),"""
    buffer_param = ",.BUFFER_DEPTH(4)" if buffered else ""
    return f"""
module {top} (
    input wire clk,input wire reset_n,input wire start_i,output wire start_ready_o,
    input wire [{width-1}:0] code_bits_i,input wire [$clog2({width}+1)-1:0] code_count_i,
    input wire code_valid_i,output wire code_ready_o,{replay_ports}
    output wire [{width-1}:0] info_bits_o,output wire [$clog2({width}+1)-1:0] info_count_o,
    output wire info_valid_o,input wire info_ready_i,output wire done_o,
    output wire success_o,output wire [$clog2({codec.t}+1)-1:0] error_count_o,
    output wire busy_o
);
    {module} #(.M(13),.T({codec.t}),.K({codec.k}),.N({codec.n}),.W({width}),
        .BM_LANES({lanes}){buffer_param},.PARTIAL_A(0),.PARTIAL_B({partial_b}),
        .PRIMITIVE_POLYNOMIAL(14'h201b),
        {parameter_text(c)}) core (
        .clk(clk),.reset_n(reset_n),.start_i(start_i),.start_ready_o(start_ready_o),
        .code_bits_i(code_bits_i),.code_count_i(code_count_i),
        .code_valid_i(code_valid_i),.code_ready_o(code_ready_o),{replay_connect}
        .info_bits_o(info_bits_o),.info_count_o(info_count_o),
        .info_valid_o(info_valid_o),.info_ready_i(info_ready_i),.done_o(done_o),
        .success_o(success_o),.error_count_o(error_count_o),.busy_o(busy_o));
endmodule
"""


def pbch_encoder_wrapper(codec, width, parallel, g0_literal, g0_beat_literal):
    return f"""
module pbch_fht_enc_w{width}_p{parallel} (
    input wire clk,input wire reset_n,input wire start_i,output wire start_ready_o,
    input wire [{width-1}:0] data_bits_i,input wire [$clog2({width}+1)-1:0] data_count_i,
    input wire data_valid_i,output wire data_ready_o,
    input wire [{width-1}:0] probe_bits_i,input wire [$clog2({width}+1)-1:0] probe_count_i,
    input wire probe_valid_i,output wire probe_ready_o,
    output wire [$clog2(4096/{width}+1)-1:0] message_addr_o,
    input wire [{width-1}:0] external_message_bits_i,
    output wire [{width-1}:0] out_bits_o,output wire [$clog2({width}+1)-1:0] out_count_o,
    output wire out_valid_o,input wire out_ready_i,output wire out_last_o,
    output wire [12:0] selector_o,output wire [$clog2({codec.n}+1)-1:0] mask_failures_o,
    output wire flag_overflow_o,output wire done_o,output wire busy_o
);
    pbch_fht_enc #(.K(4096),.L(13),.R({codec.parent.r}),.W({width}),
        .FHT_PARALLEL({parallel}),
        .BCH_GENERATOR({literal(codec.parent.r+1,codec.parent.generator)}),
        .G0_COLUMNS({g0_literal}),
        .G0_BEAT_COLUMNS({g0_beat_literal})) core (.*);
endmodule
"""


def pbch_xor_banked_encoder_wrapper(codec, width, butterflies,
                                    g0_literal, g0_beat_literal):
    top = f"pbch_fht_enc_xb{butterflies}_w{width}"
    return f"""
module {top} (
    input wire clk,input wire reset_n,input wire start_i,output wire start_ready_o,
    input wire [{width-1}:0] data_bits_i,input wire [$clog2({width}+1)-1:0] data_count_i,
    input wire data_valid_i,output wire data_ready_o,
    input wire [{width-1}:0] probe_bits_i,input wire [$clog2({width}+1)-1:0] probe_count_i,
    input wire probe_valid_i,output wire probe_ready_o,
    output wire [$clog2(4096/{width}+1)-1:0] message_addr_o,
    input wire [{width-1}:0] external_message_bits_i,
    output wire [{width-1}:0] out_bits_o,output wire [$clog2({width}+1)-1:0] out_count_o,
    output wire out_valid_o,input wire out_ready_i,output wire out_last_o,
    output wire [12:0] selector_o,output wire [$clog2({codec.n}+1)-1:0] mask_failures_o,
    output wire flag_overflow_o,output wire done_o,output wire busy_o
);
    pbch_fht_enc #(.K(4096),.L(13),.R({codec.parent.r}),.W({width}),
        .FHT_ARCH(1),.FHT_PARALLEL({butterflies}),
        .BCH_GENERATOR({literal(codec.parent.r+1,codec.parent.generator)}),
        .G0_COLUMNS({g0_literal}),
        .G0_BEAT_COLUMNS({g0_beat_literal})) core (.*);
endmodule
"""


def pbch_sparse_gray_encoder_wrapper(codec, width, max_flags, lanes,
                                     g0_literal, g0_beat_literal,
                                     external=False):
    prefix = "pbch_sparse_ext" if external else "pbch_sparse"
    top = f"{prefix}_m{max_flags}_p{lanes}_w{width}"
    local_message = 0 if external else 1
    return f"""
module {top} (
    input wire clk,input wire reset_n,input wire start_i,output wire start_ready_o,
    input wire [{width-1}:0] data_bits_i,input wire [$clog2({width}+1)-1:0] data_count_i,
    input wire data_valid_i,output wire data_ready_o,
    input wire [{width-1}:0] probe_bits_i,input wire [$clog2({width}+1)-1:0] probe_count_i,
    input wire probe_valid_i,output wire probe_ready_o,
    output wire [$clog2(4096/{width}+1)-1:0] message_addr_o,
    input wire [{width-1}:0] external_message_bits_i,
    output wire [{width-1}:0] out_bits_o,output wire [$clog2({width}+1)-1:0] out_count_o,
    output wire out_valid_o,input wire out_ready_i,output wire out_last_o,
    output wire [12:0] selector_o,output wire [$clog2({codec.n}+1)-1:0] mask_failures_o,
    output wire flag_overflow_o,output wire done_o,output wire busy_o
);
    pbch_fht_enc #(.K(4096),.L(13),.R({codec.parent.r}),.W({width}),
        .FHT_ARCH(2),.FHT_PARALLEL({lanes}),.SPARSE_MAX_FLAGS({max_flags}),
        .LOCAL_MESSAGE({local_message}),
        .BCH_GENERATOR({literal(codec.parent.r+1,codec.parent.generator)}),
        .G0_COLUMNS({g0_literal}),
        .G0_BEAT_COLUMNS({g0_beat_literal})) core (.*);
endmodule
"""


def pbch_sparse_pipeline_encoder_wrapper(codec, width, max_flags, lanes,
                                         g0_literal, g0_beat_literal,
                                         search_impl=0, fwht_high_l=7,
                                         fwht_pipe_group=1,
                                         profile_prefix=""):
    if search_impl == 2:
        prefix = f"pbch_blockg{fwht_pipe_group}_fwht_h{fwht_high_l}"
    elif search_impl == 1:
        prefix = f"pbch_block_fwht_h{fwht_high_l}"
    else:
        prefix = "pbch_sparse_pipe"
    if profile_prefix:
        prefix = f"{profile_prefix}_{prefix[5:]}"
    top = f"{prefix}_m{max_flags}_p{lanes}_w{width}"
    return f"""
module {top} (
    input wire clk,input wire reset_n,input wire start_i,
    input wire [2:0] context_i,output wire start_ready_o,
    input wire [{width-1}:0] data_bits_i,input wire [$clog2({width}+1)-1:0] data_count_i,
    input wire data_valid_i,output wire data_ready_o,
    input wire [{width-1}:0] probe_bits_i,input wire [$clog2({width}+1)-1:0] probe_count_i,
    input wire probe_valid_i,output wire probe_ready_o,
    output wire [2:0] message_context_o,
    output wire [$clog2(4096/{width}+1)-1:0] message_addr_o,
    input wire [{width-1}:0] external_message_bits_i,
    output wire [{width-1}:0] out_bits_o,output wire [$clog2({width}+1)-1:0] out_count_o,
    output wire out_valid_o,input wire out_ready_i,output wire out_last_o,
    output wire [2:0] result_context_o,output wire [12:0] selector_o,
    output wire [$clog2({codec.n}+1)-1:0] mask_failures_o,
    output wire flag_overflow_o,output wire done_o,output wire busy_o
);
    pbch_sparse_pipeline_enc #(
        .K(4096),.L(13),.R({codec.parent.r}),.W({width}),
        .LANES({lanes}),.MAX_FLAGS({max_flags}),.CONTEXT_W(3),
        .SEARCH_IMPL({search_impl}),.FWHT_HIGH_L({fwht_high_l}),
        .FWHT_PIPE_GROUP({fwht_pipe_group}),
        .BCH_GENERATOR({literal(codec.parent.r+1,codec.parent.generator)}),
        .G0_COLUMNS({g0_literal}),
        .G0_BEAT_COLUMNS({g0_beat_literal})) core (.*);
endmodule
"""


def pbch_decoder_wrapper(codec, width, buffered, mask_literal,
                         profile_name="pbch_fht"):
    suffix = "buffered" if buffered else "replay"
    module = "pbch_dec_buffered" if buffered else "pbch_dec_replay"
    t, n, r = codec.t, codec.n, codec.parent.r
    c = decoder_constants(codec.k + codec.l, n, t, width, codec.l, r % width)
    replay_ports = "" if buffered else f"""
    output wire replay_req_o,input wire [{width-1}:0] replay_bits_i,
    input wire [$clog2({width}+1)-1:0] replay_count_i,input wire replay_valid_i,
    output wire replay_ready_o,"""
    replay_connect = "" if buffered else """
        .replay_req_o(replay_req_o),.replay_bits_i(replay_bits_i),
        .replay_count_i(replay_count_i),.replay_valid_i(replay_valid_i),
        .replay_ready_o(replay_ready_o),"""
    buffer_param = ",.BUFFER_DEPTH(4)" if buffered else ""
    return f"""
module {profile_name}_dec_{suffix}_w{width} (
    input wire clk,input wire reset_n,input wire start_i,output wire start_ready_o,
    input wire [{width-1}:0] code_bits_i,input wire [$clog2({width}+1)-1:0] code_count_i,
    input wire code_valid_i,output wire code_ready_o,{replay_ports}
    output wire [{width-1}:0] info_bits_o,output wire [$clog2({width}+1)-1:0] info_count_o,
    output wire info_valid_o,input wire info_ready_i,output wire [12:0] selector_o,
    output wire done_o,output wire success_o,
    output wire [$clog2({t}+1)-1:0] error_count_o,output wire busy_o
);
    {module} #(.M(13),.T({t}),.L(13),.K(4096),.R({r}),.W({width}){buffer_param},
        .BM_LANES(1),.PRIMITIVE_POLYNOMIAL(14'h201b),
        {parameter_text(c)},.MASK_COLUMNS({mask_literal})) core (
        .clk(clk),.reset_n(reset_n),.start_i(start_i),.start_ready_o(start_ready_o),
        .code_bits_i(code_bits_i),.code_count_i(code_count_i),
        .code_valid_i(code_valid_i),.code_ready_o(code_ready_o),{replay_connect}
        .info_bits_o(info_bits_o),.info_count_o(info_count_o),
        .info_valid_o(info_valid_o),.info_ready_i(info_ready_i),
        .selector_o(selector_o),.done_o(done_o),.success_o(success_o),
        .error_count_o(error_count_o),.busy_o(busy_o));
endmodule
"""


def main():
    wrapper_dir = ROOT / "rtl" / "generated" / "study_wrappers"
    wrapper_dir.mkdir(parents=True, exist_ok=True)
    pbch = STUDY_PROFILES["pbch_fht"]
    influence = pbch.influence_columns()
    masks = pbch.mask_columns()
    g0_packed = pack(influence, pbch.l)
    mask_packed = pack(masks, pbch.l)
    g0_literal = literal(pbch.n * pbch.l, g0_packed)
    mask_literal = literal(pbch.k * pbch.l, mask_packed)

    def emit(name, body):
        (wrapper_dir / (name + ".sv")).write_text(
            "`default_nettype none\n" + body + "`default_nettype wire\n")

    for name in ("bch_base", "bch_equal_r", "bch_target", "bch_paper"):
        codec = STUDY_PROFILES[name]
        for width in WIDTHS:
            emit(f"{name}_enc_w{width}",
                 bch_encoder_wrapper(name, codec, width))
            emit(f"{name}_dec_replay_w{width}",
                 bch_decoder_wrapper(name, codec, width, False))
            emit(f"{name}_dec_buffered_w{width}",
                 bch_decoder_wrapper(name, codec, width, True))
    bm2 = STUDY_PROFILES["bch_paper_bm2"]
    for width in WIDTHS:
        emit(f"bch_paper_bm2_dec_replay_w{width}",
             bch_decoder_wrapper("bch_paper_bm2", bm2, width, False, 2))
        emit(f"bch_paper_bm2_dec_buffered_w{width}",
             bch_decoder_wrapper("bch_paper_bm2", bm2, width, True, 2))
    for width in WIDTHS:
        beat_columns = list(influence[:pbch.l]) + [0] * (width - pbch.l)
        for start in range(pbch.l, pbch.l + pbch.k, width):
            beat_columns.extend(influence[start:start + width])
        parity_start = pbch.l + pbch.k
        for start in range(parity_start, pbch.n, width):
            chunk = list(influence[start:min(start + width, pbch.n)])
            beat_columns.extend(chunk + [0] * (width - len(chunk)))
        expected_beats = 1 + pbch.k // width + (pbch.parent.r + width - 1) // width
        assert len(beat_columns) == expected_beats * width
        g0_beat_literal = literal(
            len(beat_columns) * pbch.l, pack(beat_columns, pbch.l))
        for parallel in FHT_PARALLEL:
            emit(f"pbch_fht_enc_w{width}_p{parallel}",
                 pbch_encoder_wrapper(
                     pbch, width, parallel, g0_literal, g0_beat_literal))
        if width == 64:
            for butterflies in XOR_BANK_BUTTERFLIES:
                emit(f"pbch_fht_enc_xb{butterflies}_w{width}",
                     pbch_xor_banked_encoder_wrapper(
                         pbch, width, butterflies,
                         g0_literal, g0_beat_literal))
            for max_flags, lanes in SPARSE_GRAY_CONFIGS:
                emit(f"pbch_sparse_m{max_flags}_p{lanes}_w{width}",
                     pbch_sparse_gray_encoder_wrapper(
                         pbch, width, max_flags, lanes,
                         g0_literal, g0_beat_literal))
            for max_flags, lanes in SPARSE_EXTERNAL_CONFIGS:
                emit(f"pbch_sparse_ext_m{max_flags}_p{lanes}_w{width}",
                     pbch_sparse_gray_encoder_wrapper(
                         pbch, width, max_flags, lanes,
                         g0_literal, g0_beat_literal, external=True))
        else:
            for max_flags, lanes in SPARSE_EXTERNAL_WIDTH_SWEEP:
                emit(f"pbch_sparse_ext_m{max_flags}_p{lanes}_w{width}",
                     pbch_sparse_gray_encoder_wrapper(
                         pbch, width, max_flags, lanes,
                         g0_literal, g0_beat_literal, external=True))
        for pipeline_width, max_flags, lanes in SPARSE_PIPELINE_CONFIGS:
            if width == pipeline_width:
                emit(f"pbch_sparse_pipe_m{max_flags}_p{lanes}_w{width}",
                     pbch_sparse_pipeline_encoder_wrapper(
                         pbch, width, max_flags, lanes,
                         g0_literal, g0_beat_literal))
                for fwht_high_l in (5, 6, 7, 8, 9):
                    emit(f"pbch_block_fwht_h{fwht_high_l}_m{max_flags}_p{lanes}_w{width}",
                         pbch_sparse_pipeline_encoder_wrapper(
                             pbch, width, max_flags, lanes,
                             g0_literal, g0_beat_literal,
                             search_impl=1, fwht_high_l=fwht_high_l))
                for fwht_high_l, pipe_group in (
                        (6, 6),
                        (7, 2), (7, 3), (7, 4), (7, 7),
                        (8, 2), (8, 3), (8, 8),
                        (9, 2), (9, 3), (9, 9)):
                    emit(
                        f"pbch_blockg{pipe_group}_fwht_h{fwht_high_l}_m{max_flags}_p{lanes}_w{width}",
                        pbch_sparse_pipeline_encoder_wrapper(
                            pbch, width, max_flags, lanes,
                            g0_literal, g0_beat_literal,
                            search_impl=2, fwht_high_l=fwht_high_l,
                            fwht_pipe_group=pipe_group))
        emit(f"pbch_fht_dec_replay_w{width}",
             pbch_decoder_wrapper(pbch, width, False, mask_literal))
        emit(f"pbch_fht_dec_buffered_w{width}",
             pbch_decoder_wrapper(pbch, width, True, mask_literal))

    # Emit the paper PBCH point under distinct top names.  Only the selected
    # exact grouped-FWHT encoder is needed; both decoder storage variants are
    # emitted for the normal width sweep and verification flow.
    paper_pbch = STUDY_PROFILES["pbch_paper"]
    paper_influence = paper_pbch.influence_columns()
    paper_masks = paper_pbch.mask_columns()
    paper_g0_literal = literal(
        paper_pbch.n * paper_pbch.l, pack(paper_influence, paper_pbch.l))
    paper_mask_literal = literal(
        paper_pbch.k * paper_pbch.l, pack(paper_masks, paper_pbch.l))
    # Keep the paper search microarchitecture fixed while allowing the stream
    # width to be matched to the BCH comparison.  Width changes only message
    # capture/replay; the exact 7+6 blocked FWHT and its 32-flag bound remain
    # identical.
    for paper_width in (256, 512):
        paper_beat_columns = list(paper_influence[:paper_pbch.l])
        paper_beat_columns += [0] * (paper_width - paper_pbch.l)
        for start in range(paper_pbch.l,
                           paper_pbch.l + paper_pbch.k, paper_width):
            paper_beat_columns.extend(
                paper_influence[start:start + paper_width])
        paper_parity_start = paper_pbch.l + paper_pbch.k
        for start in range(paper_parity_start, paper_pbch.n, paper_width):
            chunk = list(paper_influence[
                start:min(start + paper_width, paper_pbch.n)])
            paper_beat_columns.extend(
                chunk + [0] * (paper_width - len(chunk)))
        paper_g0_beat_literal = literal(
            len(paper_beat_columns) * paper_pbch.l,
            pack(paper_beat_columns, paper_pbch.l))
        paper_top = (
            f"pbch_paper_blockg7_fwht_h7_m32_p128_w{paper_width}")
        emit(paper_top, pbch_sparse_pipeline_encoder_wrapper(
            paper_pbch, paper_width, 32, 128,
            paper_g0_literal, paper_g0_beat_literal,
            search_impl=2, fwht_high_l=7, fwht_pipe_group=7,
            profile_prefix="pbch_paper"))
    for width in WIDTHS:
        emit(f"pbch_paper_dec_replay_w{width}",
             pbch_decoder_wrapper(paper_pbch, width, False,
                                  paper_mask_literal, "pbch_paper"))
        emit(f"pbch_paper_dec_buffered_w{width}",
             pbch_decoder_wrapper(paper_pbch, width, True,
                                  paper_mask_literal, "pbch_paper"))
    packed_bytes = g0_packed.to_bytes((pbch.n * pbch.l + 7) // 8, "little")
    counts = {}
    for column in influence:
        counts[column] = counts.get(column, 0) + 1
    manifest = {
        "profiles": {
            name: {"k": c.k, "t": c.t, "r": c.r, "n": c.n}
            if not isinstance(c, PBCH) else {
                "k": c.k, "t": c.t, "l": c.l, "r": c.parent.r, "n": c.n}
            for name, c in STUDY_PROFILES.items()
        },
        "widths": WIDTHS,
        "fht_parallel": FHT_PARALLEL,
        "xor_bank_butterflies": XOR_BANK_BUTTERFLIES,
        "sparse_gray_configs": SPARSE_GRAY_CONFIGS,
        "sparse_external_configs": SPARSE_EXTERNAL_CONFIGS,
        "sparse_external_width_sweep": SPARSE_EXTERNAL_WIDTH_SWEEP,
        "sparse_pipeline_configs": SPARSE_PIPELINE_CONFIGS,
        "primitive_polynomial": hex(PRIMITIVE_POLY),
        "g0_sha256": hashlib.sha256(packed_bytes).hexdigest(),
        "g0_unique_columns": len(counts),
        "g0_zero_columns": counts.get(0, 0),
        "g0_max_column_multiplicity": max(counts.values()),
    }
    (ROOT / "rtl" / "generated" / "study_manifest.json").write_text(
        json.dumps(manifest, indent=2) + "\n")

    # Compact deterministic end-to-end encoder vectors for VCS.
    vector_dir = ROOT / "vectors" / "study"
    vector_dir.mkdir(parents=True, exist_ok=True)
    def write_pbch_encoder_vectors(codec, destination, seed):
        destination.mkdir(parents=True, exist_ok=True)
        rng = random.Random(seed)
        vector_rows = []
        for defects in (0, 1, 9, 32, 48, 80):
            message = rng.getrandbits(codec.k)
            positions = tuple(sorted(rng.sample(range(codec.n), defects)))
            probe = sum(
                1 << (codec.n - 1 - position) for position in positions)
            selector, failures = codec.fht_selector(message, positions)
            word = codec.encode(message, selector)
            vector_rows.append((message, probe, word, selector, failures))
        formats = (("message.hex", codec.k, 0),
                   ("probe.hex", codec.n, 1),
                   ("codeword.hex", codec.n, 2))
        for filename, bits, field in formats:
            digits = (bits + 3) // 4
            (destination / filename).write_text("".join(
                ("%0*x\n" % (digits, row[field])) for row in vector_rows))
        (destination / "selector.hex").write_text("".join(
            "%04x\n" % row[3] for row in vector_rows))
        (destination / "failures.hex").write_text("".join(
            "%04x\n" % row[4] for row in vector_rows))

    write_pbch_encoder_vectors(pbch, vector_dir, 0xF17B)
    write_pbch_encoder_vectors(
        paper_pbch, vector_dir / "pbch_paper_encoder", 0xFA27)

    def segments(value, total_bits, counts, width):
        rows = []
        seen = 0
        for count in counts:
            part = (value >> (total_bits - seen - count)) & ((1 << count) - 1)
            rows.append(part << (width - count))
            seen += count
        assert seen == total_bits
        return rows

    # One exactly-t-error decoder vector for every width and profile.
    for profile_name, codec in STUDY_PROFILES.items():
        for width in WIDTHS:
            local_rng = random.Random((sum(map(ord, profile_name)) << 12) + width)
            if isinstance(codec, PBCH):
                message = local_rng.getrandbits(codec.k)
                probe_positions = tuple(sorted(local_rng.sample(range(codec.n), 17)))
                selector, _ = codec.fht_selector(message, probe_positions)
                word = codec.encode(message, selector)
                r = codec.parent.r
                counts = [codec.l] + [width] * (codec.k // width)
                counts += [width] * (r // width)
                if r % width:
                    counts.append(r % width)
                t = codec.t
                k = codec.k
            else:
                message = local_rng.getrandbits(codec.k)
                selector = 0
                word = codec.encode(message)
                counts = [width] * (codec.k // width)
                counts += [width] * (codec.r // width)
                if codec.r % width:
                    counts.append(codec.r % width)
                t = codec.t
                k = codec.k
            error_positions = local_rng.sample(range(codec.n), t)
            received = word
            for polynomial_position in error_positions:
                received ^= 1 << polynomial_position
            directory = vector_dir / profile_name / ("w%d" % width)
            directory.mkdir(parents=True, exist_ok=True)
            info_counts = [width] * (k // width)
            if k % width:
                info_counts.append(k % width)
            digits = (width + 3) // 4
            (directory / "message.mem").write_text("".join(
                "%0*x\n" % (digits, row)
                for row in segments(message, k, info_counts, width)))
            (directory / "received.mem").write_text("".join(
                "%0*x\n" % (digits, row)
                for row in segments(received, codec.n, counts, width)))
            (directory / "codeword.mem").write_text("".join(
                "%0*x\n" % (digits, row)
                for row in segments(word, codec.n, counts, width)))
            (directory / "manifest.json").write_text(json.dumps({
                "profile": profile_name, "width": width, "k": k,
                "n": codec.n, "t": t,
                "l": codec.l if isinstance(codec, PBCH) else 0,
                "r": r if isinstance(codec, PBCH) else codec.r,
                "selector": selector, "counts": counts,
                "error_positions": error_positions,
            }, indent=2) + "\n")

            # Five distinct frames exercise inter-frame ordering and stage
            # overlap.  The weights deliberately mix zero and nonzero errors.
            pipeline_messages = []
            pipeline_received = []
            pipeline_manifest = []
            weights = (0, 1, max(2, t // 2), t - 1, t)
            for frame, weight in enumerate(weights):
                frame_message = local_rng.getrandbits(k)
                if isinstance(codec, PBCH):
                    frame_probe = tuple(sorted(
                        local_rng.sample(range(codec.n), 7 + 2 * frame)))
                    frame_selector, _ = codec.fht_selector(
                        frame_message, frame_probe)
                    frame_word = codec.encode(frame_message, frame_selector)
                else:
                    frame_selector = 0
                    frame_word = codec.encode(frame_message)
                frame_errors = local_rng.sample(range(codec.n), weight)
                frame_received = frame_word
                for polynomial_position in frame_errors:
                    frame_received ^= 1 << polynomial_position
                pipeline_messages.extend(
                    segments(frame_message, k, info_counts, width))
                pipeline_received.extend(
                    segments(frame_received, codec.n, counts, width))
                pipeline_manifest.append({
                    "frame": frame,
                    "error_weight": weight,
                    "error_positions": frame_errors,
                    "selector": frame_selector,
                })

            (directory / "pipeline_message.mem").write_text("".join(
                "%0*x\n" % (digits, row) for row in pipeline_messages))
            (directory / "pipeline_received.mem").write_text("".join(
                "%0*x\n" % (digits, row) for row in pipeline_received))
            (directory / "pipeline_error_count.mem").write_text("".join(
                "%x\n" % weight for weight in weights))
            (directory / "pipeline_manifest.json").write_text(json.dumps({
                "profile": profile_name,
                "width": width,
                "frames": pipeline_manifest,
            }, indent=2) + "\n")
    print(wrapper_dir)


if __name__ == "__main__":
    main()
