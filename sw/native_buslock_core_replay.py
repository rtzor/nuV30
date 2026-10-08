#!/usr/bin/env python3
"""Receipted actual-core replay of 19 retained native BUSLOCK observations."""
import argparse
import ast
from datetime import datetime, timezone
import gzip
import hashlib
import importlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import types

ROOT = Path(__file__).resolve().parents[1]
SCHEMA = 'native-buslock-core-replay-v1'
PREREG = 'docs/notes/native_buslock_core_replay_prereg_2026-10-08.md'
INVENTORY = 'docs/notes/native_buslock_core_replay_inventory_2026-10-08.json'
GEN = '4386ff71c2bcb93b87827da8d53757ca11cb00d7'
KEYS = (1057, 1105, 1110, 1147, 1150, 1157, 1184, 1189, 1191, 1192,
        1201, 1206, 1210, 1212, 1248, 1251, 1259, 1284, 1285)
HARNESS = ('capture_buf', 'hps_axi_slave', 'iords_buf', 'nec_bus',
           'system_large', 'test_mem', 'wvec_buf')
PURE = ('testimage', 'v30asm', 'gen_seq', 'gen_soup', 'gen_raw', 'optable', 'fuzz_cov')
WORD = re.compile(r'[0-9a-fA-F]{16}\Z')
# Exact registered Git LF and exact CRLF checkout identities, never normalization.
REGISTERED = {
    PREREG: ('1d8a02e6e73483f2c81d0c4d48994600629e85659dd091e11735f057dd92ca42',
             'e912d20689de013ed88319a81cd0949eb0cfde9a56ee0d1872df1def1b4c9bc3'),
    INVENTORY: ('15a1b8353c23fa783cb0ccb3e0ffc8d9e9c9d6b765383a34184bb6c72deb24da',
                'e95c27fefa436c806bbd2e17ebcd58ddf9b273560e06ab4f23ecfee83a1058ac')}


class ReplayError(ValueError):
    pass


def sha(data):
    return hashlib.sha256(data).hexdigest()


def unique(pairs):
    obj = {}
    for k, v in pairs:
        if k in obj:
            raise ReplayError('duplicate JSON key: ' + k)
        obj[k] = v
    return obj


def read_json(path):
    return json.loads(path.read_text(encoding='utf-8'), object_pairs_hook=unique)


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n', encoding='utf-8')


def jsonl(path, rows):
    with path.open('w', encoding='utf-8', newline='\n') as f:
        for row in rows:
            f.write(json.dumps(row, separators=(',', ':')) + '\n')


def repo_path(name):
    if not isinstance(name, str) or '\\' in name or ':' in name:
        raise ReplayError('invalid repository path')
    p = PurePosixPath(name)
    path = (ROOT / name).resolve()
    if p.is_absolute() or '..' in p.parts or not path.is_relative_to(ROOT):
        raise ReplayError('repository path escape')
    return path


def integer(value, low, high, label):
    if type(value) is not int or not low <= value <= high:
        raise ReplayError('invalid ' + label)
    return value


def source_files():
    u = 'hdl/rtl/ucore/'
    rtl = ([u + 'v30u_ss_pkg.sv'] + ['hdl/rtl/' + n + '.sv' for n in HARNESS]
           + [u + n + '.sv' for n in ('v30_core', 'v30u_biu', 'v30u_ucrom', 'v30u_eu')]
           + ['hdl/tb/tb_sys.sv'])
    deps = rtl + [p.relative_to(ROOT).as_posix() for p in sorted((ROOT / u).glob('*.svh'))]
    return rtl, deps + [u + 'ucrom.hex', u + 'ucdecode.hex']


def seal(inputs, path):
    path = path.resolve()
    inputs[str(path)] = sha(path.read_bytes())


def check_hashes(paths):
    if not isinstance(paths, dict) or not paths:
        raise ReplayError('empty/malformed artifact closure')
    for name, wanted in paths.items():
        if sha(Path(name).read_bytes()) != wanted:
            raise ReplayError('changed artifact: ' + name)


