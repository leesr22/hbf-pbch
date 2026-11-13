"""Checks for the Fig. 8 BCH/PBCH hardware profiles."""

import hashlib
import json
import random
from pathlib import Path

from model.ecc import STUDY_PROFILES


ROOT = Path(__file__).resolve().parents[1]


def test_study_code_lengths():
    assert STUDY_PROFILES["bch_base"].n == 4200
    assert STUDY_PROFILES["bch_target"].n == 4486
    assert STUDY_PROFILES["pbch_fht"].n == 4278
    assert STUDY_PROFILES["pbch_fht"].parent.r == 169


def test_fht_matches_direct_exhaustive_search():
    codec = STUDY_PROFILES["pbch_fht"]
    rng = random.Random(0xF17)

    cases = [(), (0,), (codec.n - 1,)]
    cases += [tuple(sorted(rng.sample(range(codec.n), count)))
              for count in (2, 5, 9, 17, 32)]

    for positions in cases:
        message = rng.getrandbits(codec.k)
        assert codec.fht_selector(message, positions) == \
            codec.exact_selector(message, positions)


def test_selected_word_has_reported_failure_count():
    codec = STUDY_PROFILES["pbch_fht"]
    rng = random.Random(0x13)
    message = rng.getrandbits(codec.k)
    positions = tuple(sorted(rng.sample(range(codec.n), 31)))
    selector, failures = codec.fht_selector(message, positions)
    word = codec.encode(message, selector)
    observed = sum((word >> (codec.n - 1 - position)) & 1
                   for position in positions)
    assert observed == failures


def test_study_pbch_is_a_valid_nested_code_and_recovers_message():
    """The fixed non-cyclic mask rows must still be parent-BCH codewords."""
    codec = STUDY_PROFILES["pbch_fht"]
    rng = random.Random(0xB13)

    for _ in range(3):
        message = rng.getrandbits(codec.k)
        selector = rng.randrange(1 << codec.l)
        word = codec.encode(message, selector)
        recovered, recovered_selector = codec.recover(word)

        assert not any(codec.parent.syndromes(word))
        assert recovered == message
        assert recovered_selector == selector


def test_frozen_g0_matches_manifest():
    codec = STUDY_PROFILES["pbch_fht"]
    columns = codec.influence_columns()
    packed = sum(column << (index * codec.l)
                 for index, column in enumerate(columns))
    payload = packed.to_bytes((codec.n * codec.l + 7) // 8, "little")
    manifest = json.loads(
        (ROOT / "rtl/generated/study_manifest.json").read_text())

    assert hashlib.sha256(payload).hexdigest() == manifest["g0_sha256"]
    assert len(set(columns)) == manifest["g0_unique_columns"]
    assert columns.count(0) == manifest["g0_zero_columns"]
