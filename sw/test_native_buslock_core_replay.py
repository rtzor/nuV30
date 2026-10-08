#!/usr/bin/env python3
"""Synthetic falsifiers for replay framing, custody and actual-core receipts."""
import copy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import native_buslock_core_replay as r


def words():
    return [((1 << 55) if i < 33 else 0) | (1 << 50) | (7 << 40) | (7 << 43)
            for i in range(4096)]


def text(values):
    return ''.join(f'{v:016x}\n' for v in values)


def native():
    return r.decode_raw(text(words()))[33:]


def case(random=False):
    return {'evt': {'delay': 1158, 'hold': 300, 'pin': 0, 'hold_bits': 12, 'hold_applied': 300},
            'waits': {'wrand': random, 'wmax': 2 if random else None,
                      'wseed': 33036 if random else None, 'fixed': None if random else 1}}


class Falsifiers(unittest.TestCase):
    def rejects(self, fn, *args):
        with self.assertRaises((r.ReplayError, OSError, ValueError)):
            fn(*args)

    def test_valid_complete_absolute_frames(self):
        n, c = native(), r.decode_raw(text(words()))
        self.assertEqual(r.compare(n, c), ([], []))

    def test_bit50_independent_adjacent_bits(self):
        w = words(); w[44] &= ~(1 << 50); w[44] |= (1 << 49) | (1 << 51)
        self.assertEqual(r.decode_raw(text(w))[44]['lock_n'], 0)

    def test_constant_high_fails_all_native_lows(self):
        n, c = native(), r.decode_raw(text(words()))
        for i in (33, 34, 400, 4095): n[i-33]['lock_n'] = 0
        pins, _ = r.compare(n, c)
        self.assertEqual([p['idx'] for p in pins], [33, 34, 400, 4095])

    def test_both_shifted_edges_retained(self):
        n, c = native(), r.decode_raw(text(words()))
        n[100-33]['lock_n'] = 0; c[101]['lock_n'] = 0
        self.assertEqual([p['idx'] for p in r.compare(n, c)[0]], [100, 101])

    def test_busgrid_diagnostic_independent_of_pin(self):
        n, c = native(), r.decode_raw(text(words())); c[77]['ad_data'] = 1234
        pins, grid = r.compare(n, c)
        self.assertEqual(pins, []); self.assertEqual(grid, [{'idx': 77, 'fields': {'ad_data': [0,1234]}}])

    def test_missing_pin_rejected(self):
        n = native(); del n[0]['lock_n']; self.rejects(r.native_rows, n)

    def test_boolean_pin_rejected(self):
        n = native(); n[0]['lock_n'] = True; self.rejects(r.native_rows, n)

    def test_string_pin_rejected(self):
        n = native(); n[0]['lock_n'] = '1'; self.rejects(r.native_rows, n)

    def test_float_pin_rejected(self):
        n = native(); n[0]['lock_n'] = 1.0; self.rejects(r.native_rows, n)

    def test_nonbinary_pin_rejected(self):
        n = native(); n[0]['lock_n'] = 2; self.rejects(r.native_rows, n)

    def test_duplicate_absolute_index(self):
        n = native(); n[1]['idx'] = 33; self.rejects(r.native_rows, n)

    def test_shifted_native_not_rebased(self):
        n = native()
        for a in n: a['idx'] += 1
        self.rejects(r.native_rows, n)

    def test_boolean_index_rejected(self):
        n = native(); n[0]['idx'] = True; self.rejects(r.native_rows, n)

    def test_native_truncation(self):
        self.rejects(r.native_rows, native()[:-1])

    def test_native_unknown_reset_not_invented(self):
        n = native(); n[0]['rst'] = 1; self.rejects(r.native_rows, n)

    def test_candidate_truncation(self):
        self.rejects(r.decode_raw, text(words()[:-1]))

    def test_candidate_excess(self):
        self.rejects(r.decode_raw, text(words()+[0]))

    def test_candidate_bad_width(self):
        self.rejects(r.decode_raw, text(words()).replace('00', '0', 1))

    def test_candidate_unknown_or_negative(self):
        for s in ('x'*16, '-000000000000001'):
            self.rejects(r.decode_raw, s+'\n'+text(words()[1:]))

    def test_candidate_blank_line(self):
        self.rejects(r.decode_raw, '\n'+text(words()))

    def test_first_nonreset32_rejected(self):
        w = words(); w[32] &= ~(1 << 55); self.rejects(r.decode_raw, text(w))

    def test_first_nonreset34_rejected(self):
        w = words(); w[33] |= 1 << 55; self.rejects(r.decode_raw, text(w))

    def test_later_reset_glitch(self):
        w = words(); w[4095] |= 1 << 55; self.rejects(r.decode_raw, text(w))

    def test_candidate_indices_not_fitted(self):
        c = r.decode_raw(text(words())); c[33]['idx'] = 34; self.rejects(r.compare, native(), c)

    def test_fixed_wait_exact(self):
        args, ev, wr = r.profile(case(), 0x500)
        self.assertIn('+waits=1', args); self.assertNotIn('+wrand=1', args)
        self.assertIsNone(wr); self.assertEqual(ev, 0x882c0486)

    def test_random_wait_exact(self):
        args, _, wr = r.profile(case(True), 0x500)
        self.assertIn('+wseed=810c', args); self.assertIn('+wmax=2', args)
        self.assertEqual(wr, 0x810c0021)

    def test_no_fixed_fallback_for_bad_random(self):
        c = case(True); c['waits']['wseed'] = None; self.rejects(r.profile, c, 0x500)

    def test_ambiguous_waits(self):
        c = case(True); c['waits']['fixed'] = 0; self.rejects(r.profile, c, 0x500)

    def test_unsupported_wvec(self):
        c = case(); c['wvec'] = [0]; self.rejects(r.profile, c, 0x500)

    def test_truncated_8bit_hold(self):
        c = case(); c['evt']['hold_applied'] = 44; self.rejects(r.profile, c, 0x500)

    def test_event_out_of_range(self):
        for key,val in [('pin', 3), ('hold',4096), ('delay',65536)]:
            c = case(); c['evt'][key] = val; self.rejects(r.profile, c, 0x500)

    def test_event_wrong_readback(self):
        self.rejects(r.validate_readbacks, 'SYS DONE 4096 records fired=1 vecused=0', 0x500, 0x882c0486, None)

    def test_random_wrong_readback(self):
        out='SYS EVT EVT  ADDR=00000500 CFG=882c0486  readback ADDR=00000500 CFG=882c0486\nSYS REG WRAND=810c0021 readback 810c0011\nSYS DONE 4096 records fired=1 vecused=0'
        self.rejects(r.validate_readbacks, out, 0x500, 0x882c0486, 0x810c0021)

    def test_success_readbacks_exact(self):
        out='SYS EVT EVT  ADDR=00000500 CFG=882c0486  readback ADDR=00000500 CFG=882c0486\nSYS REG WRAND=810c0021 readback 810c0021\nSYS DONE 4096 records fired=1 vecused=0'
        r.validate_readbacks(out, 0x500, 0x882c0486, 0x810c0021)

    def test_default_control_recipe(self):
        cmd = r.build_command(Path('C:/build'))
        self.assertIn('-DV30_MUXED_AD', cmd)
        self.assertNotIn('-DX1_AD_RETENTION', cmd)
        self.assertFalse(any('UNOPTFLAT' in x for x in cmd))
        self.assertEqual(cmd[cmd.index('--top-module')+1], 'tb_sys')
        self.assertTrue({'hdl/rtl/ucore/ucrom.hex','hdl/rtl/ucore/ucdecode.hex'}.issubset(r.source_files()[1]))

    def test_wrong_macro_top_receipt(self):
        with tempfile.TemporaryDirectory() as td:
            p=Path(td); f=p/'input'; f.write_text('x'); out=p/'Vtb_sys.exe'; out.write_bytes(b'binary')
            cmd=r.build_command(p); cmd.append('-DX1_AD_RETENTION')
            rec={'schema':r.SCHEMA,'kind':'build','tool_status':'PASS','compile_command':cmd,
                 'inputs':{str(f):r.sha(f.read_bytes())},'outputs':{out.name:r.sha(out.read_bytes())}}
            r.write_json(p/'receipt.json',rec)
            with self.assertRaisesRegex(r.ReplayError,'wrong CONTROL build recipe/top/macro'):
                r.verify_receipt(p/'receipt.json',True)

    def test_wrong_top_receipt(self):
        with tempfile.TemporaryDirectory() as td:
            p=Path(td); cmd=r.build_command(p); cmd[cmd.index('--top-module')+1]='fake_core'
            r.write_json(p/'receipt.json',{'schema':r.SCHEMA,'kind':'build','tool_status':'PASS','compile_command':cmd})
            with self.assertRaisesRegex(r.ReplayError,'wrong CONTROL build recipe/top/macro'):
                r.verify_receipt(p/'receipt.json',True)

    def test_stale_input_and_output(self):
        with tempfile.TemporaryDirectory() as td:
            p=Path(td); f=p/'input'; f.write_bytes(b'x'); out=p/'result'; out.write_bytes(b'y')
            rec={'schema':r.SCHEMA,'kind':'replay','tool_status':'PASS','inputs':{str(f):r.sha(b'x')},'outputs':{'result':r.sha(b'y')}}
            r.check_hashes(rec['inputs'])
            f.write_bytes(b'z'); self.rejects(r.check_hashes,rec['inputs'])
            f.write_bytes(b'x'); out.write_bytes(b'z'); self.assertNotEqual(r.sha(out.read_bytes()), rec['outputs']['result'])

    def test_missing_rom_seal_and_binary(self):
        with tempfile.TemporaryDirectory() as td:
            p=Path(td); f=p/'input'; f.write_bytes(b'x'); out=p/'Vtb_sys.exe'; out.write_bytes(b'x')
            rec={'schema':r.SCHEMA,'kind':'build','tool_status':'PASS','compile_command':r.build_command(p),
                 'inputs':{str(f):r.sha(b'x')},'outputs':{out.name:r.sha(b'x')}}
            r.write_json(p/'receipt.json',rec); self.rejects(r.verify_receipt,p/'receipt.json',True)

    def test_self_referential_receipt_rejected(self):
        with tempfile.TemporaryDirectory() as td:
            p=Path(td); f=p/'input'; f.write_bytes(b'x')
            r.write_json(p/'receipt.json',{'schema':r.SCHEMA,'tool_status':'PASS','inputs':{str(f):r.sha(b'x')},'outputs':{'receipt.json':r.sha(b'x')}})
            self.rejects(r.verify_receipt,p/'receipt.json')

    def test_source_path_escape(self):
        for p in ('../capture', '/capture', 'C:/capture', 'sw\\capture'):
            self.rejects(r.repo_path,p)

    def test_duplicate_json_key(self):
        with tempfile.TemporaryDirectory() as td:
            p=Path(td)/'x.json'; p.write_text('{"pin":0,"pin":1}')
            self.rejects(r.read_json,p)

    def test_missing_population_seal(self):
        inv={'schema':'native-buslock-core-replay-inventory-v1','cases':[]}
        with patch.object(r,'read_json',return_value=inv): self.rejects(r.inventory,{})

    def test_image_drift_hard_failure(self):
        import gzip
        bank=json.loads(gzip.decompress((r.ROOT/'tests/v30/fuzz_bank/mc1/seeds/soup_1057_70d953d7a847.json.gz').read_bytes()))
        bank['image_sha256']='0'*64
        with tempfile.TemporaryDirectory() as td:
            src=r.historical(r.read_json(r.ROOT/r.INVENTORY),Path(td))
            self.rejects(r.reconstruct,src,bank)

    def test_original_short_git_identity(self):
        # Metadata-only original read; no heldout pin outcomes.
        inv=r.read_json(r.ROOT/r.INVENTORY)
        rows,bank=r.source_case(inv['cases'][0])
        self.assertEqual(bank['gen_git'],'4386ff7'); self.assertEqual(len(rows),4063)

    def test_wrong_historical_generator_rejected(self):
        self.rejects(r.resolve_gen,'e383a5b930331ad5f6423120863624b3a431b631')

    def test_nonhex_historical_generator_rejected(self):
        self.rejects(r.resolve_gen,'HEAD')

    def test_changed_historical_blob_rejected(self):
        inv=r.read_json(r.ROOT/r.INVENTORY)
        inv['generation']['historical_sources'][0]['sha256']='0'*64
        with tempfile.TemporaryDirectory() as td:
            self.rejects(r.historical,inv,Path(td))

    def test_wrong_native_wait_metadata_rejected(self):
        inv=r.read_json(r.ROOT/r.INVENTORY)
        c=inv['cases'][0]; c['waits']['fixed']=1
        self.rejects(r.source_case,c)

    def test_candidate_bool_index_direct_api(self):
        c=r.decode_raw(text(words())); c[1]['idx']=True
        self.rejects(r.compare,native(),c)

    def test_candidate_later_reset_direct_api(self):
        c=r.decode_raw(text(words())); c[300]['rst']=1
        self.rejects(r.compare,native(),c)

    def test_changed_normative_inventory(self):
        # Even self-consistent re-sealing cannot redefine registered source bytes.
        actual=r.repo_path
        with tempfile.TemporaryDirectory() as td:
            p=Path(td)/'inventory'; p.write_text('{"inputs":{"tampered":"newhash"}}')
            with patch.object(r,'repo_path',side_effect=lambda n:p if n==r.INVENTORY else actual(n)):
                self.rejects(r.registration)

    def test_vacuous_receipt_rejected(self):
        with tempfile.TemporaryDirectory() as td:
            p=Path(td); r.write_json(p/'receipt.json',{'schema':r.SCHEMA,'kind':'replay','tool_status':'PASS','inputs':{},'outputs':{}})
            self.rejects(r.verify_receipt,p/'receipt.json')


if __name__ == '__main__':
    unittest.main(verbosity=2)