def registration():
    for name, allowed in REGISTERED.items():
        if sha(repo_path(name).read_bytes()) not in allowed:
            raise ReplayError('committed registration identity changed: ' + name)


def native_rows(rows):
    if not isinstance(rows, list) or len(rows) != 4063:
        raise ReplayError('native rows must be exactly4063')
    for idx, r in enumerate(rows, 33):
        if not isinstance(r, dict) or type(r.get('idx')) is not int or r['idx'] != idx:
            raise ReplayError('native absolute index drift')
        integer(r.get('lock_n'), 0, 1, 'native lock_n')
        if type(r.get('rst')) is not int or r['rst'] != 0:
            raise ReplayError('native nonreset frame invalid')
        for key, maximum in [('ad_addr', 0xfffff), ('ad_data', 0xffff), ('ps', 15),
                             ('bs_early', 7), ('bs_late', 7), ('qs', 3),
                             ('ube_n', 1), ('rd_n', 1), ('t', 5)]:
            integer(r.get(key), 0, maximum, 'native ' + key)
    return rows


def decode_raw(text):
    lines = text.splitlines()
    if len(lines) != 4096 or any(not WORD.fullmatch(line) for line in lines):
        raise ReplayError('candidate must contain4096 exact64-bit words')
    rows = []
    for idx, line in enumerate(lines):
        w = int(line, 16)
        rows.append({'idx': idx, 'ad_addr': w & 0xfffff, 'ad_data': (w >> 20) & 0xffff,
                     'ps': (w >> 36) & 15, 'bs_early': (w >> 40) & 7,
                     'bs_late': (w >> 43) & 7, 'qs': (w >> 46) & 3,
                     'rd_n': (w >> 48) & 1, 'ube_n': (w >> 49) & 1,
                     'lock_n': (w >> 50) & 1, 'rst': (w >> 55) & 1,
                     't': (w >> 56) & 7})
    if any(r['rst'] != int(r['idx'] < 33) for r in rows):
        raise ReplayError('candidate RESET map drift; expected first nonreset33, no offset allowed')
    return rows


def compare(native, candidate):
    native_rows(native)
    if len(candidate) != 4096 or any(type(r.get('idx')) is not int or r['idx'] != i for i, r in enumerate(candidate)):
        raise ReplayError('candidate absolute index drift')
    if any(type(r.get('rst')) is not int or r['rst'] != int(i < 33) for i, r in enumerate(candidate)):
        raise ReplayError('candidate RESET map drift; no offset allowed')
    pins, grid = [], []
    fields = ('t', 'bs_early', 'bs_late', 'qs', 'ube_n', 'rd_n', 'ad_addr', 'ad_data', 'ps')
    for n in native:
        c = candidate[n['idx']]
        integer(c.get('lock_n'), 0, 1, 'candidate lock_n')
        if n['lock_n'] != c['lock_n']:
            pins.append({'idx': n['idx'], 'native': n['lock_n'], 'candidate': c['lock_n']})
        diff = {f: [n[f], c[f]] for f in fields if n[f] != c[f]}
        if diff:
            grid.append({'idx': n['idx'], 'fields': diff})
    return pins, grid


