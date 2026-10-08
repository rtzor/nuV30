#!/usr/bin/env python3
"""Synthetic offline falsifiers. These tests make no chip/RTL-match claim."""
import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

import native_buslock_evidence as evidence


def manifest():
    return {'tool': 'tf0f_cell run', 'use_core': False, 'div': 8,
            'ts': '2026-08-11T22:55:11Z', 'images': {'v_lock_a0': 'a' * 64},
            'flash': {'tail': {'ts': '2026-08-11T13:49:17Z', 'verify': 'OK',
                               'sha256': 'b' * 64, 'sof_path': 'fixture.sof',
                               'git_describe': 'synthetic-fixture'}}}


class Falsifiers(unittest.TestCase):
    def setUp(self):
        self.rows = [{'idx': i, 'lock_n': pin, 'reset': int(i == 0)}
                     for i, pin in enumerate((1, 0, 0, 1))]
        self.spec = next(s for s in evidence.expected_cells() if s['cell'] == 'v_lock_w0_a0')
        self.words = ['0004000000000000', '0000000000000000']
        self.table = {'cell': 'v_lock_w0_a0', 'probe': 'v_lock', 'waits': 0, 'align': 0,
                      'n_words': 2, 'ncap': 2,
                      'sha256': evidence.sha(evidence.canonical_words(self.words)),
                      'image_sha256': 'a' * 64}

    def rejects(self, func, *args):
        with self.assertRaises(evidence.EvidenceError):
            func(*args)

    def test_bit50_not_adjacent_bit49_or51(self):
        words = [f'{1 << bit:016x}' for bit in (49, 50, 51)]
        self.assertEqual([r['lock_n'] for r in evidence.decode_words(words)], [0, 1, 0])

    def test_reset_bit55_retains_all_original_indices(self):
        rows = evidence.decode_words([f'{(1 << 55) | (1 << 50):016x}', '0000000000000000'])
        self.assertEqual(rows, [{'idx': 0, 'lock_n': 1, 'reset': 1}, {'idx': 1, 'lock_n': 0, 'reset': 0}])

    def test_malformed_short_and_overflow_words_reject(self):
        for words in (['0'], ['1' * 17], ['z' * 16], [1], [], '0000000000000000'):
            with self.subTest(words=words):
                self.rejects(evidence.decode_words, words)

    def test_canonical_stream_exact_fixed_format(self):
        self.assertEqual(evidence.canonical_words(['0004ABCDEF012345']), b'0004abcdef012345\n')
        self.rejects(evidence.decode_words, ['0004abcdef012345\n'])

    def test_self_comparison_only_tool_validation(self):
        self.assertEqual(evidence.compare_pin_rows(self.rows, copy.deepcopy(self.rows)), [])

    def test_every_mismatch_including_reset_row_is_retained(self):
        actual = copy.deepcopy(self.rows)
        for row in actual:
            row['lock_n'] ^= 1
        self.assertEqual([r['idx'] for r in evidence.compare_pin_rows(self.rows, actual)], [0, 1, 2, 3])

    def test_missing_pin_rejects(self):
        actual = copy.deepcopy(self.rows)
        del actual[1]['lock_n']
        self.rejects(evidence.compare_pin_rows, self.rows, actual)

    def test_nonbinary_pin_rejects_no_coercion(self):
        for value in (None, 2, -1, '1', True, 1.0):
            actual = copy.deepcopy(self.rows)
            actual[1]['lock_n'] = value
            with self.subTest(value=value):
                self.rejects(evidence.compare_pin_rows, self.rows, actual)

    def test_missing_index_rejects(self):
        actual = copy.deepcopy(self.rows)
        del actual[2]['idx']
        self.rejects(evidence.compare_pin_rows, self.rows, actual)

    def test_duplicate_index_rejects(self):
        actual = copy.deepcopy(self.rows)
        actual[2]['idx'] = 1
        self.rejects(evidence.compare_pin_rows, self.rows, actual)

    def test_shifted_equal_indices_cannot_fit_offset(self):
        shifted = [{'idx': r['idx'] + 1, 'lock_n': r['lock_n']} for r in self.rows]
        self.rejects(evidence.compare_pin_rows, shifted, copy.deepcopy(shifted))

    def test_truncation_rejects(self):
        self.rejects(evidence.compare_pin_rows, self.rows, self.rows[:-1])

    def test_empty_comparison_rejects(self):
        self.rejects(evidence.compare_pin_rows, [], [])

    def test_legacy11_columns_are_unknown_and_not_comparable(self):
        pin = evidence.legacy_pin([0] * 11)
        self.assertIsNone(pin)
        self.rejects(evidence.compare_pin_rows, [{'idx': 0, 'lock_n': pin}], [{'idx': 0, 'lock_n': 1}])

    def test_socket_core_and_ambiguous_source_reject(self):
        for source in (True, None, 'false', 0):
            data = manifest()
            data['use_core'] = source
            with self.subTest(source=source):
                self.rejects(evidence.validate_manifest, data, 'tf0f')

    def test_divider_mismatch_and_type_reject(self):
        for div in (4, 16, '8', None, True):
            data = manifest()
            data['div'] = div
            self.rejects(evidence.validate_manifest, data, 'tf0f')

    def test_timestamp_missing_or_invalid_reject(self):
        for ts in (None, '', '2026-19-11T22:55:11Z', '2026-08-11'):
            data = manifest()
            data['ts'] = ts
            self.rejects(evidence.validate_manifest, data, 'tf0f')

    def test_unverified_flash_reject(self):
        data = manifest()
        data['flash']['tail']['verify'] = 'UNKNOWN'
        self.rejects(evidence.validate_manifest, data, 'tf0f')

    def test_malformed_flash_and_tail_reject(self):
        for flash in (None, [], {'tail': None}, {'tail': []}):
            data = manifest()
            data['flash'] = flash
            self.rejects(evidence.validate_manifest, data, 'tf0f')

    def test_wrong_source_tool_reject(self):
        self.rejects(evidence.validate_manifest, manifest(), 'iret-tf')

    def test_table_hash_tamper_rejects(self):
        table = dict(self.table, sha256='0' * 64)
        self.rejects(evidence.validate_cell, self.spec, self.words, table, manifest())

    def test_raw_word_tamper_rejects(self):
        words = list(self.words)
        words[1] = '0004000000000000'
        self.rejects(evidence.validate_cell, self.spec, words, self.table, manifest())

    def test_missing_manifest_image_rejects(self):
        data = manifest()
        data['images'] = {}
        self.rejects(evidence.validate_cell, self.spec, self.words, self.table, data)

    def test_conflicting_image_identity_rejects(self):
        data = manifest()
        data['images']['v_lock_a0'] = 'c' * 64
        self.rejects(evidence.validate_cell, self.spec, self.words, self.table, data)

    def test_wrong_word_count_or_requested_length_rejects(self):
        for field in ('n_words', 'ncap'):
            for value in (1, '2'):
                self.rejects(evidence.validate_cell, self.spec, self.words, dict(self.table, **{field: value}), manifest())

    def test_valid_cell_does_not_infer_timing(self):
        rows = evidence.validate_cell(self.spec, self.words, self.table, manifest())
        self.assertEqual([r['lock_n'] for r in rows], [1, 0])

    def test_duplicate_json_and_table_cells_reject(self):
        self.rejects(evidence.parse_json, '{"cell":1,"cell":2}')
        self.rejects(evidence.table_index, [self.table, dict(self.table)])

    def test_sealed_compressed_byte_tamper_rejects(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path = root / 'capture.gz'
            path.write_bytes(b'original')
            inputs = {'capture.gz': evidence.sha(b'original')}
            self.assertEqual(evidence.verify_seal(root, inputs), inputs)
            path.write_bytes(b'changed')
            self.rejects(evidence.verify_seal, root, inputs)

    def test_checkout_variants_exact_only_no_normalization(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            lf, crlf = b'a\nb\n', b'a\r\nb\r\n'
            allowed = [evidence.sha(lf), evidence.sha(crlf)]
            variants = {'source.txt': {'allowed_sha256': allowed, 'git_lf_sha256': allowed[0], 'exact_lf_to_crlf_sha256': allowed[1]}}
            path = root / 'source.txt'
            for data in (lf, crlf):
                path.write_bytes(data)
                self.assertEqual(evidence.verify_seal(root, {'source.txt': allowed[0]}, variants)['source.txt'], evidence.sha(data))
            path.write_bytes(b'a\r\nb\n')
            self.rejects(evidence.verify_seal, root, {'source.txt': allowed[0]}, variants)

    def test_relative_input_path_escape_rejects(self):
        for name in ('../capture', '/capture', 'C:/capture', 'sub\\capture'):
            self.rejects(evidence.repo_path, Path.cwd(), name)

    def test_exact_population_has144_unique_fixed_cells(self):
        specs = evidence.expected_cells()
        self.assertEqual(len(specs), 144)
        self.assertEqual(len({(s['source'], s['cell']) for s in specs}), 144)
        self.assertEqual(sum(s['source'] == 'tf0f' for s in specs), 48)

    def test_malformed_or_missing_inventory_rejects(self):
        for value in (None, [], {}, {'schema': 'native-buslock-evidence-inventory-v1', 'population': 143}):
            self.rejects(evidence.validate_inventory, value, evidence.expected_cells())

    def test_historical_manifest_must_be_in_sealed_closure(self):
        specs = evidence.expected_cells()
        inputs = {s['raw']: 'a' * 64 for s in specs}
        for source in evidence.SOURCES:
            for file in ('manifest.json', 'table.json', 'SHA256SUMS'):
                inputs[f'sw/testdata/{source}/board/{file}'] = 'a' * 64
        self.rejects(evidence.require_sealed_sources, {'inputs': inputs}, specs)
        inputs[evidence.HISTORICAL] = 'b' * 64
        evidence.require_sealed_sources({'inputs': inputs}, specs)

    def fixture_inventory(self):
        specs = evidence.expected_cells()
        cells = []
        for spec in specs:
            original = evidence.HISTORICAL if spec['source'] == 'iret-tf' and spec['probe'] != 'v_lock' else f"sw/testdata/{spec['source']}/board/manifest.json"
            cells.append({**spec, 'raw_path': spec['raw'], 'image_manifest': original})
        return {'schema': 'native-buslock-evidence-inventory-v1', 'population': 144, 'cells': cells}

    def test_historical_source_map_contradiction_rejects(self):
        inventory = self.fixture_inventory()
        evidence.validate_inventory(inventory, evidence.expected_cells())
        control = next(c for c in inventory['cells'] if c['source'] == 'iret-tf' and c['probe'] == 'nop')
        control['image_manifest'] = 'sw/testdata/iret-tf/board/manifest.json'
        self.rejects(evidence.validate_inventory, inventory, evidence.expected_cells())

    def test_duplicate_inventory_cell_cannot_replace_missing_cell(self):
        inventory = self.fixture_inventory()
        inventory['cells'][1] = copy.deepcopy(inventory['cells'][0])
        self.rejects(evidence.validate_inventory, inventory, evidence.expected_cells())

    def test_missing_inventory_cell_rejects(self):
        inventory = self.fixture_inventory()
        inventory['cells'].pop()
        self.rejects(evidence.validate_inventory, inventory, evidence.expected_cells())

    def run_cli_fixture(self, expected, actual):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            paths = [root / 'expected.jsonl', root / 'actual.jsonl']
            evidence.write_rows(paths[0], expected)
            evidence.write_rows(paths[1], actual)
            result = subprocess.run([sys.executable, str(Path(evidence.__file__)), '--work', str(root / 'attempts'),
                                     'compare', *map(str, paths)], capture_output=True, text=True)
            receipt_paths = list((root / 'attempts').glob('compare_*/receipt.json'))
            self.assertEqual(len(receipt_paths), 1, result.stderr)
            receipt = json.loads(receipt_paths[0].read_text(encoding='utf-8'))
            for name, digest in receipt['outputs'].items():
                self.assertEqual(evidence.sha((receipt_paths[0].parent / name).read_bytes()), digest)
            return result.returncode, receipt, receipt_paths[0].parent.joinpath('comparison.json').read_text(encoding='utf-8') if 'comparison.json' in receipt['outputs'] else None

    def test_cli_pin_mismatch_nonzero_and_receipt_preserves_every_edge(self):
        actual = [{'idx': r['idx'], 'lock_n': r['lock_n'] ^ 1} for r in self.rows]
        code, receipt, comparison = self.run_cli_fixture(self.rows, actual)
        self.assertEqual(code, 1)
        self.assertEqual(receipt['status'], 'FAIL')
        self.assertEqual(len(json.loads(comparison)['mismatches']), 4)

    def test_cli_missing_pin_nonzero_has_failure_receipt(self):
        code, receipt, comparison = self.run_cli_fixture(self.rows, [{'idx': 0}])
        self.assertEqual(code, 1)
        self.assertIn('missing/nonbinary', receipt['error'])
        self.assertIsNone(comparison)

    def test_cli_self_comparison_is_scoped_tool_pass(self):
        code, receipt, comparison = self.run_cli_fixture(self.rows, self.rows)
        self.assertEqual(code, 0)
        self.assertEqual(receipt['status'], 'PASS')
        self.assertIn('self-comparison is tool validation only', json.loads(comparison)['scope'])

    def test_low_spans_keep_tail_and_original_indices(self):
        self.assertEqual(evidence.low_spans(self.rows), [[1, 2]])
        self.assertEqual(evidence.low_spans(self.rows[:-1]), [[1, 2]])


if __name__ == '__main__':
    unittest.main(verbosity=2)