def profile(case, anchor):
    integer(anchor, 0, 0xfffff, 'image anchor')
    e, w = case.get('evt'), case.get('waits')
    if not isinstance(e, dict) or not isinstance(w, dict) or type(w.get('wrand')) is not bool:
        raise ReplayError('malformed event/wait profile')
    for key, high in [('delay', 65535), ('hold', 4095), ('pin', 2)]:
        integer(e.get(key), 0, high, 'event ' + key)
    if e.get('hold_bits') != 12 or e.get('hold_applied') != e['hold'] or e['hold'] != 300:
        raise ReplayError('event must reproduce repaired12-bit hold300')
    if set(w) != {'wrand', 'wmax', 'wseed', 'fixed'} or case.get('wvec'):
        raise ReplayError('unsupported wait flags')
    args = [f'+evaddr={anchor:05x}', f"+evdelay={e['delay']}",
            f"+evhold={e['hold']}", f"+evpin={e['pin']}"]
    if w['wrand']:
        integer(w['wmax'], 0, 15, 'random wait max')
        integer(w['wseed'], 0, 65535, 'random wait seed')
        if w['fixed'] is not None:
            raise ReplayError('ambiguous random/fixed waits')
        args += ['+waits=0', '+wrand=1', f"+wmax={w['wmax']}", f"+wseed={w['wseed']:04x}"]
        wrand = (w['wseed'] << 16) | (w['wmax'] << 4) | 1
    else:
        integer(w['fixed'], 0, 15, 'fixed wait')
        if w['wmax'] is not None or w['wseed'] is not None:
            raise ReplayError('ambiguous fixed/random waits')
        args += [f"+waits={w['fixed']}"]
        wrand = None
    cfg = 0x80000000 | e['delay'] | ((e['hold'] & 255) << 16) | (e['pin'] << 24) | ((e['hold'] >> 8) << 27)
    return args, cfg, wrand


def validate_readbacks(output, anchor, evt, wrand):
    matches = re.findall(r'SYS EVT\s+EVT\s+ADDR=([0-9a-fA-F]{8}) CFG=([0-9a-fA-F]{8})\s+readback ADDR=([0-9a-fA-F]{8}) CFG=([0-9a-fA-F]{8})', output)
    if len(matches) != 1 or [int(x, 16) for x in matches[0]] != [anchor, evt, anchor, evt]:
        raise ReplayError('event readback does not match exact source profile')
    waits = re.findall(r'SYS REG\s+WRAND=([0-9a-fA-F]{8})\s+readback ([0-9a-fA-F]{8})', output)
    if (wrand is None and waits) or (wrand is not None and (len(waits) != 1 or [int(x, 16) for x in waits[0]] != [wrand, wrand])):
        raise ReplayError('wait readback does not match exact source profile')
    if not re.search(r'SYS DONE 4096 records fired=1 vecused=0', output):
        raise ReplayError('capture/event completion witness missing')


def inventory(inputs):
    registration()
    inv = read_json(ROOT / INVENTORY)
    if not isinstance(inv, dict) or inv.get('schema') != 'native-buslock-core-replay-inventory-v1':
        raise ReplayError('inventory schema invalid')
    cases = inv.get('cases')
    if not isinstance(cases, list) or len(cases) != 19:
        raise ReplayError('population must contain19 cases')
    observed = []
    for i, c in enumerate(cases):
        m = re.fullmatch(r'mc1_soup_(\d+)_([0-9a-f]{12})', c.get('name', ''))
        if not m or c.get('cohort') != ('discovery' if i < 3 else 'heldout'):
            raise ReplayError('invalid case identity/cohort')
        observed.append(int(m[1]))
        if (c.get('expected_first_index'), c.get('expected_last_index'), c.get('expected_rows')) != (33, 4095, 4063):
            raise ReplayError('source mapping changed')
        if c.get('gen_commit') != GEN or c.get('cfg_hash') != m[2]:
            raise ReplayError('source genotype changed')
        for f in ('raw_path', 'bank_path', 'sidecar_path'):
            if c[f] not in inv.get('inputs', {}):
                raise ReplayError('missing sealed case source: ' + f)
    if tuple(observed) != KEYS or len(inv.get('inputs', {})) != 66:
        raise ReplayError('closed population/source closure changed')
    for name, expected in inv['inputs'].items():
        p = repo_path(name)
        actual = sha(p.read_bytes())
        allowed = inv.get('checkout_variants', {}).get(name, {}).get('allowed_sha256', [expected])
        if actual not in allowed:
            raise ReplayError('sealed original changed: ' + name)
        seal(inputs, p)
    gen = inv.get('generation', {})
    if gen.get('commit') != GEN or len(gen.get('historical_sources', [])) != 11:
        raise ReplayError('historical generator closure missing')
    return inv


def source_case(c):
    raw = repo_path(c['raw_path']).read_bytes()
    data = gzip.decompress(raw)
    if sha(raw) != c['raw_compressed_sha256'] or sha(data) != c['decoded_json_sha256']:
        raise ReplayError('compressed/decoded native identity mismatch')
    if repo_path(c['sidecar_path']).read_text(encoding='utf-8').strip() != c['sidecar_expected'] or c['sidecar_expected'] != sha(data):
        raise ReplayError('decoded sidecar mismatch')
    native = json.loads(data, object_pairs_hook=unique)
    bank = json.loads(gzip.decompress(repo_path(c['bank_path']).read_bytes()), object_pairs_hook=unique)
    for key in ('cfg_hash', 'image_sha256', 'waits'):
        if native.get(key) != c[key] or bank.get(key) != c[key]:
            raise ReplayError('source metadata contradicts inventory: ' + key)
    if native.get('name') != c['name'] or native.get('evt') != c['evt'] or native.get('captured_utc') != c['captured_utc']:
        raise ReplayError('native capture identity mismatch')
    resolve_gen(bank.get('gen_git'))
    if (bank.get('ov') or {}) != c['ov']:
        raise ReplayError('bank generator provenance mismatch')
    for key in ('delay', 'hold', 'pin'):
        if bank.get('evt', {}).get(key) != c['evt'][key]:
            raise ReplayError('bank event mismatch')
    return native_rows(native.get('rows')), bank


def resolve_gen(recorded_gen):
    if not isinstance(recorded_gen, str) or not re.fullmatch('[0-9a-f]{7,40}', recorded_gen):
        raise ReplayError('invalid bank generator identity')
    resolved = subprocess.check_output(['git', 'rev-parse', '--verify', recorded_gen + '^{commit}'], cwd=ROOT).decode().strip()
    if resolved != GEN:
        raise ReplayError('bank generator provenance mismatch')
    return resolved


def historical(inv, attempt):
    target = attempt / 'historical-source'
    for item in inv['generation']['historical_sources']:
        name = item['git_path']
        repo_path(name)
        data = subprocess.check_output(['git', 'show', GEN + ':' + name], cwd=ROOT)
        blob = hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
        if sha(data) != item['sha256'] or blob != item['git_blob'] or len(data) != item['bytes']:
            raise ReplayError('historical Git object mismatch: ' + name)
        p = target / name
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(data)
    return target


def reconstruct(src, bank):
    saved_path = sys.path[:]
    saved = {n: sys.modules.get(n) for n in PURE}
    try:
        for n in PURE:
            sys.modules.pop(n, None)
        sys.path.insert(0, str(src / 'sw'))
        ti = importlib.import_module('testimage')
        # Only original pure modules are imported; no board/device modules.
        check = ast.parse((src / 'sw/check_seq.py').read_text(encoding='utf-8'))
        compose = next(n for n in check.body if isinstance(n, ast.FunctionDef) and n.name == 'compose')
        checkns = {'testimage': ti}
        exec(compile(ast.Module(body=[compose], type_ignores=[]), 'historical-compose', 'exec'), checkns)
        tree = ast.parse((src / 'sw/fuzz_campaign.py').read_text(encoding='utf-8'))
        body, stopped = [], False
        unsafe = {'check_seq', 'fuzz_classify', 'fuzz_cov', 'fuzz_accept', 'v30run', 'v30ctl'}
        for n in tree.body:
            if isinstance(n, ast.FunctionDef) and n.name == '_weff':
                stopped = True
                break
            if isinstance(n, ast.Import) and any(a.name in unsafe for a in n.names):
                continue
            if isinstance(n, ast.ImportFrom) and n.module in unsafe:
                continue
            body.append(n)
        if not stopped:
            raise ReplayError('historical pure boundary absent')
        vt = ast.parse((src / 'sw/v30ctl.py').read_text(encoding='utf-8'))
        rig = next((ast.literal_eval(n.value) for n in vt.body if isinstance(n, ast.Assign)
                    and any(isinstance(t, ast.Name) and t.id == 'RIG_EVT_HOLD_BITS' for t in n.targets)), None)
        ns = {'__file__': str(src / 'sw/fuzz_campaign.py'), '__name__': 'historical_pure_recipe',
              'check_seq': types.SimpleNamespace(**checkns), 'v30ctl': types.SimpleNamespace(RIG_EVT_HOLD_BITS=rig)}
        exec(compile(ast.Module(body=body, type_ignores=[]), 'historical-pure-recipe', 'exec'), ns)
        cfg = ns['derive_case'](bank['cid'], bank['k'], bank.get('ov') or {})
        g = ns['build'](cfg)
        image, meta = checkns['compose'](g)
        image = bytes(image)
        if len(image) != 65536 or sha(image) != bank['image_sha256'] or cfg['cfg_hash'] != bank['cfg_hash']:
            raise ReplayError('historical complete image/configuration drift')
        if cfg['waits'] != bank['waits'] or any(cfg['evt'][k] != bank['evt'][k] for k in ('delay', 'hold', 'pin')):
            raise ReplayError('historical profile drift')
        return image, meta, cfg
    finally:
        sys.path[:] = saved_path
        for n, value in saved.items():
            sys.modules.pop(n, None)
            if value is not None:
                sys.modules[n] = value


def toolchain(msys, inputs):
    paths = [msys / n for n in ('usr/bin/bash.exe', 'usr/bin/make.exe', 'usr/bin/perl.exe',
                               'ucrt64/bin/verilator', 'ucrt64/bin/verilator_bin.exe',
                               'clang64/bin/clang++.exe', 'clang64/bin/ld.lld.exe')]
    for p in paths:
        seal(inputs, p)
    include = msys / 'ucrt64/share/verilator/include'
    if not (include / 'verilated.h').is_file():
        raise ReplayError('Verilator runtime include closure absent')
    for p in sorted(include.rglob('*')):
        if p.is_file():
            seal(inputs, p)
    seal(inputs, Path(sys.executable))
    git = shutil.which('git')
    if not git:
        raise ReplayError('Git tool absent')
    seal(inputs, Path(git))
    return paths[0]


def invoke(bash, command, log, timeout=1800):
    root = ROOT.as_posix()
    root = '/' + root[0].lower() + root[2:] if os.name == 'nt' else root
    script = 'export PATH=/clang64/bin:/ucrt64/bin:/usr/bin:$PATH; cd ' + shlex.quote(root) + ' && ' + shlex.join(command)
    try:
        r = subprocess.run([str(bash), '-lc', script], capture_output=True, text=True, timeout=timeout)
        output = r.stdout + r.stderr
        log.write_text(output, encoding='utf-8')
    except subprocess.TimeoutExpired as exc:
        output = (exc.stdout or b'') + (exc.stderr or b'')
        log.write_bytes(output if isinstance(output, bytes) else output.encode())
        raise ReplayError('command timeout; full available output retained') from exc
    if r.returncode:
        raise ReplayError('command failed code' + str(r.returncode) + '; see ' + str(log))
    return output


def build_command(build):
    rtl, _ = source_files()
    warnings = ('UNUSEDSIGNAL', 'VARHIDDEN', 'TIMESCALEMOD', 'WIDTHEXPAND', 'BLKSEQ',
                'DECLFILENAME', 'UNUSEDPARAM', 'MULTIDRIVEN', 'PINCONNECTEMPTY', 'PROCASSINIT')
    return ['verilator', '--binary', '--timing', '--assert', '--compiler', 'clang', '-Wall',
            *['-Wno-' + w for w in warnings], '--top-module', 'tb_sys', '-DV30_MUXED_AD',
            '-Ihdl/rtl/ucore', '--Mdir', build.as_posix(), '-CFLAGS', '-std=c++20',
            '-MAKEFLAGS', "CXX=clang++ LINK='env -u LINK clang++' CFG_LDLIBS_THREADS=-pthread OPT_FAST=-O0 OPT_SLOW=-O0", *rtl]


def verify_receipt(path, require_build=False):
    rec = read_json(path)
    if not isinstance(rec, dict) or rec.get('schema') != SCHEMA or rec.get('tool_status') != 'PASS':
        raise ReplayError('unaccepted/malformed artifact receipt')
    if require_build and (rec.get('kind') != 'build' or rec.get('compile_command') != build_command(path.parent)):
        raise ReplayError('wrong CONTROL build recipe/top/macro')
    registration()
    required = {'sw/native_buslock_core_replay.py', 'sw/test_native_buslock_core_replay.py', PREREG, INVENTORY,
                *source_files()[1]}
    if not {str(repo_path(n)) for n in required}.issubset(rec.get('inputs', {})):
        raise ReplayError('missing mandatory tool/test/registration/RTL/ROM closure')
    current_tools = {}
    toolchain(Path(rec['msys_root']), current_tools)
    if not set(current_tools).issubset(rec['inputs']):
        raise ReplayError('missing toolchain/binary closure')
    check_hashes(rec['inputs'])
    outputs = rec.get('outputs')
    if not isinstance(outputs, dict) or 'receipt.json' in outputs or not outputs:
        raise ReplayError('invalid output closure')
    for name, wanted in outputs.items():
        p = path.parent / name
        if '..' in PurePosixPath(name).parts or PurePosixPath(name).is_absolute() or sha(p.read_bytes()) != wanted:
            raise ReplayError('changed output: ' + name)
    if require_build:
        if rec.get('kind') != 'build' or rec.get('compile_command') != build_command(path.parent):
            raise ReplayError('wrong CONTROL build recipe/top/macro')
        expected = set(str(repo_path(n)) for n in source_files()[1])
        if not expected.issubset(rec['inputs']):
            raise ReplayError('missing RTL/runtime ROM closure')
        binary = path.parent / 'Vtb_sys.exe'
        if outputs.get(binary.name) != sha(binary.read_bytes()):
            raise ReplayError('wrong/missing actual-core binary')
    elif rec.get('kind') == 'replay':
        build_receipt = Path(rec['build_receipt'])
        verify_receipt(build_receipt, True)
        binary = build_receipt.parent / 'Vtb_sys.exe'
        if not {str(build_receipt), str(binary)}.issubset(rec['inputs']):
            raise ReplayError('missing actual-core build/binary linkage')
        inv = inventory({})
        required_sources = {str(repo_path(n)) for n in inv['inputs']}
        if not required_sources.issubset(rec['inputs']):
            raise ReplayError('missing original source closure')
        summary = read_json(path.parent / 'summary.json')
        if len(summary.get('cases', [])) != 19 or summary.get('compared_rows') != 77197:
            raise ReplayError('incomplete replay receipt')
        names = [c['name'] for c in inv['cases']]
        if [c.get('name') for c in summary['cases']] != names or any(c.get('tool_status') != 'PASS' for c in summary['cases']):
            raise ReplayError('wrong/incomplete replay population')
        expected_status = 'FAIL' if any(c.get('pin_mismatches', -1) > 0 for c in summary['cases']) else 'PASS'
        if (summary.get('native_status') != expected_status or rec.get('native_status') != expected_status
                or any(c.get('compared') != 4063 or type(c.get('pin_mismatches')) is not int
                       or c['pin_mismatches'] < 0 or c.get('native_status') != ('FAIL' if c['pin_mismatches'] else 'PASS')
                       for c in summary['cases'])
                or summary.get('pin_mismatches') != sum(c['pin_mismatches'] for c in summary['cases'])):
            raise ReplayError('native verdict/count contradiction')
        files = ('image.bin', 'image.hex', 'program.json', 'command.json', 'run.log', 'native.jsonl',
                 'candidate.raw.hex', 'candidate.jsonl', 'pin-mismatches.jsonl', 'busgrid-mismatches.jsonl',
                 'literal-high-mismatches.jsonl', 'summary.json')
        if not {'summary.json', *[name + '/' + f for name in names for f in files]}.issubset(outputs):
            raise ReplayError('missing complete capture/comparison outputs')
    else:
        raise ReplayError('wrong receipt kind')
    return rec


def replay(inv, attempt, build_receipt, bash, inputs):
    verify_receipt(build_receipt, True)
    seal(inputs, build_receipt)
    build_rec = read_json(build_receipt)
    inputs.update(build_rec['inputs'])
    binary = build_receipt.parent / 'Vtb_sys.exe'
    seal(inputs, binary)
    src = historical(inv, attempt)
    results = []
    for case in inv['cases']:
        folder = attempt / case['name']
        folder.mkdir()
        result = {'name': case['name'], 'cohort': case['cohort'], 'tool_status': 'FAIL', 'native_status': 'FAIL'}
        try:
            native, bank = source_case(case)
            jsonl(folder / 'native.jsonl', native)
            image, meta, cfg = reconstruct(src, bank)
            (folder / 'image.bin').write_bytes(image)
            image_path = folder / 'image.hex'
            image_path.write_text(''.join(f'{b:02x}\n' for b in image), encoding='ascii')
            write_json(folder / 'program.json', {'cfg': cfg, 'metadata': meta,
                                                'image_sha256': sha(image), 'source': case})
            cap = folder / 'candidate.raw.hex'
            args, evt, wrand = profile(case, meta['anchor_linear'])
            command = [binary.as_posix(), '+img=' + image_path.as_posix(), '+cap=' + cap.as_posix(),
                       '+ncap=4096', '+div=8', *args]
            write_json(folder / 'command.json', {'argv': command, 'expected_evt_cfg': evt,
                                                 'expected_wrand': wrand, 'mapping': 'direct absolute index; offset0'})
            output = invoke(bash, command, folder / 'run.log', timeout=180)
            validate_readbacks(output, meta['anchor_linear'], evt, wrand)
            candidate = decode_raw(cap.read_text(encoding='ascii'))
            jsonl(folder / 'candidate.jsonl', candidate)
            pins, grid = compare(native, candidate)
            jsonl(folder / 'pin-mismatches.jsonl', pins)
            jsonl(folder / 'busgrid-mismatches.jsonl', grid)
            literal = [{'idx': r['idx'], 'native': r['lock_n'], 'literal_prediction': 1}
                       for r in native if r['lock_n'] != 1]
            jsonl(folder / 'literal-high-mismatches.jsonl', literal)
            result.update(tool_status='PASS', native_status='FAIL' if pins else 'PASS',
                          compared=4063, pin_mismatches=len(pins), busgrid_rows=len(grid),
                          literal_high_mismatches=len(literal), candidate_raw_words=4096,
                          first_nonreset=33, native_unknown_indices=[0, 32])
        except (ReplayError, OSError, ValueError, KeyError, TypeError, AttributeError, StopIteration) as exc:
            result['error'] = str(exc)
        write_json(folder / 'summary.json', result)
        results.append(result)
        print(case['name'] + ' tool=' + result['tool_status'] + ' native=' + result['native_status'], flush=True)
    summary = {'cases': results, 'tool_status': 'PASS' if all(r['tool_status'] == 'PASS' for r in results) else 'FAIL',
               'native_status': 'PASS' if all(r['native_status'] == 'PASS' for r in results) else 'FAIL',
               'registered_rows': 77197, 'compared_rows': sum(r.get('compared', 0) for r in results),
               'pin_mismatches': sum(r.get('pin_mismatches', 0) for r in results),
               'scope': 'actual production core pin comparison; busgrid diagnostics do not imply architectural correctness'}
    write_json(attempt / 'summary.json', summary)
    return summary


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', default='../work/native-buslock-rmw-validation/attempts')
    parser.add_argument('--msys-root', type=Path, default=Path('C:/msys64'))
    sub = parser.add_subparsers(dest='command', required=True)
    b = sub.add_parser('build')
    b.add_argument('--compiler', choices=['clang'], default='clang')
    r = sub.add_parser('replay')
    r.add_argument('--build-receipt', required=True, type=Path)
    v = sub.add_parser('verify')
    v.add_argument('receipt', type=Path)
    args = parser.parse_args(argv)
    if args.command == 'verify':
        verify_receipt(args.receipt.resolve(), read_json(args.receipt).get('kind') == 'build')
        print('VERIFIED ' + str(args.receipt))
        return 0
    work = (ROOT / args.work).resolve()
    work.mkdir(parents=True, exist_ok=True)
    attempt = Path(tempfile.mkdtemp(prefix=args.command + '_', dir=work))
    inputs, extra, error = {}, {}, None
    tool_status = native_status = 'FAIL'
    try:
        registration()
        for name in ('sw/native_buslock_core_replay.py', 'sw/test_native_buslock_core_replay.py', PREREG, INVENTORY):
            p = repo_path(name)
            seal(inputs, p)
            snapshot = attempt / 'input-snapshot' / name
            snapshot.parent.mkdir(parents=True, exist_ok=True)
            snapshot.write_bytes(p.read_bytes())
        bash = toolchain(args.msys_root.resolve(), inputs)
        versions = invoke(bash, ['bash', '-c', 'verilator --version; clang++ --version; make --version; perl --version'], attempt / 'toolchain.log')
        extra['toolchain_versions'] = versions
        extra['msys_root'] = str(args.msys_root.resolve())
        if args.command == 'build':
            for name in source_files()[1]:
                seal(inputs, repo_path(name))
            command = build_command(attempt)
            extra['compile_command'] = command
            invoke(bash, command, attempt / 'build.log')
            if not (attempt / 'Vtb_sys.exe').is_file():
                raise ReplayError('actual-core executable absent')
            tool_status, native_status = 'PASS', 'NOT_RUN'
        else:
            extra['build_receipt'] = str(args.build_receipt.resolve())
            inv = inventory(inputs)
            summary = replay(inv, attempt, args.build_receipt.resolve(), bash, inputs)
            tool_status, native_status = summary['tool_status'], summary['native_status']
        check_hashes(inputs)
    except (ReplayError, OSError, ValueError, KeyError, TypeError, AttributeError, StopIteration, subprocess.CalledProcessError) as exc:
        error = str(exc)
        tool_status = 'FAIL'
        write_json(attempt / 'failure.json', {'error': error})
    outputs = {p.relative_to(attempt).as_posix(): sha(p.read_bytes()) for p in attempt.rglob('*') if p.is_file()}
    receipt = {'schema': SCHEMA, 'kind': args.command, 'tool_status': tool_status, 'native_status': native_status,
               'inputs': inputs, 'outputs': outputs, 'error': error, 'command': [sys.executable, *sys.argv],
               'prereg_commit': 'e383a5b930331ad5f6423120863624b3a431b631',
               'created_utc': datetime.now(timezone.utc).isoformat(), **extra}
    write_json(attempt / 'receipt.json', receipt)
    print('tool=' + tool_status + ' native=' + native_status + ' ' + str(attempt / 'receipt.json'))
    return 0 if tool_status == 'PASS' and native_status in ('PASS', 'NOT_RUN') else 1


if __name__ == '__main__':
    sys.exit(main())
